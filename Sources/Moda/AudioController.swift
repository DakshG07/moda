import AudioToolbox
import CoreAudio
import Foundation

protocol VolumeControlling: AnyObject, Sendable {
  func canHandle(_ key: VolumeKey) -> Bool
  func perform(_ action: VolumeAction) -> VolumeSnapshot?
  func currentSnapshot() -> VolumeSnapshot?
}

final class AudioController: VolumeControlling, @unchecked Sendable {
  private enum VolumeControl {
    case single(selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement)
    case channels([AudioObjectPropertyElement])
  }

  private let lock = NSLock()
  private var rememberedVolumeByDevice: [AudioDeviceID: Float32] = [:]

  func canHandle(_ key: VolumeKey) -> Bool {
    lock.withLock {
      guard let device = defaultOutputDevice(), volumeControl(for: device) != nil else {
        return false
      }
      let anyMute = muteAddress(device: device, requireSettable: false)
      let writableMute = muteAddress(device: device, requireSettable: true)
      switch key {
      case .up, .down:
        let currentlyMuted = readMute(device: device) ?? false
        return !currentlyMuted || anyMute == nil || writableMute != nil
      case .mute:
        // A read-only mute property cannot be safely emulated with volume alone.
        return anyMute == nil || writableMute != nil
      }
    }
  }

  func perform(_ action: VolumeAction) -> VolumeSnapshot? {
    lock.withLock {
      guard
        let device = defaultOutputDevice(),
        let control = volumeControl(for: device),
        var volume = readVolume(device: device, control: control)
      else { return nil }

      let anyMute = muteAddress(device: device, requireSettable: false)
      let nativeMute = muteAddress(device: device, requireSettable: true)
      let wasMuted = readMute(device: device) ?? isEmulatedMuted(device: device, volume: volume)

      if anyMute != nil, nativeMute == nil {
        switch action {
        case .toggleMute:
          return nil
        case .increase(_), .decrease(_), .set(_):
          if wasMuted { return nil }
        }
      }

      let mutation = VolumeStateReducer.apply(
        action,
        volume: volume,
        isMuted: wasMuted,
        rememberedVolume: rememberedVolumeByDevice[device],
        usesNativeMute: nativeMute != nil
      )
      volume = mutation.volume

      if let remembered = mutation.rememberedVolume {
        rememberedVolumeByDevice[device] = remembered
      } else {
        rememberedVolumeByDevice.removeValue(forKey: device)
      }

      switch action {
      case .increase(_), .decrease(_), .set(_):
        if wasMuted, let nativeMute {
          guard writeUInt32(0, device: device, address: nativeMute) else { return nil }
        }
        guard writeVolume(volume, device: device, control: control) else { return nil }

      case .toggleMute:
        if let nativeMute {
          guard writeUInt32(mutation.isMuted ? 1 : 0, device: device, address: nativeMute) else {
            return nil
          }
        } else {
          guard writeVolume(volume, device: device, control: control) else { return nil }
        }
      }

      let confirmedVolume = readVolume(device: device, control: control) ?? volume
      let confirmedMute = readMute(device: device) ?? mutation.isMuted
      return VolumeSnapshot(
        deviceID: device,
        volume: confirmedVolume,
        isMuted: confirmedMute
      )
    }
  }

  func currentSnapshot() -> VolumeSnapshot? {
    lock.withLock {
      guard
        let device = defaultOutputDevice(),
        let control = volumeControl(for: device),
        let volume = readVolume(device: device, control: control)
      else { return nil }
      let isMuted = readMute(device: device) ?? isEmulatedMuted(device: device, volume: volume)
      return VolumeSnapshot(deviceID: device, volume: volume, isMuted: isMuted)
    }
  }

