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
    self.present(snapshot)
  }
  private var interceptor: MediaKeyInterceptor?
  private var permissionTimer: Timer?
  private var cancellables = Set<AnyCancellable>()
  private var hasStarted = false

  private init() {}

  func start() {
    guard !hasStarted else { return }
    hasStarted = true
    betterDisplayObserver.start()

    hudController.onLevelSet = { [weak self] control, level in
      self?.controlRouter.setLevel(level, for: control)
    }

    interceptor = MediaKeyInterceptor(controller: controlRouter) { snapshot in
      Task { @MainActor in
        AppCoordinator.shared.present(snapshot)
      }
    }

    settings.$isEnabled
      .removeDuplicates()
      .sink { [weak self] enabled in
        guard let self else { return }
        if enabled {
          self.enableInterception(promptIfNeeded: true)
        } else {
          self.interceptor?.stop()
          self.hudController.hideImmediately()
        }
      }
      .store(in: &cancellables)

    permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        guard let self, self.settings.isEnabled else { return }
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
    guard settings.isEnabled else { return }
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

  private func present(_ snapshot: HUDSnapshot) {
    guard settings.isEnabled else { return }
    hudController.show(snapshot: snapshot, dismissAfter: settings.dismissDelay)
  }
}
