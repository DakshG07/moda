import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var settings: SettingsStore
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Toggle("Enable Moda", isOn: $settings.isEnabled)

    Button("Settings…") {
      NSApp.activate(ignoringOtherApps: true)
      openSettings()
    }
    .keyboardShortcut(",", modifiers: .command)

    Divider()

    Button("Quit Moda") {
      NSApp.terminate(nil)
    }
    .keyboardShortcut("q", modifiers: .command)
  }
}
