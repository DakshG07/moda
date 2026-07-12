import Foundation

@MainActor
final class SettingsStore: ObservableObject {
  static let shared = SettingsStore()

  private enum Key {
    static let isEnabled = "moda.isEnabled"
    static let dismissDelay = "moda.dismissDelay"
  }

  @Published var isEnabled: Bool {
    didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
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

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [
      Key.isEnabled: true,
      Key.dismissDelay: 1.5,
    ])
    isEnabled = defaults.bool(forKey: Key.isEnabled)
    dismissDelay = min(max(defaults.double(forKey: Key.dismissDelay), 0.5), 5.0)
  }
}
