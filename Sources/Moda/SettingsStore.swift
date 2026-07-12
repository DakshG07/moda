import Foundation

@MainActor
final class SettingsStore: ObservableObject {
  static let shared = SettingsStore()

  private enum Key {
    static let isEnabled = "moda.isEnabled"
    static let isVolumeEnabled = "moda.isVolumeEnabled"
    static let isDisplayBrightnessEnabled = "moda.isDisplayBrightnessEnabled"
    static let isKeyboardBrightnessEnabled = "moda.isKeyboardBrightnessEnabled"
    static let dismissDelay = "moda.dismissDelay"
    static let hasLaunchedBefore = "moda.hasLaunchedBefore"
  }

  @Published var isEnabled: Bool {
    didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
  }

  @Published var isVolumeEnabled: Bool {
    didSet { defaults.set(isVolumeEnabled, forKey: Key.isVolumeEnabled) }
  }

  @Published var isDisplayBrightnessEnabled: Bool {
    didSet {
      defaults.set(isDisplayBrightnessEnabled, forKey: Key.isDisplayBrightnessEnabled)
    }
  }

  @Published var isKeyboardBrightnessEnabled: Bool {
    didSet {
      defaults.set(isKeyboardBrightnessEnabled, forKey: Key.isKeyboardBrightnessEnabled)
    }
  }

  @Published var dismissDelay: Double {
    didSet {
      let bounded = min(max(dismissDelay, 0.5), 5.0)
      if bounded != dismissDelay {
        dismissDelay = bounded
      } else {
        defaults.set(bounded, forKey: Key.dismissDelay)
      }
    }
  }

  private let defaults: UserDefaults
  private(set) var shouldOpenSettingsOnLaunch: Bool

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [
      Key.isEnabled: true,
      Key.isVolumeEnabled: true,
      Key.isDisplayBrightnessEnabled: true,
      Key.isKeyboardBrightnessEnabled: true,
      Key.dismissDelay: 1.5,
    ])
    isEnabled = defaults.bool(forKey: Key.isEnabled)
    isVolumeEnabled = defaults.bool(forKey: Key.isVolumeEnabled)
    isDisplayBrightnessEnabled = defaults.bool(forKey: Key.isDisplayBrightnessEnabled)
    isKeyboardBrightnessEnabled = defaults.bool(forKey: Key.isKeyboardBrightnessEnabled)
    dismissDelay = min(max(defaults.double(forKey: Key.dismissDelay), 0.5), 5.0)
    shouldOpenSettingsOnLaunch = !defaults.bool(forKey: Key.hasLaunchedBefore)
  }

  func consumeFirstLaunchSettingsRequest() -> Bool {
    guard shouldOpenSettingsOnLaunch else { return false }
    shouldOpenSettingsOnLaunch = false
    defaults.set(true, forKey: Key.hasLaunchedBefore)
    return true
  }

  func isControlEnabled(_ control: HUDControlKind) -> Bool {
    guard isEnabled else { return false }
    return switch control {
    case .volume: isVolumeEnabled
    case .displayBrightness: isDisplayBrightnessEnabled
    case .keyboardBrightness: isKeyboardBrightnessEnabled
    }
  }

  var enabledControls: Set<HUDControlKind> {
    Set(HUDControlKind.allCases.filter(isControlEnabled))
  }
}
