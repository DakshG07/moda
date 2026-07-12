import Foundation
import ModaHardwareBridge

protocol BrightnessControlling: AnyObject, Sendable {
  var target: BrightnessTarget { get }
  func currentSnapshot() -> HUDSnapshot?
  func perform(_ action: BrightnessAction) -> HUDSnapshot?
}

final class BetterDisplayBrightnessController: BrightnessControlling, @unchecked Sendable {
  let target = BrightnessTarget.display
  private let lock = NSLock()
  private var lastLevel: Float32?

  func currentSnapshot() -> HUDSnapshot? {
    lock.withLock {
      lastLevel.map { HUDSnapshot(control: .displayBrightness, level: $0) }
    }
  }

  func perform(_ action: BrightnessAction) -> HUDSnapshot? {
    let level: Float32? = lock.withLock {
      guard let current = lastLevel ?? requestedLevel(from: action) else { return nil }
      let updated = BrightnessMath.applying(action, to: current)
      lastLevel = updated
      return updated
    }
    guard let level, BetterDisplayIntegration.setBrightness(level) else { return nil }
    return HUDSnapshot(control: .displayBrightness, level: level)
  }

  func record(level: Float32) {
    lock.withLock { lastLevel = VolumeMath.clamped(level) }
  }

  private func requestedLevel(from action: BrightnessAction) -> Float32? {
    if case .set(let level) = action { return level }
    return nil
  }
}

final class KeyboardBrightnessController: BrightnessControlling, @unchecked Sendable {
  let target = BrightnessTarget.keyboard
  private let lock = NSLock()
  private let client: UnsafeMutableRawPointer?

  init() {
    client = ModaKeyboardBrightnessClientCreate()
  }

  deinit {
    ModaKeyboardBrightnessClientRelease(client)
  }

  func currentSnapshot() -> HUDSnapshot? {
    lock.withLock { readSnapshot() }
  }

  func perform(_ action: BrightnessAction) -> HUDSnapshot? {
    lock.withLock {
      guard let client, let current = read(client: client) else { return nil }
      let level = BrightnessMath.applying(action, to: current.level)
      guard ModaKeyboardBrightnessSet(client, current.keyboardID, level) else { return nil }
      let confirmed = read(client: client)?.level ?? level
      return HUDSnapshot(control: .keyboardBrightness, level: confirmed)
    }
  }

  private func readSnapshot() -> HUDSnapshot? {
    guard let client, let current = read(client: client) else { return nil }
    return HUDSnapshot(control: .keyboardBrightness, level: current.level)
  }

  private func read(
    client: UnsafeMutableRawPointer
  ) -> (keyboardID: UInt64, level: Float32)? {
    var keyboardID: UInt64 = 0
    var level: Float32 = 0
    guard ModaKeyboardBrightnessGet(client, &keyboardID, &level), level.isFinite else {
      return nil
    }
    return (keyboardID, VolumeMath.clamped(level))
  }
}

protocol MediaKeyControlling: AnyObject, Sendable {
  func canHandle(_ event: DecodedMediaKeyEvent) -> Bool
  func perform(_ action: MediaKeyAction) -> HUDSnapshot?
  func setLevel(_ level: Float32, for control: HUDControlKind) -> HUDSnapshot?
}

final class SystemControlRouter: MediaKeyControlling, @unchecked Sendable {
  private let audio: VolumeControlling
  private let displayBrightness: BrightnessControlling
  private let keyboardBrightness: BrightnessControlling

  init(
    audio: VolumeControlling,
    displayBrightness: BrightnessControlling,
    keyboardBrightness: BrightnessControlling
  ) {
    self.audio = audio
    self.displayBrightness = displayBrightness
    self.keyboardBrightness = keyboardBrightness
  }

  func canHandle(_ event: DecodedMediaKeyEvent) -> Bool {
    switch event.key {
    case .volume(let key): audio.canHandle(key)
    case .brightnessUp, .brightnessDown:
      controller(for: event.isCommandPressed ? .keyboard : .display).currentSnapshot() != nil
    }
  }

  func perform(_ action: MediaKeyAction) -> HUDSnapshot? {
    switch action {
    case .volume(let volumeAction):
      return audio.perform(volumeAction)?.hudSnapshot
    case .brightness(let target, let brightnessAction):
      return controller(for: target).perform(brightnessAction)
    }
  }

  func setLevel(_ level: Float32, for control: HUDControlKind) -> HUDSnapshot? {
    switch control {
    case .volume:
      return audio.perform(.set(volume: level))?.hudSnapshot
    case .displayBrightness:
      return displayBrightness.perform(.set(level: level))
    case .keyboardBrightness:
      return keyboardBrightness.perform(.set(level: level))
    }
  }

  private func controller(for target: BrightnessTarget) -> BrightnessControlling {
    switch target {
    case .display: displayBrightness
    case .keyboard: keyboardBrightness
    }
  }
}
