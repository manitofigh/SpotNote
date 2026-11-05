import Core
import SwiftUI

/// Editor-pane card: version-history on/off switch plus "Clear history".
struct HistorySettingsCard: View {
  @AppStorage(NoteHistoryStore.enabledDefaultsKey) private var isEnabled = true
  @State private var confirmClear = false

  var body: some View {
    SettingsCard {
      SettingsToggleRow(
        title: "Version history",
        subtitle: "Keep compact snapshots of each note so earlier versions can be restored (⌘Y).",
        isOn: $isEnabled
      )

      SettingsDivider()

      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Clear history")
            .font(.system(.body, weight: .regular))
          Text("Delete every stored version. Your notes are not affected.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        SettingsPillButton("Clear…") { confirmClear = true }
          .disabled(NoteHistoryStore.shared == nil)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .confirmationDialog(
        "Delete all version history?",
        isPresented: $confirmClear,
        titleVisibility: .visible
      ) {
        Button("Clear History", role: .destructive) {
          Task { await NoteHistoryStore.shared?.clearAll() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Every stored version of every note will be removed. This cannot be undone.")
      }
    }
  }
}
