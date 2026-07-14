import AppKit
import Foundation

struct BetterDisplayConfigurationStatus: Equatable {
  let isInstalled: Bool
  let integrationEnabled: Bool
  let builtInOSDDisabled: Bool

  var isConfigured: Bool {
    isInstalled && integrationEnabled && builtInOSDDisabled
  }
}

@MainActor
enum BetterDisplaySettingsController {
  static let bundleIdentifier = "pro.betterdisplay.BetterDisplay"
  private static let applicationURL = URL(
    fileURLWithPath: "/Applications/BetterDisplay.app"
  )

  static var status: BetterDisplayConfigurationStatus {
    _ = CFPreferencesAppSynchronize(bundleIdentifier as CFString)
    return BetterDisplayConfigurationStatus(
      isInstalled: FileManager.default.fileExists(atPath: applicationURL.path),
      integrationEnabled: boolValue(for: "osdIntegrationNotification"),
      builtInOSDDisabled: !boolValue(for: "osdShowBasic")
        && !boolValue(for: "osdShowCustom")
    )
  }

  static func configureAndRestart() throws {
    guard FileManager.default.fileExists(atPath: applicationURL.path) else {
      throw ConfigurationError.notInstalled
    }

    set(true, for: "osdIntegrationNotification")
    set(false, for: "osdShowBasic")
    set(false, for: "osdShowCustom")
    guard CFPreferencesAppSynchronize(bundleIdentifier as CFString) else {
      throw ConfigurationError.couldNotSave
    }

    let runningApplications = NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    )
    for application in runningApplications where !application.terminate() {
      application.forceTerminate()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      NSWorkspace.shared.openApplication(
        at: applicationURL,
        configuration: configuration
      )
    }
  }

  private static func boolValue(for key: String) -> Bool {
    guard
      let value = CFPreferencesCopyAppValue(
        key as CFString,
        bundleIdentifier as CFString
      )
    else { return false }
    return (value as? NSNumber)?.boolValue ?? false
  }

  private static func set(_ value: Bool, for key: String) {
    CFPreferencesSetAppValue(
      key as CFString,
      value ? kCFBooleanTrue : kCFBooleanFalse,
      bundleIdentifier as CFString
    )
  }

  enum ConfigurationError: LocalizedError {
    case notInstalled
    case couldNotSave

    var errorDescription: String? {
      switch self {
      case .notInstalled: "BetterDisplay is not installed in Applications."
      case .couldNotSave: "BetterDisplay's integration settings could not be saved."
      }
    }
  }
}
