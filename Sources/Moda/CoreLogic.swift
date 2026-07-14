import CoreGraphics
import Foundation

enum VolumeKey: Equatable, Sendable {
  case up
  case down
  case mute
}

enum MediaKey: Equatable, Sendable {
  case volume(VolumeKey)
  case brightnessUp
  case brightnessDown
}

enum BrightnessTarget: Equatable, Sendable {
  case display
  case keyboard
}

enum MediaKeyPhase: Equatable, Sendable {
  case down
  case up
}

struct DecodedMediaKeyEvent: Equatable, Sendable {
  let key: MediaKey
  let phase: MediaKeyPhase
  let isFineAdjustment: Bool
  let isCommandPressed: Bool
  var isRepeat = false
}

enum VolumeAction: Equatable, Sendable {
  case increase(step: Float32)
  case decrease(step: Float32)
  case set(volume: Float32)
  case toggleMute

  static let normalStep: Float32 = 1.0 / 16.0
  static let fineStep: Float32 = 1.0 / 64.0
}

enum BrightnessAction: Equatable, Sendable {
  case increase(step: Float32)
  case decrease(step: Float32)
  case set(level: Float32)
}

enum MediaKeyAction: Equatable, Sendable {
  case volume(VolumeAction)
  case brightness(target: BrightnessTarget, action: BrightnessAction)
}

enum MediaKeyDecoder {
  private static let auxiliaryControlSubtype = 8
  private static let keyDownState = 0xA
  private static let keyUpState = 0xB

  static func decode(
    subtype: Int,
    data1: Int,
    modifierFlags: CGEventFlags
  ) -> DecodedMediaKeyEvent? {
    guard subtype == auxiliaryControlSubtype else { return nil }

    let keyCode = (data1 & 0xFFFF_0000) >> 16
    let state = (data1 & 0x0000_FF00) >> 8

    let key: MediaKey
    switch keyCode {
    case 0: key = .volume(.up)
    case 1: key = .volume(.down)
    case 2: key = .brightnessUp
    case 3: key = .brightnessDown
    case 7: key = .volume(.mute)
    default: return nil
    }

    let phase: MediaKeyPhase
    switch state {
    case keyDownState: phase = .down
    case keyUpState: phase = .up
    default: return nil
    }

    let isFine =
      modifierFlags.contains(.maskAlternate)
      && modifierFlags.contains(.maskShift)
    return DecodedMediaKeyEvent(
      key: key,
      phase: phase,
      isFineAdjustment: isFine,
      isCommandPressed: modifierFlags.contains(.maskCommand),
      isRepeat: (data1 & 0xFF) != 0
    )
  }

  static func action(for event: DecodedMediaKeyEvent) -> MediaKeyAction? {
    guard event.phase == .down else { return nil }
    let step = event.isFineAdjustment ? VolumeAction.fineStep : VolumeAction.normalStep
    switch event.key {
    case .volume(.up): return .volume(.increase(step: step))
    case .volume(.down): return .volume(.decrease(step: step))
    case .volume(.mute): return .volume(.toggleMute)
    case .brightnessUp:
      return .brightness(
        target: event.isCommandPressed ? .keyboard : .display,
        action: .increase(step: step)
      )
    case .brightnessDown:
      return .brightness(
        target: event.isCommandPressed ? .keyboard : .display,
        action: .decrease(step: step)
      )
    }
  }
}

enum MediaKeyRouting {
  static func control(for event: DecodedMediaKeyEvent) -> HUDControlKind {
    switch event.key {
    case .volume:
      return .volume
    case .brightnessUp, .brightnessDown:
      return event.isCommandPressed ? .keyboardBrightness : .displayBrightness
    }
  }

  static func shouldConsume(_ event: DecodedMediaKeyEvent?, deviceCanHandle: Bool) -> Bool {
    event != nil && deviceCanHandle
  }

  static func shouldDeferToDisplayHandler(_ event: DecodedMediaKeyEvent?) -> Bool {
    guard let event, !event.isCommandPressed else { return false }
    return switch event.key {
    case .brightnessUp, .brightnessDown: true
    case .volume: false
    }
  }
}

enum VolumeMath {
  static func clamped(_ value: Float32) -> Float32 {
    min(max(value, 0), 1)
  }

  static func percentage(for volume: Float32, isMuted: Bool) -> Int {
    let displayedVolume = isMuted ? 0 : clamped(volume)
    return Int((displayedVolume * 100).rounded())
  }

  static func fillHeight(volumePercent: Int, totalHeight: CGFloat) -> CGFloat {
    let clampedPercent = min(max(volumePercent, 0), 100)
    return totalHeight * CGFloat(clampedPercent) / 100
  }

  static func volume(
    byDraggingFrom startingVolume: Float32,
    verticalDelta: CGFloat,
    height: CGFloat
  ) -> Float32 {
    dragRequest(
      from: startingVolume,
      verticalDelta: verticalDelta,
      height: height
    ).level
  }

  static func dragRequest(
    from startingVolume: Float32,
    verticalDelta: CGFloat,
    height: CGFloat
  ) -> HUDLevelRequest {
    guard height > 0 else {
      return HUDLevelRequest(level: clamped(startingVolume), edgePull: nil)
    }
    let requested = startingVolume + Float32(verticalDelta / height)
    let edgePull: HUDEdgePull? =
      if requested > 1 {
        .upper
      } else if requested < 0 {
        .lower
      } else {
        nil
      }
    return HUDLevelRequest(level: clamped(requested), edgePull: edgePull)
  }

