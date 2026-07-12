import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class HUDController {
  private let model = HUDViewModel()
  private let panel: NSPanel
  private var dismissalTimer: Timer?
  private var transitionCompletionTimer: Timer?
  private var presentationGeneration = 0
  private var currentDismissDelay = 1.5
  private var currentControl = HUDControlKind.volume
  private var currentTargetDisplayID: UInt32?
  private var isPointerInside = false
  private var levelHistory = HUDLevelHistory()

  var onLevelSet: ((HUDControlKind, Float32) -> HUDSnapshot?)?

  init() {
    panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: VolumeHUDView.size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.hidesOnDeactivate = false
    panel.animationBehavior = .none
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .ignoresCycle,
      .stationary,
    ]
    panel.contentView = InteractiveHUDContainerView(
      rootView: VolumeHUDView(model: model)
    ) { [weak self] interaction in
      self?.handleInteraction(interaction)
    }
  }

  func show(snapshot: HUDSnapshot, dismissAfter delay: Double) {
    let transition = levelHistory.transition(
      for: snapshot.control,
      target: snapshot.percentage,
      isHUDActive: panel.isVisible,
      displayedPercentage: model.percentage
    )
    currentControl = snapshot.control
    model.accessibilityLabel = snapshot.control.accessibilityLabel

    if panel.isVisible {
      model.percentage = transition.target
      present(dismissAfter: delay, targetDisplayID: snapshot.targetDisplayID)
      return
    }

    // A dismissed HUD starts from this control's own last value. Give SwiftUI one
    // render pass at that baseline before applying the new value so its numeric and
    // fill transitions never inherit a different control's stale percentage.
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      model.percentage = transition.baseline
    }
    present(dismissAfter: delay, targetDisplayID: snapshot.targetDisplayID)
    let generation = presentationGeneration
    guard transition.baseline != transition.target else { return }
    DispatchQueue.main.async { [weak self] in
      guard
        let self,
        self.panel.isVisible,
        self.presentationGeneration == generation
      else { return }
      self.model.percentage = transition.target
    }
  }

  func showTest(dismissAfter delay: Double) {
    model.percentage = model.percentage == 73 ? 42 : 73
    present(dismissAfter: delay, targetDisplayID: nil)
  }

  func setEnabledControls(_ controls: Set<HUDControlKind>) {
    guard panel.isVisible, !controls.contains(currentControl) else { return }
    dismiss()
  }

  func hideImmediately() {
    dismissalTimer?.invalidate()
    dismissalTimer = nil
    transitionCompletionTimer?.invalidate()
    transitionCompletionTimer = nil
    presentationGeneration += 1
    isPointerInside = false
    panel.orderOut(nil)
    panel.alphaValue = 1
  }

  private func present(dismissAfter delay: Double, targetDisplayID: UInt32?) {
    currentDismissDelay = min(max(delay, 0.5), 5.0)
    currentTargetDisplayID = targetDisplayID
    presentationGeneration += 1
    dismissalTimer?.invalidate()
    transitionCompletionTimer?.invalidate()
    transitionCompletionTimer = nil

    let targetScreen = screen(withDisplayID: targetDisplayID) ?? screenContainingPointer()
    let targetFrame = visibleFrame(on: targetScreen)
    let offscreenFrame = hiddenFrame(on: targetScreen, alignedWith: targetFrame)
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    if !panel.isVisible {
      panel.setFrame(reduceMotion ? targetFrame : offscreenFrame, display: false)
      panel.alphaValue = reduceMotion ? 0 : 1
      panel.orderFrontRegardless()
    }

    if reduceMotion {
      panel.setFrame(targetFrame, display: true)
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = reduceMotion ? 0.14 : 0.28
      context.timingFunction = CAMediaTimingFunction(
        controlPoints: 0.22,
        1.0,
        0.36,
        1.0
      )
      context.allowsImplicitAnimation = true
      panel.animator().alphaValue = 1
      if !reduceMotion {
        panel.animator().setFrame(targetFrame, display: true)
      }
    }

    scheduleDismissal()
  }

  private func scheduleDismissal() {
    dismissalTimer?.invalidate()
    dismissalTimer = nil
    guard panel.isVisible, !isPointerInside else { return }
    dismissalTimer = HUDDismissalTimer.schedule(after: currentDismissDelay) { [weak self] in
      self?.dismiss()
    }
  }

  private func handleInteraction(_ interaction: HUDInteraction) {
    if case .hoverChanged(let isInside) = interaction {
      handleHoverChanged(isInside)
      return
    }

    let requestedLevel: Float32
    switch interaction {
    case .set(let level):
      requestedLevel = level
    case .adjust(let delta):
      requestedLevel = VolumeMath.clamped(Float32(model.percentage) / 100 + delta)
    case .hoverChanged:
      return
    }
    guard let snapshot = onLevelSet?(currentControl, requestedLevel) else { return }
    show(snapshot: snapshot, dismissAfter: currentDismissDelay)
  }

  private func handleHoverChanged(_ isInside: Bool) {
    isPointerInside = isInside
    dismissalTimer?.invalidate()
    dismissalTimer = nil
    transitionCompletionTimer?.invalidate()
    transitionCompletionTimer = nil

    guard panel.isVisible else { return }
    if !isInside {
      scheduleDismissal()
      return
    }

    // Entering during an exit invalidates its completion and smoothly restores
    // the panel instead of allowing orderOut to make it disappear abruptly.
    presentationGeneration += 1
    let screen =
      screen(withDisplayID: currentTargetDisplayID)
      ?? screenContaining(panel.frame)
      ?? screenContainingPointer()
    let targetFrame = visibleFrame(on: screen)
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    NSAnimationContext.runAnimationGroup { context in
      context.duration = reduceMotion ? 0.1 : 0.18
      context.timingFunction = CAMediaTimingFunction(
        controlPoints: 0.22,
        1.0,
        0.36,
        1.0
      )
      context.allowsImplicitAnimation = true
      panel.animator().alphaValue = 1
      panel.animator().setFrame(targetFrame, display: true)
    }
  }

  private func dismiss() {
    guard panel.isVisible else { return }
    let pointerInsidePanel = panel.frame.contains(NSEvent.mouseLocation)
    guard
      HUDDismissalPolicy.shouldDismiss(
        isHovering: isPointerInside,
        pointerInsidePanel: pointerInsidePanel
      )
    else {
      isPointerInside = true
      dismissalTimer?.invalidate()
      dismissalTimer = nil
      return
    }

    dismissalTimer = nil
    transitionCompletionTimer?.invalidate()
    transitionCompletionTimer = nil
    presentationGeneration += 1
    let generation = presentationGeneration
    let screen = screenContaining(panel.frame) ?? screenContainingPointer()
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let offscreen = hiddenFrame(on: screen, alignedWith: panel.frame)
    let duration = reduceMotion ? 0.12 : 0.24

    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(
        controlPoints: 0.4,
        0.0,
        1.0,
        1.0
      )
      context.allowsImplicitAnimation = true
      panel.animator().alphaValue = 0
      if !reduceMotion {
        panel.animator().setFrame(offscreen, display: true)
      }
    }

    // AppKit can occasionally deliver an implicit-animation completion before
    // the window's presentation frame catches up. Own the completion deadline
    // instead, and cancel it whenever input reverses the exit.
    transitionCompletionTimer = HUDDismissalTimer.schedule(after: duration) { [weak self] in
      guard let self, self.presentationGeneration == generation else { return }
      self.transitionCompletionTimer = nil
      self.panel.orderOut(nil)
      self.panel.alphaValue = 1
      self.isPointerInside = false
    }
  }

  private func visibleFrame(on screen: NSScreen) -> NSRect {
    let visible = screen.visibleFrame
    return NSRect(
      x: visible.maxX - (32 * VolumeHUDView.designScale) - VolumeHUDView.size.width,
      y: visible.midY - VolumeHUDView.size.height / 2,
      width: VolumeHUDView.size.width,
      height: VolumeHUDView.size.height
    )
  }

  private func hiddenFrame(on screen: NSScreen, alignedWith frame: NSRect) -> NSRect {
    NSRect(
      x: screen.frame.maxX + 8,
      y: frame.minY,
      width: frame.width,
      height: frame.height
    )
  }

  private func screenContainingPointer() -> NSScreen {
    let pointer = NSEvent.mouseLocation
    return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
      ?? NSScreen.main
      ?? NSScreen.screens[0]
  }

  private func screen(withDisplayID displayID: UInt32?) -> NSScreen? {
    guard let displayID else { return nil }
    return NSScreen.screens.first { screen in
      guard
        let number = screen.deviceDescription[
          NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
      else { return false }
      return number.uint32Value == displayID
    }
  }

  private func screenContaining(_ frame: NSRect) -> NSScreen? {
    NSScreen.screens.max { first, second in
      first.frame.intersection(frame).area < second.frame.intersection(frame).area
    }
  }
}

