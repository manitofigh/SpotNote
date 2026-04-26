import AppKit
import SwiftUI

/// Settings pane for Sparkle-driven auto-updates.
///
/// Lives in the Spotlight framework so it can be embedded in
/// `SettingsView`, but the actual `SPUUpdater` lives in the app target.
/// We bridge the gap with a Notification: the app's `AppDelegate`
/// listens for `.spotNoteCheckForUpdates` and forwards it to Sparkle's
/// updater. The "automatically check" toggle is bound to UserDefaults
/// key `SUEnableAutomaticChecks` which Sparkle reads natively.
struct UpdatesPane: View {
  @AppStorage("SUEnableAutomaticChecks") private var autoCheck: Bool = true

  init() {}

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Updates")
        .font(.system(size: 22, weight: .semibold))

      Toggle(isOn: $autoCheck) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Automatically check for updates")
          Text("SpotNote will check periodically and notify you when a new version is available.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.switch)

      Button("Check for Updates Now") {
        NotificationCenter.default.post(name: .spotNoteCheckForUpdates, object: nil)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension Notification.Name {
  public static let spotNoteCheckForUpdates = Notification.Name("SpotNoteCheckForUpdates")
}
