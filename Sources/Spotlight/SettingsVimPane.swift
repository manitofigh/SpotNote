import SwiftUI

struct VimPane: View {
  @ObservedObject var preferences: ThemePreferences

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      PaneHeader(title: "Vim")
      SettingsCard {
        SettingsToggleRow(
          title: "Vim mode",
          subtitle: "Modal editing with normal / insert modes and a `:` command prompt.",
          isOn: Binding(
            get: { preferences.vimMode },
            set: { preferences.vimMode = $0 }
          )
        )
      }
      Text("Command reference")
        .font(.system(.title3, weight: .semibold))
        .padding(.top, 4)
      Text(
        "Press `:` in normal mode to open the command prompt in the bottom bar."
          + " Enter runs the command, Esc cancels."
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      ForEach(VimCommandReference.sections) { section in
        VimCommandsCard(section: section)
      }
    }
  }
}

private struct VimCommandsCard: View {
  let section: VimCommandReference.Section

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(section.title)
        .font(.system(.subheadline, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(0.6)
      SettingsCard {
        ForEach(Array(section.entries.enumerated()), id: \.element.id) { idx, entry in
          if idx > 0 { SettingsDivider() }
          VimCommandRow(entry: entry)
        }
      }
    }
  }
}

private struct VimCommandRow: View {
  let entry: VimCommandReference.Entry

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Text(entry.usage)
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(.primary)
        .frame(width: 240, alignment: .leading)
      Text(entry.summary)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}