@MainActor
enum HUDDismissalTimer {
  static func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> Timer {
    let timer = Timer(timeInterval: delay, repeats: false) { _ in
      MainActor.assumeIsolated {
        action()
      }
    }
    timer.tolerance = min(0.05, delay * 0.1)

    // A scheduledTimer is installed only in the default mode, which pauses while
    // AppKit tracks a drag, trackpad gesture, or menu. Register the timer explicitly
    // in every interactive mode instead of relying on a host's common-mode setup.
    RunLoop.main.add(timer, forMode: .common)
    RunLoop.main.add(timer, forMode: .eventTracking)
    RunLoop.main.add(timer, forMode: .modalPanel)
    return timer
  }
}

@MainActor
private final class InteractiveHUDContainerView: NSView {
  private let onAction: (HUDInteraction) -> Void
  private var hoverTrackingArea: NSTrackingArea?

  init(rootView: VolumeHUDView, onAction: @escaping (HUDInteraction) -> Void) {
    self.onAction = onAction
    super.init(frame: NSRect(origin: .zero, size: VolumeHUDView.size))

    let hostingView = NSHostingView(rootView: rootView)
    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverTrackingArea {
      removeTrackingArea(hoverTrackingArea)
    }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    hoverTrackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    onAction(.hoverChanged(isInside: true))
  }