  static func scrollAdjustment(deltaY: CGFloat, isPrecise: Bool) -> Float32 {
    guard deltaY != 0 else { return 0 }
    if !isPrecise {
      return deltaY > 0 ? VolumeAction.normalStep : -VolumeAction.normalStep
    }
    return min(max(Float32(deltaY / 300), -0.125), 0.125)
  }
}

enum BrightnessMath {
  static func applying(_ action: BrightnessAction, to level: Float32) -> Float32 {
    switch action {
    case .increase(let step): VolumeMath.clamped(level + step)
    case .decrease(let step): VolumeMath.clamped(level - step)
    case .set(let requestedLevel): VolumeMath.clamped(requestedLevel)
    }
  }
}

enum HUDControlKind: CaseIterable, Equatable, Hashable, Sendable {
  case volume
  case displayBrightness
  case keyboardBrightness
}

enum HUDEdgePull: Equatable, Sendable {
  case upper
  case lower
}

struct HUDLevelRequest: Equatable, Sendable {
  let level: Float32
  let edgePull: HUDEdgePull?
}

enum HUDEdgeFeedback {
  static func pull(
    for event: DecodedMediaKeyEvent,
    startingLevel: Float32,
    resultingLevel: Float32
  ) -> HUDEdgePull? {
    guard event.phase == .down else { return nil }

    if startingLevel >= 0.999, resultingLevel >= 0.999 {
      switch event.key {
      case .volume(.up), .brightnessUp: return .upper
      case .volume, .brightnessDown: break
      }
    }
    if startingLevel <= 0.001, resultingLevel <= 0.001 {
      switch event.key {
      case .volume(.down), .brightnessDown: return .lower
      case .volume, .brightnessUp: break
      }
    }
    return nil
  }
}

struct HUDLevelTransition: Equatable, Sendable {
  let baseline: Int
  let target: Int
}

struct HUDLevelHistory: Sendable {
  private var percentages: [HUDControlKind: Int] = [:]

  mutating func transition(
    for control: HUDControlKind,
    target: Int,
    isHUDActive: Bool,
    displayedPercentage: Int
  ) -> HUDLevelTransition {
    let baseline = isHUDActive ? displayedPercentage : (percentages[control] ?? target)
    percentages[control] = target
    return HUDLevelTransition(baseline: baseline, target: target)
  }
}

enum HUDDismissalPolicy {
  static func shouldDismiss(isHovering: Bool, pointerInsidePanel: Bool) -> Bool {
    !isHovering && !pointerInsidePanel
  }
}

enum EventTapPriorityPolicy {
  static func shouldReassert(
    lastObservedAt: TimeInterval?,
    lastReassertedAt: TimeInterval?,
    now: TimeInterval,
    observationWindow: TimeInterval = 0.35,
    cooldown: TimeInterval = 2.0,
    force: Bool = false
  ) -> Bool {
    if let lastReassertedAt, now - lastReassertedAt < cooldown {
      return false
    }
    guard !force else { return true }
    guard let lastObservedAt else { return true }
    return now - lastObservedAt > observationWindow
  }
}

struct HUDSnapshot: Equatable, Sendable {
  let control: HUDControlKind
  let level: Float32
  var targetDisplayID: UInt32? = nil
  var edgePull: HUDEdgePull? = nil

  var percentage: Int {
    VolumeMath.percentage(for: level, isMuted: false)
  }
}

struct VolumeSnapshot: Equatable, Sendable {
  let deviceID: UInt32
  let volume: Float32
  let isMuted: Bool

  var percentage: Int {
    VolumeMath.percentage(for: volume, isMuted: isMuted)
  }
}

extension VolumeSnapshot {
  var hudSnapshot: HUDSnapshot {
    HUDSnapshot(
      control: .volume,
      level: isMuted ? 0 : volume
    )
  }
}

enum VolumeControlSelection: Equatable, Sendable {
  case virtualMain
  case master
  case channels([UInt32])
  case unsupported

  static func select(
    virtualMainWritable: Bool,
    masterWritable: Bool,
    writableChannels: [UInt32]
  ) -> VolumeControlSelection {
    if virtualMainWritable { return .virtualMain }
    if masterWritable { return .master }
    if !writableChannels.isEmpty { return .channels(writableChannels) }
    return .unsupported
  }
}

struct VolumeMutation: Equatable, Sendable {
  let volume: Float32
  let isMuted: Bool
  let rememberedVolume: Float32?
}

enum VolumeStateReducer {
  static func apply(
    _ action: VolumeAction,
    volume: Float32,
    isMuted: Bool,
    rememberedVolume: Float32?,
    usesNativeMute: Bool
  ) -> VolumeMutation {
    var volume = VolumeMath.clamped(volume)
    var isMuted = isMuted
    var remembered = rememberedVolume

    switch action {
    case .increase(let step):
      if isMuted, !usesNativeMute {
        volume = remembered ?? volume
      }
      isMuted = false
      remembered = nil
      volume = VolumeMath.clamped(volume + step)

    case .decrease(let step):
      if isMuted, !usesNativeMute {
        volume = remembered ?? volume
      }
      isMuted = false
      remembered = nil
      volume = VolumeMath.clamped(volume - step)

    case .set(let requestedVolume):
      volume = VolumeMath.clamped(requestedVolume)
      isMuted = false
      remembered = nil

    case .toggleMute:
      if usesNativeMute {
        isMuted.toggle()
      } else if isMuted {
        volume = remembered ?? 0.5
        remembered = nil
        isMuted = false
      } else {
        if volume > 0.001 {
          remembered = volume
        }
        volume = 0
        isMuted = true
      }
    }

    return VolumeMutation(
      volume: volume,
      isMuted: isMuted,
      rememberedVolume: remembered
    )
  }
}
