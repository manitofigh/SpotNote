import SwiftUI

/// Two-row strip above the editor listing the HUD's everyday chords.
/// Reads every chord from `ShortcutStore` so rebinds in the Settings
/// "Shortcuts" tab immediately update the hints here.
///
/// `delete` is intentionally absent -- it's surfaced inside the
/// `NavigationOverlay` whenever the user is browsing chats so the
/// destructive chord stays out of sight during normal note-taking.
struct TutorialBar: View {
  let theme: Theme
  @ObservedObject var shortcuts: ShortcutStore
  let onDismiss: () -> Void

  private static let row1: [ShortcutAction] = [
    .toggleHotkey, .newChat, .olderChat, .newerChat, .commandPalette
  ]
  private static let row2: [ShortcutAction] = [
    .appendToLastNote, .findInNote, .fuzzyFindAll, .openSettings, .toggleTutorial
  ]

  private static let labels: [ShortcutAction: String] = [
    .toggleHotkey: "toggle show/hide",
    .newChat: "new file",
    .olderChat: "next file",
    .newerChat: "prev file",
    .copyContent: "copy",
    .appendToLastNote: "jump to last edit",
    .pinNote: "pin",
    .commandPalette: "commands",
    .findInNote: "search file",
    .fuzzyFindAll: "global search",
    .openSettings: "settings",
    .toggleTutorial: "hide hints"
  ]

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        row(Self.row1)
        row(Self.row2)
      }
      Spacer(minLength: 8)
      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(theme.text.opacity(0.7))
          .padding(3)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Hide hints")
      .fixedSize()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .frame(height: EditorMetrics.tutorialBarHeight)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(theme.background)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(theme.border, lineWidth: 1)
    )
    .padding(.horizontal, EditorMetrics.outerPadding)
  }

  private func row(_ entries: [ShortcutAction]) -> some View {
    HStack(spacing: 9) {
      ForEach(entries, id: \.self) { action in
        chord(for: action)
      }
      Spacer(minLength: 0)
    }
  }

  private func chord(for action: ShortcutAction) -> some View {
    HStack(spacing: 4) {
      KeyCap.row(
        for: shortcuts.binding(for: action).displayString,
        theme: theme,
        size: .compact
      )
      Text(Self.labels[action] ?? action.displayName)
        .font(.system(size: 11))
        .foregroundStyle(theme.text.opacity(0.65))
        .fixedSize()
    }
    .fixedSize()
  }
}
