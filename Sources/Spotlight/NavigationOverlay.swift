import Core
import SwiftUI

/// Compact floating card rendered above the editor whenever
/// `ChatSession.navigationPreview` is non-nil. Shows the action label,
/// a window of surrounding chats with a `>` marker + border highlighting
/// the current one, and the first line of each chat's text.
struct NavigationOverlay: View {
  let preview: NavigationPreview
  let theme: Theme
  @ObservedObject var shortcuts: ShortcutStore
  /// When true, an extra `undo` chord is appended to the hint footer.
  /// Driven by `ChatSession.lastDeleted` from the parent view.
  var canUndo: Bool = false

  /// How many rows the list shows at most. Panel-sizing math in
  /// `SpotlightRootView.overlayChromeHeight` assumes this ceiling.
  static let maxRows = 5

  /// Fixed height budget reserved below the editor when the overlay is
  /// visible. Kept constant so resize animations don't flicker between
  /// nav actions with different row counts. Sized to hold 5 rows plus
  /// header plus the chord-hint footer (with KeyCap chrome) without
  /// clipping the delete cap's bottom edge.
  static let reservedHeight: CGFloat = 162

  private static let shape = UnevenRoundedRectangle(
    topLeadingRadius: 0,
    bottomLeadingRadius: 10,
    bottomTrailingRadius: 10,
    topTrailingRadius: 0,
    style: .continuous
  )

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      header
      ForEach(windowed, id: \.id) { chat in
        row(for: chat)
      }
      if !preview.chats.isEmpty {
        hintFooter
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    // Fill the reserved height SwiftUI hands us so the rounded card
    // stays a fixed size as the chat list grows or shrinks. Top-leading
    // alignment keeps rows pinned under the header; deletes/restores
    // reflow inside this constant frame instead of resizing it.
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Self.shape.fill(theme.background))
    .overlay(Self.shape.strokeBorder(theme.border, lineWidth: 1))
    .animation(.easeInOut(duration: 0.16), value: preview.chats.map(\.id))
    .animation(.easeInOut(duration: 0.16), value: preview.highlightedID)
  }

  /// Small row of chord hints so the delete action in particular is
  /// discoverable while the user is already in "nav" mode. Reads every
  /// chord from `ShortcutStore` so it picks up user rebinds immediately.
  private var hintFooter: some View {
    HStack(spacing: 8) {
      hintChord(action: .olderChat, label: "older")
      hintChord(action: .newerChat, label: "newer")
      hintChord(action: .pinNote, label: "pin")
      hintChord(action: .deleteChat, label: "delete", accent: .red)
      if canUndo {
        hintChord(action: .undoDelete, label: "undo delete")
      }
      Spacer(minLength: 0)
    }
    .padding(.top, 2)
  }

  private func hintChord(
    action: ShortcutAction,
    label: String,
    accent: KeyCap.Accent? = nil
  ) -> some View {
    HStack(spacing: 4) {
      KeyCap.row(
        for: shortcuts.binding(for: action).displayString,
        theme: theme,
        accent: accent,
        size: .regular
      )
      Text(label)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(labelColor(accent: accent))
    }
    .fixedSize()
  }

  private func labelColor(accent: KeyCap.Accent?) -> Color {
    guard accent == .red else { return theme.placeholder }
    if theme.mode == .dark {
      return Color(red: 0.988, green: 0.647, blue: 0.647)
    }
    return Color(red: 0.725, green: 0.110, blue: 0.110)
  }

  private var header: some View {
    Text(preview.actionLabel)
      .font(.system(size: 10, weight: .semibold, design: .monospaced))
      .foregroundStyle(theme.placeholder)
      .textCase(.uppercase)
      .tracking(0.4)
  }

  private static let highlightTint = Color(red: 0.30, green: 0.78, blue: 0.45)

  private func row(for chat: Chat) -> some View {
    let isCurrent = chat.id == preview.currentID
    let isHighlighted = chat.id == preview.highlightedID
    let line = Self.firstNonEmptyLine(chat.text)
    return HStack(spacing: 6) {
      Text(isCurrent ? ">" : " ")
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(isCurrent ? theme.text : .clear)
        .frame(width: 8, alignment: .leading)
      if chat.isPinned {
        Text("★")
          .font(.system(size: 9))
          .foregroundStyle(Color(red: 0.95, green: 0.75, blue: 0.25))
      }
      Text(line.isEmpty ? "(empty)" : line)
        .font(.system(size: 11))
        .foregroundStyle(isCurrent ? theme.text : theme.text.opacity(0.55))
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(rowBackground(isHighlighted: isHighlighted))
    .overlay(rowBorder(isHighlighted: isHighlighted, isCurrent: isCurrent))
  }

  private func rowBackground(isHighlighted: Bool) -> some View {
    RoundedRectangle(cornerRadius: 4, style: .continuous)
      .fill(isHighlighted ? Self.highlightTint.opacity(0.18) : .clear)
  }

  private func rowBorder(isHighlighted: Bool, isCurrent: Bool) -> some View {
    let stroke: Color
    let width: CGFloat
    if isHighlighted {
      stroke = Self.highlightTint.opacity(0.65)
      width = 1
    } else if isCurrent {
      stroke = theme.border
      width = 0.5
    } else {
      stroke = .clear
      width = 0
    }
    return RoundedRectangle(cornerRadius: 4, style: .continuous)
      .strokeBorder(stroke, lineWidth: width)
  }

  /// Centers the row window on the current chat so users always see
  /// context before and after it (clamped at list ends).
  private var windowed: [Chat] {
    let all = preview.chats
    guard all.count > Self.maxRows else { return all }
    guard let currentID = preview.currentID,
      let idx = all.firstIndex(where: { $0.id == currentID })
    else { return Array(all.prefix(Self.maxRows)) }
    let half = Self.maxRows / 2
    let start = max(0, min(all.count - Self.maxRows, idx - half))
    return Array(all[start..<(start + Self.maxRows)])
  }

  private static func firstNonEmptyLine(_ text: String) -> String {
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty { return String(trimmed.prefix(80)) }
    }
    return ""
  }
}
