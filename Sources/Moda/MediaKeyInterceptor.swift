import AppKit
import CoreGraphics
import Foundation

final class MediaKeyInterceptor: @unchecked Sendable {
  typealias SnapshotHandler = @Sendable (HUDSnapshot) -> Void
  private static let systemDefinedEventType: UInt32 = 14

  private let controller: MediaKeyControlling
  private let onSnapshot: SnapshotHandler
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  init(controller: MediaKeyControlling, onSnapshot: @escaping SnapshotHandler) {
    self.controller = controller
    self.onSnapshot = onSnapshot
  }

  var isRunning: Bool {
    guard let eventTap else { return false }
    return CGEvent.tapIsEnabled(tap: eventTap)
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
    if MediaKeyRouting.shouldDeferToDisplayHandler(decoded) {
      // BetterDisplay remains the sole owner of normal brightness keys. Its
      // distributed OSD notification supplies Moda with the resulting value.
      return Unmanaged.passUnretained(event)
    }
    let canHandle = decoded.map { controller.canHandle($0) } ?? false
    guard MediaKeyRouting.shouldConsume(decoded, deviceCanHandle: canHandle),
      let decoded
    else {
      return Unmanaged.passUnretained(event)
    }

    if let action = MediaKeyDecoder.action(for: decoded) {
      guard let snapshot = controller.perform(action) else {
        return Unmanaged.passUnretained(event)
      }
      onSnapshot(snapshot)
    }

    // Consume both phases for supported media keys. This prevents macOS from
    // applying the event a second time and suppresses its native HUD.
    return nil
  }
}
