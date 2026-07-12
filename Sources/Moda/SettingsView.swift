import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
  @ObservedObject var settings: SettingsStore
  @State private var permissionGranted = AccessibilityPermission.isGranted
  @State private var launchAtLogin = LaunchAtLoginController.isEnabled
  @State private var launchAtLoginError: String?
  @State private var betterDisplayStatus = BetterDisplaySettingsController.status
  @State private var betterDisplayMessage: String?

  private let permissionRefresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    Form {
      Section("General") {
        Toggle("Enable Moda", isOn: $settings.isEnabled)

        Text("Replaces supported system HUDs with Moda's interactive liquid-glass slider.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Controls") {
        featureToggle(
          title: "Volume",
          detail: "Volume keys · Moda controls Core Audio",
          systemImage: "speaker.wave.2.fill",
          isOn: $settings.isVolumeEnabled
        )
        featureToggle(
          title: "Display brightness",
          detail: betterDisplayStatus.isInstalled
            ? "Brightness keys · Reflected from BetterDisplay"
            : "Requires BetterDisplay",
          systemImage: "sun.max.fill",
          isOn: $settings.isDisplayBrightnessEnabled,
          isAvailable: betterDisplayStatus.isInstalled
        )
        featureToggle(
          title: "Keyboard brightness",
          detail: "Command + Brightness keys · Built-in keyboard",
          systemImage: "keyboard.fill",
          isOn: $settings.isKeyboardBrightnessEnabled
        )

        if !betterDisplayStatus.isInstalled {
          Text("Install BetterDisplay to enable display-brightness HUD reflection.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("HUD Behavior") {

        HStack {
          Text("Dismiss after")
          Slider(value: $settings.dismissDelay, in: 0.5...5, step: 0.1)
          Text(settings.dismissDelay, format: .number.precision(.fractionLength(1)))
            .monospacedDigit()
            .frame(width: 36, alignment: .trailing)
          Text("s")
            .foregroundStyle(.secondary)
        }

        LabeledContent("Pointer interaction") {
          Text("Click-drag or two-finger scroll")
            .foregroundStyle(.secondary)
        }

        HStack {
          Button("Test HUD") {
            AppCoordinator.shared.showTestHUD()
          }
          Text("Hovering pauses dismissal until the pointer leaves.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("BetterDisplay") {
        LabeledContent("Application") {
          statusLabel(
            betterDisplayStatus.isInstalled ? "Installed" : "Not installed",
            isReady: betterDisplayStatus.isInstalled
          )
        }
        LabeledContent("Moda OSD integration") {
          statusLabel(
            betterDisplayStatus.integrationEnabled ? "Enabled" : "Disabled",
            isReady: betterDisplayStatus.integrationEnabled
          )
        }
        LabeledContent("BetterDisplay built-in OSD") {
          statusLabel(
            betterDisplayStatus.builtInOSDDisabled ? "Off" : "Still active",
            isReady: betterDisplayStatus.builtInOSDDisabled
          )
        }

        Button(
          betterDisplayStatus.isConfigured
            ? "Reapply Moda Integration"
            : "Configure BetterDisplay for Moda"
        ) {
          configureBetterDisplay()
        }
        .disabled(!betterDisplayStatus.isInstalled)

        Text(
          "Enables BetterDisplay's OSD notifications, disables its basic and custom OSDs, and restarts BetterDisplay. Brightness remains fully controlled by BetterDisplay."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if let betterDisplayMessage {
          Text(betterDisplayMessage)
            .font(.caption)
            .foregroundStyle(betterDisplayStatus.isConfigured ? Color.green : Color.red)
        }
      }

      Section("Permissions") {
        LabeledContent("Accessibility") {
          Label(
            permissionGranted ? "Granted" : "Required",
            systemImage: permissionGranted
              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
          )
          .foregroundStyle(permissionGranted ? Color.green : Color.orange)
        }

        HStack {
          Button("Request Access") {
            permissionGranted = AccessibilityPermission.request()
          }
          Button("Open System Settings") {
            AccessibilityPermission.openSystemSettings()
          }
        }

        Text(
          "Accessibility is required for enabled volume and keyboard-brightness controls. Normal brightness keys remain under BetterDisplay's control."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Startup") {
        Toggle(
          "Launch Moda at login",
          isOn: Binding(
            get: { launchAtLogin },
            set: updateLaunchAtLogin
          ))

        if let launchAtLoginError {
          Text(launchAtLoginError)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 680)
    .onReceive(permissionRefresh) { _ in
      betterDisplayStatus = BetterDisplaySettingsController.status
      let nowGranted = AccessibilityPermission.isGranted
      if nowGranted != permissionGranted {
        permissionGranted = nowGranted
        if nowGranted {
          AppCoordinator.shared.refreshInterception()
        }
      }
    }
  }

  private func featureToggle(
    title: String,
    detail: String,
    systemImage: String,
    isOn: Binding<Bool>,
    isAvailable: Bool = true
  ) -> some View {
    Toggle(isOn: isOn) {
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .foregroundStyle(.secondary)
          .frame(width: 22)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .disabled(!isAvailable)
  }

  private func statusLabel(_ text: String, isReady: Bool) -> some View {
    Label(
      text,
      systemImage: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    )
    .foregroundStyle(isReady ? Color.green : Color.orange)
  }

  private func configureBetterDisplay() {
    do {
      try BetterDisplaySettingsController.configureAndRestart()
      settings.isDisplayBrightnessEnabled = true
      betterDisplayStatus = BetterDisplaySettingsController.status
      betterDisplayMessage = "Configured. BetterDisplay is restarting."
    } catch {
      betterDisplayStatus = BetterDisplaySettingsController.status
      betterDisplayMessage = error.localizedDescription
    }
  }

  private func updateLaunchAtLogin(_ enabled: Bool) {
    do {
      try LaunchAtLoginController.setEnabled(enabled)
      launchAtLogin = LaunchAtLoginController.isEnabled
      launchAtLoginError = nil
    } catch {
      launchAtLogin = LaunchAtLoginController.isEnabled
      launchAtLoginError = error.localizedDescription
    }
  }
}
