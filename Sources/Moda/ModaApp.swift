import AppKit
import SwiftUI

@MainActor
private enum ModaAssets {
  static let toolbarIcon: NSImage = {
    if let url = Bundle.main.url(forResource: "ModaToolbarIcon", withExtension: "svg"),
      let image = NSImage(contentsOf: url)
    {
      image.isTemplate = true
      image.size = NSSize(width: 18, height: 18)
      image.accessibilityDescription = "Moda"
      return image
    }

    return NSImage(
      systemSymbolName: "slider.vertical.3",
      accessibilityDescription: "Moda"
    ) ?? NSImage()
  }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    AppCoordinator.shared.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    AppCoordinator.shared.stop()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}

@main
struct ModaApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var settings = SettingsStore.shared

  var body: some Scene {
    MenuBarExtra {
      MenuBarView(settings: settings)
    } label: {
      Image(nsImage: ModaAssets.toolbarIcon)
        .accessibilityLabel("Moda")
    }
    .menuBarExtraStyle(.menu)

    Settings {
      SettingsView(settings: settings)
    }
  }
}
