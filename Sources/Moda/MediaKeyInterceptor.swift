import AppKit
import CoreGraphics
import Foundation

final class MediaKeyInterceptor: @unchecked Sendable {
  typealias SnapshotHandler = @Sendable (HUDSnapshot) -> Void
  typealias EdgeFeedbackHandler = @Sendable (HUDEdgePull?) -> Void
  private static let systemDefinedEventType: UInt32 = 14

  private let controller: MediaKeyControlling
  private let onSnapshot: SnapshotHandler
  private let onEdgeFeedback: EdgeFeedbackHandler
  private let enabledControlsLock = NSLock()
  private var enabledControls = Set(HUDControlKind.allCases)
  private var lastDisplayBrightnessEventAt: TimeInterval?
  private var lastPriorityReassertionAt: TimeInterval?
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  init(
    controller: MediaKeyControlling,
    onEdgeFeedback: @escaping EdgeFeedbackHandler,
    onSnapshot: @escaping SnapshotHandler
  ) {
    self.controller = controller
    self.onEdgeFeedback = onEdgeFeedback
    self.onSnapshot = onSnapshot
  }

  var isRunning: Bool {
    guard let eventTap else { return false }
    return CGEvent.tapIsEnabled(tap: eventTap)
  }

  func setEnabledControls(_ controls: Set<HUDControlKind>) {
    enabledControlsLock.lock()
    enabledControls = controls
    enabledControlsLock.unlock()
  }

  @discardableResult
  func reassertPriorityIfNeeded(force: Bool = false) -> Bool {
    let now = ProcessInfo.processInfo.systemUptime
    enabledControlsLock.lock()
    let shouldReassert = EventTapPriorityPolicy.shouldReassert(
      lastObservedAt: lastDisplayBrightnessEventAt,
      lastReassertedAt: lastPriorityReassertionAt,
      now: now,
      force: force
    )
    if shouldReassert {
      lastPriorityReassertionAt = now
    }
    enabledControlsLock.unlock()
    guard shouldReassert else { return false }

    // headInsert only orders against taps that already exist. Recreating the
    // tap moves Moda ahead again if BetterDisplay recreated its own tap later.
    stop()
    return start()
  }

  @discardableResult
  func start() -> Bool {
    guard eventTap == nil else { return true }
    guard AccessibilityPermission.isGranted else { return false }

    let eventMask = CGEventMask(1) << Self.systemDefinedEventType
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: Self.eventTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else { return false }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    eventTap = tap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  func stop() {
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    runLoopSource = nil
    eventTap = nil
  }

  private static let eventTapCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<MediaKeyInterceptor>
      .fromOpaque(userInfo)
      .takeUnretainedValue()
    return interceptor.handle(type: type, event: event)
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    guard type.rawValue == Self.systemDefinedEventType,
      let nsEvent = NSEvent(cgEvent: event)
    else {
      return Unmanaged.passUnretained(event)
    }

    let decoded = MediaKeyDecoder.decode(
      subtype: Int(nsEvent.subtype.rawValue),
      data1: nsEvent.data1,
      modifierFlags: event.flags
    )
    guard let decoded else {
      return Unmanaged.passUnretained(event)
    }
    let control = MediaKeyRouting.control(for: decoded)
    guard isEnabled(control) else { return Unmanaged.passUnretained(event) }
    if control == .displayBrightness {
      enabledControlsLock.lock()
      lastDisplayBrightnessEventAt = ProcessInfo.processInfo.systemUptime
      enabledControlsLock.unlock()
    }
    if decoded.phase == .up {
      onEdgeFeedback(nil)
    }
    if MediaKeyRouting.shouldDeferToDisplayHandler(decoded) {
      if
        var snapshot = controller.currentSnapshot(for: .displayBrightness),
        let edgePull = HUDEdgeFeedback.pull(
          for: decoded,
          startingLevel: snapshot.level,
          resultingLevel: snapshot.level
        )
      {
        snapshot.edgePull = edgePull
        onSnapshot(snapshot)
      }
      // BetterDisplay remains the sole owner of normal brightness keys. Its
      // distributed OSD notification supplies Moda with the resulting value.
      return Unmanaged.passUnretained(event)
    }
    let canHandle = controller.canHandle(decoded)
    guard MediaKeyRouting.shouldConsume(decoded, deviceCanHandle: canHandle),
      isEnabled(MediaKeyRouting.control(for: decoded))
    else {
      return Unmanaged.passUnretained(event)
    }

    if let action = MediaKeyDecoder.action(for: decoded) {
      let startingLevel = controller.currentSnapshot(
        for: control
      )?.level
      guard var snapshot = controller.perform(action) else {
        return Unmanaged.passUnretained(event)
      }
      if let startingLevel {
        snapshot.edgePull = HUDEdgeFeedback.pull(
          for: decoded,
          startingLevel: startingLevel,
          resultingLevel: snapshot.level
        )
      }
      onSnapshot(snapshot)
    }

    // Consume both phases for supported media keys. This prevents macOS from
    // applying the event a second time and suppresses its native HUD.
    return nil
  }

  private func isEnabled(_ control: HUDControlKind) -> Bool {
    enabledControlsLock.lock()
    defer { enabledControlsLock.unlock() }
    return enabledControls.contains(control)
  }
}