  override func mouseExited(with event: NSEvent) {
    onAction(.hoverChanged(isInside: false))
  }

  override func mouseDown(with event: NSEvent) {
    setVolume(from: event)
  }

  override func mouseDragged(with event: NSEvent) {
    setVolume(from: event)
  }

  override func scrollWheel(with event: NSEvent) {
    let physicalDeltaY =
      event.isDirectionInvertedFromDevice
      ? -event.scrollingDeltaY
      : event.scrollingDeltaY
    let adjustment = VolumeMath.scrollAdjustment(
      deltaY: physicalDeltaY,
      isPrecise: event.hasPreciseScrollingDeltas
    )
    guard adjustment != 0 else { return }
    onAction(.adjust(delta: adjustment))
  }

  private func setVolume(from event: NSEvent) {
    let position = convert(event.locationInWindow, from: nil).y
    let volume = VolumeMath.volume(
      forVerticalPosition: position,
      height: bounds.height
    )
    onAction(.set(level: volume))
  }
}

private enum HUDInteraction {
  case set(level: Float32)
  case adjust(delta: Float32)
  case hoverChanged(isInside: Bool)
}

extension HUDControlKind {
  fileprivate var accessibilityLabel: String {
    switch self {
    case .volume: "Volume"
    case .displayBrightness: "Display brightness"
    case .keyboardBrightness: "Keyboard brightness"
    }
  }
}

extension NSRect {
  fileprivate var area: CGFloat { max(width, 0) * max(height, 0) }
}