  private func defaultOutputDevice() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &device
    )
    guard status == noErr, device != kAudioObjectUnknown else { return nil }
    return device
  }

  private func volumeControl(for device: AudioDeviceID) -> VolumeControl? {
    let virtualSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    let virtualMainWritable = isSettable(
      device: device,
      selector: virtualSelector,
      scope: kAudioDevicePropertyScopeOutput,
      element: kAudioObjectPropertyElementMain
    )
    let masterWritable = isSettable(
      device: device,
      selector: kAudioDevicePropertyVolumeScalar,
      scope: kAudioDevicePropertyScopeOutput,
      element: kAudioObjectPropertyElementMain
    )

    let count = max(outputChannelCount(device: device), 2)
    let writableChannels = (1...count).compactMap { channel -> AudioObjectPropertyElement? in
      let element = AudioObjectPropertyElement(channel)
      return isSettable(
        device: device,
        selector: kAudioDevicePropertyVolumeScalar,
        scope: kAudioDevicePropertyScopeOutput,
        element: element
      ) ? element : nil
    }
    switch VolumeControlSelection.select(
      virtualMainWritable: virtualMainWritable,
      masterWritable: masterWritable,
      writableChannels: writableChannels
    ) {
    case .virtualMain:
      return .single(selector: virtualSelector, element: kAudioObjectPropertyElementMain)
    case .master:
      return .single(
        selector: kAudioDevicePropertyVolumeScalar,
        element: kAudioObjectPropertyElementMain
      )
    case .channels(let elements):
      return .channels(elements)
    case .unsupported:
      return nil
    }
  }

  private func outputChannelCount(device: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
      return 0
    }

    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: Int(size),
      alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { raw.deallocate() }
    let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else {
      return 0
    }
    return UnsafeMutableAudioBufferListPointer(list).reduce(0) {
      $0 + Int($1.mNumberChannels)
    }
  }

  private func readVolume(device: AudioDeviceID, control: VolumeControl) -> Float32? {
    switch control {
    case .single(let selector, let element):
      var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: element
      )
      return readFloat32(device: device, address: &address)

    case .channels(let elements):
      let values = elements.compactMap { element -> Float32? in
        var address = AudioObjectPropertyAddress(
          mSelector: kAudioDevicePropertyVolumeScalar,
          mScope: kAudioDevicePropertyScopeOutput,
          mElement: element
        )
        return readFloat32(device: device, address: &address)
      }
      guard !values.isEmpty else { return nil }
      return values.reduce(0, +) / Float32(values.count)
    }
  }

  private func writeVolume(
    _ volume: Float32,
    device: AudioDeviceID,
    control: VolumeControl
  ) -> Bool {
    let volume = VolumeMath.clamped(volume)
    switch control {
    case .single(let selector, let element):
      var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: element
      )
      return writeFloat32(volume, device: device, address: &address)

    case .channels(let elements):
      return elements.reduce(true) { success, element in
        var address = AudioObjectPropertyAddress(
          mSelector: kAudioDevicePropertyVolumeScalar,
          mScope: kAudioDevicePropertyScopeOutput,
          mElement: element
        )
        return writeFloat32(volume, device: device, address: &address) && success
      }
    }
  }

  private func muteAddress(
    device: AudioDeviceID,
    requireSettable: Bool
  ) -> AudioObjectPropertyAddress? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectHasProperty(device, &address) else { return nil }
    if requireSettable {
      var settable = DarwinBoolean(false)
      guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
      else {
        return nil
      }
    }
    return address
  }

  private func readMute(device: AudioDeviceID) -> Bool? {
    guard var address = muteAddress(device: device, requireSettable: false) else { return nil }
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
      return nil
    }
    return value != 0
  }

  private func isEmulatedMuted(device: AudioDeviceID, volume: Float32) -> Bool {
    rememberedVolumeByDevice[device] != nil && volume <= 0.001
  }

  private func isSettable(
    device: AudioDeviceID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope,
    element: AudioObjectPropertyElement
  ) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: scope,
      mElement: element
    )
    guard AudioObjectHasProperty(device, &address) else { return false }
    var settable = DarwinBoolean(false)
    return AudioObjectIsPropertySettable(device, &address, &settable) == noErr
      && settable.boolValue
  }

  private func readFloat32(
    device: AudioDeviceID,
    address: inout AudioObjectPropertyAddress
  ) -> Float32? {
    var value: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
      return nil
    }
    return VolumeMath.clamped(value)
  }

  private func writeFloat32(
    _ value: Float32,
    device: AudioDeviceID,
    address: inout AudioObjectPropertyAddress
  ) -> Bool {
    var value = value
    return AudioObjectSetPropertyData(
      device,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<Float32>.size),
      &value
    ) == noErr
  }

  private func writeUInt32(
    _ value: UInt32,
    device: AudioDeviceID,
    address: AudioObjectPropertyAddress
  ) -> Bool {
    var address = address
    var value = value
    return AudioObjectSetPropertyData(
      device,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<UInt32>.size),
      &value
    ) == noErr
  }
}
