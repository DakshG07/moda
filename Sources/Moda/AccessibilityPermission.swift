import AppKit
import ApplicationServices

enum AccessibilityPermission {
  static var isGranted: Bool {
    AXIsProcessTrusted()
  }

  @discardableResult
  static func request() -> Bool {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  static func openSystemSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }
}
