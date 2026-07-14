import AppKit
import Combine
import Foundation

@MainActor
final class AppCoordinator {
  static let shared = AppCoordinator()

  private let settings = SettingsStore.shared
  private let audioController = AudioController()
  private let displayBrightnessController = BetterDisplayBrightnessController()
  private let keyboardBrightnessController = KeyboardBrightnessController()
  private let hudController = HUDController()
  private lazy var controlRouter = SystemControlRouter(
    audio: audioController,
    displayBrightness: displayBrightnessController,
    keyboardBrightness: keyboardBrightnessController
  )
  private lazy var betterDisplayObserver = BetterDisplayObserver { [weak self] snapshot in
    guard let self else { return }
    self.displayBrightnessController.record(level: snapshot.level)
    _ = self.interceptor?.reassertPriorityIfNeeded()
    // The media-key event owns endpoint tension. BetterDisplay's notification
    // supplies the updated value, but must not immediately clear that tension.
    self.present(snapshot, preservesEdgePull: true)
  }
  private var interceptor: MediaKeyInterceptor?
  private var permissionTimer: Timer?
  private var cancellables = Set<AnyCancellable>()
  private var hasStarted = false

  private init() {}

  func start() {
    guard !hasStarted else { return }
    hasStarted = true

    hudController.onLevelSet = { [weak self] control, level in
      guard let self, self.settings.isControlEnabled(control) else { return nil }
      return self.controlRouter.setLevel(level, for: control)
    }

    interceptor = MediaKeyInterceptor(
      controller: controlRouter,
      onEdgeFeedback: { pull in
        Task { @MainActor in
          AppCoordinator.shared.hudController.setEdgePull(pull)
        }
      }
    ) { snapshot in
      Task { @MainActor in
        AppCoordinator.shared.present(snapshot)
      }
    }

    Publishers.CombineLatest4(
      settings.$isEnabled,
      settings.$isVolumeEnabled,
      settings.$isDisplayBrightnessEnabled,
      settings.$isKeyboardBrightnessEnabled
    )
      .removeDuplicates { $0 == $1 }
      .sink { [weak self] configuration in
        self?.applyFeatureConfiguration(
          isEnabled: configuration.0,
          volume: configuration.1,
          displayBrightness: configuration.2,
          keyboardBrightness: configuration.3,
          promptIfNeeded: true
        )
      }
      .store(in: &cancellables)

    NSWorkspace.shared.notificationCenter.publisher(
      for: NSWorkspace.didLaunchApplicationNotification
    )
      .compactMap { notification in
        notification.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication
      }
      .filter {
        $0.bundleIdentifier == BetterDisplaySettingsController.bundleIdentifier
      }
      .sink { [weak self] _ in
        // Let BetterDisplay finish installing its tap, then place Moda back at
        // the head of the session tap list.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          _ = self?.interceptor?.reassertPriorityIfNeeded(force: true)
        }
      }
      .store(in: &cancellables)

    permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        guard
          let self,
          self.settings.isEnabled,
          self.settings.isVolumeEnabled || self.settings.isKeyboardBrightnessEnabled
        else { return }
        self.enableInterception(promptIfNeeded: false)
      }
    }
  }

  func stop() {
    permissionTimer?.invalidate()
    permissionTimer = nil
    interceptor?.stop()
    betterDisplayObserver.stop()
    hudController.hideImmediately()
    hudController.onLevelSet = nil
    cancellables.removeAll()
    hasStarted = false
  }

  func refreshInterception() {
    guard
      settings.isEnabled,
      settings.isVolumeEnabled || settings.isKeyboardBrightnessEnabled
    else { return }
    enableInterception(promptIfNeeded: false)
  }

  func showTestHUD() {
    if let snapshot = audioController.currentSnapshot() {
      hudController.show(snapshot: snapshot.hudSnapshot, dismissAfter: settings.dismissDelay)
    } else {
      hudController.showTest(dismissAfter: settings.dismissDelay)
    }
  }

  private func enableInterception(promptIfNeeded: Bool) {
    guard interceptor?.isRunning != true else { return }
    if !AccessibilityPermission.isGranted, promptIfNeeded {
      AccessibilityPermission.request()
    }
    _ = interceptor?.start()
  }

  private func applyFeatureConfiguration(
    isEnabled: Bool,
    volume: Bool,
    displayBrightness: Bool,
    keyboardBrightness: Bool,
    promptIfNeeded: Bool
  ) {
    var enabledControls = Set<HUDControlKind>()
    if isEnabled, volume { enabledControls.insert(.volume) }
    if isEnabled, displayBrightness { enabledControls.insert(.displayBrightness) }
    if isEnabled, keyboardBrightness { enabledControls.insert(.keyboardBrightness) }
    interceptor?.setEnabledControls(enabledControls)
    hudController.setEnabledControls(enabledControls)

    if isEnabled, displayBrightness {
      betterDisplayObserver.start()
    } else {
      betterDisplayObserver.stop()
    }

    if isEnabled, volume || keyboardBrightness {
      enableInterception(promptIfNeeded: promptIfNeeded)
    } else {
      interceptor?.stop()
    }

    if !isEnabled {
      hudController.hideImmediately()
    }
  }

  private func present(
    _ snapshot: HUDSnapshot,
    preservesEdgePull: Bool = false
  ) {
    guard settings.isControlEnabled(snapshot.control) else { return }
    hudController.show(
      snapshot: snapshot,
      dismissAfter: settings.dismissDelay,
      preservesEdgePull: preservesEdgePull
    )
  }
}
