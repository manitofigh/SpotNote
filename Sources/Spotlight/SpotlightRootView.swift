import AppKit
import Combine
import SwiftUI

@MainActor
final class FocusTrigger: ObservableObject {
  @Published private(set) var tick: Int = 0
  /// Bumped to ask the editor to move its caret to the very end of the
  /// current note's text. Used by the append-to-last-note global hotkey.
  @Published private(set) var caretEndTick: Int = 0
  func pulse() { tick &+= 1 }
  func requestCaretEnd() { caretEndTick &+= 1 }
}

private enum InterFont {
  static let regular = "Inter-Regular"
}

struct SpotlightRootView: View {
  @ObservedObject var focusTrigger: FocusTrigger
  @ObservedObject var preferences: ThemePreferences
  @ObservedObject var session: ChatSession
  @ObservedObject var shortcuts: ShortcutStore
  @ObservedObject var find: FindController
  @ObservedObject var fuzzy: FuzzyController
  @ObservedObject var command: CommandController
  @ObservedObject var copy: CopyController
  @ObservedObject var vimController: VimController
  /// Called synchronously from the editor delegate when the text's line
  /// count changes, so the panel resize happens in the same runloop tick
  /// as the text mutation (no flash).
  let onHeightChange: (CGFloat) -> Void
  /// Invoked when Esc should dismiss the HUD (vim off, or vim on and
  /// already in normal mode).
  let onEscape: () -> Void

  private var theme: Theme { preferences.activeTheme }

  private var editorFont: NSFont {
    NSFont(name: InterFont.regular, size: EditorMetrics.fontSize)
      ?? .systemFont(ofSize: EditorMetrics.fontSize)
  }

  /// Binding that funnels user edits through `session.persistIfNeeded()`
  /// so they hit the debounced store writer. Programmatic chat-switches
  /// bypass this path by assigning `session.currentText` directly.
  private var editorText: Binding<String> {
    Binding(
      get: { session.currentText },
      set: { newValue in
        guard session.currentText != newValue else { return }
        session.currentText = newValue
        session.persistIfNeeded()
        if find.isVisible { find.search(in: newValue) }
      }
    )
  }

  static let vimBarHeight: CGFloat = 18

  private var extraChromeHeight: CGFloat {
    var total: CGFloat = 0
    if find.isVisible { total += EditorMetrics.findBarHeight }
    if preferences.showHints { total += EditorMetrics.tutorialBarHeight }
    if preferences.vimMode { total += Self.vimBarHeight }
    if fuzzy.isVisible {
      total += FuzzyPalette.reservedHeight
    } else if command.isVisible {
      total += CommandPalette.reservedHeight
    } else if session.navigationPreview != nil {
      total += NavigationOverlay.reservedHeight
    }
    return total
  }

  var body: some View {
    VStack(spacing: 0) {
      if find.isVisible {
        FindBar(controller: find, theme: theme, editorText: session.currentText)
          .transition(.opacity)
      }
      if preferences.showHints {
        TutorialBar(theme: theme, shortcuts: shortcuts) {
          preferences.showHints = false
        }
      }
      editorCard
        .transaction { $0.animation = nil }
      if preferences.vimMode {
        vimModeBar
          .transaction { $0.animation = nil }
      }
      if fuzzy.isVisible {
        FuzzyPalette(controller: fuzzy, theme: theme) { chat in
          session.jump(to: chat)
        }
        .padding(.horizontal, EditorMetrics.outerPadding)
        .padding(.bottom, EditorMetrics.outerPadding)
        .frame(height: FuzzyPalette.reservedHeight)
        .transition(.opacity)
      } else if command.isVisible {
        CommandPalette(controller: command, theme: theme)
          .padding(.horizontal, EditorMetrics.outerPadding)
          .padding(.bottom, EditorMetrics.outerPadding)
          .frame(height: CommandPalette.reservedHeight)
          .transition(.opacity)
      } else if let preview = session.navigationPreview {
        NavigationOverlay(
          preview: preview,
          theme: theme,
          shortcuts: shortcuts,
          canUndo: session.lastDeleted != nil
        )
        .padding(.horizontal, EditorMetrics.outerPadding)
        .padding(.bottom, EditorMetrics.outerPadding)
        .frame(height: NavigationOverlay.reservedHeight)
        .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .colorScheme(theme.mode == .dark ? .dark : .light)
    .animation(.easeOut(duration: 0.10), value: session.navigationPreview != nil)
    .animation(.easeOut(duration: 0.10), value: find.isVisible)
    .animation(.easeOut(duration: 0.10), value: fuzzy.isVisible)
    .animation(.easeOut(duration: 0.10), value: command.isVisible)
    .onChange(of: session.chats) { _, newChats in
      fuzzy.updateCorpus(newChats)
    }
    .onChange(of: find.isVisible) { _, isVisible in
      if !isVisible { focusTrigger.pulse() }
    }
    .onChange(of: fuzzy.isVisible) { _, isVisible in
      if !isVisible { focusTrigger.pulse() }
    }
    .onChange(of: command.isVisible) { _, isVisible in
      if !isVisible { focusTrigger.pulse() }
    }
    .onChange(of: preferences.showHints) { _, _ in
      let editorHeight = EditorMetrics.panelHeight(
        forLines: EditorMetrics.lineCount(in: session.currentText),
        maxLines: preferences.maxVisibleLines
      )
      onHeightChange(editorHeight + extraChromeHeight)
    }
    .onAppear {
      let editorHeight = EditorMetrics.panelHeight(
        forLines: EditorMetrics.lineCount(in: session.currentText),
        maxLines: preferences.maxVisibleLines
      )
      onHeightChange(editorHeight + extraChromeHeight)
    }
  }

  private var hasAttachedBottom: Bool {
    preferences.vimMode || session.navigationPreview != nil
      || fuzzy.isVisible || command.isVisible
  }

  private var editorCardShape: UnevenRoundedRectangle {
    let flat = hasAttachedBottom
    return UnevenRoundedRectangle(
      topLeadingRadius: 10,
      bottomLeadingRadius: flat ? 0 : 10,
      bottomTrailingRadius: flat ? 0 : 10,
      topTrailingRadius: 10,
      style: .continuous
    )
  }

  private var editorCard: some View {
    MultilineEditor(
      text: editorText,
      theme: theme,
      placeholder: "Jot something down…",
      showLineNumbers: preferences.showLineNumbers,
      font: editorFont,
      focusRequest: focusTrigger.tick,
      caretEndRequest: focusTrigger.caretEndTick,
      maxVisibleLines: preferences.maxVisibleLines,
      extraChromeHeight: extraChromeHeight,
      findHighlight: find.currentMatch,
      vimModeEnabled: preferences.vimMode,
      vimController: vimController,
      onEscape: onEscape,
      onHeightChange: onHeightChange
    )
    .padding(.leading, EditorMetrics.leadingInset)
    .padding(.trailing, EditorMetrics.trailingInset)
    .padding(.vertical, EditorMetrics.verticalInset)
    .background(editorCardShape.fill(theme.background))
    .overlay(editorCardShape.strokeBorder(theme.border, lineWidth: 1))
    .overlay(alignment: .topTrailing) {
      CopyButton(controller: copy, theme: theme) {
        copy.copy(session.currentText)
      }
      .padding(.trailing, 6)
      .padding(.top, 9)
    }
    .padding(.top, EditorMetrics.outerPadding)
    .padding(.horizontal, EditorMetrics.outerPadding)
    .padding(.bottom, hasAttachedBottom ? 0 : EditorMetrics.outerPadding)
  }

  private var hasOverlayBelow: Bool {
    fuzzy.isVisible || command.isVisible || session.navigationPreview != nil
  }

  private var vimBarShape: UnevenRoundedRectangle {
    let roundBottom = !hasOverlayBelow
    return UnevenRoundedRectangle(
      topLeadingRadius: 0,
      bottomLeadingRadius: roundBottom ? 10 : 0,
      bottomTrailingRadius: roundBottom ? 10 : 0,
      topTrailingRadius: 0,
      style: .continuous
    )
  }

  private var vimModeBar: some View {
    HStack(spacing: 6) {
      if let prompt = vimController.prompt {
        VimPromptView(prompt: prompt, theme: theme)
        Spacer(minLength: 0)
      } else {
        Text(label(for: vimController.mode))
          .font(.system(size: 9, weight: .semibold, design: .monospaced))
          .foregroundStyle(color(for: vimController.mode))
        Spacer(minLength: 8)
        if let message = vimController.message {
          Text(message.text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(messageColor(for: message.kind))
            .lineLimit(1)
            .truncationMode(.tail)
        } else if let status = vimController.searchStatus {
          Text(status)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.text.opacity(0.55))
            .lineLimit(1)
        }
      }
    }
    .padding(.horizontal, 8)
    .frame(height: Self.vimBarHeight)
    .background(vimBarShape.fill(theme.background))
    .overlay(alignment: .top) {
      Rectangle()
        .fill(theme.border.opacity(0.6))
        .frame(height: 1)
    }
    .overlay(vimBarShape.strokeBorder(theme.border, lineWidth: 1))
    .padding(.horizontal, EditorMetrics.outerPadding)
  }

  private func label(for mode: VimMode) -> String {
    switch mode {
    case .normal: return "NORMAL"
    case .insert: return "INSERT"
    case .visualLine: return "VISUAL LINE"
    }
  }

  private func color(for mode: VimMode) -> Color {
    switch mode {
    case .normal: return theme.text.opacity(0.7)
    case .insert: return theme.placeholder
    case .visualLine: return theme.text.opacity(0.85)
    }
  }

  private func messageColor(for kind: VimController.MessageKind) -> Color {
    switch kind {
    case .info: return theme.text.opacity(0.7)
    case .success: return Color(red: 0.40, green: 0.78, blue: 0.50)
    case .error: return Color(red: 0.95, green: 0.45, blue: 0.45)
    }
  }
}

/// Renders the active `:` / `/` prompt with a slow-blinking caret. The
/// caret is a discrete `▏` glyph rather than an `NSTextField` so the
/// prompt can live in the bottom bar without stealing first responder
/// from the editor (the prompt keystrokes are intercepted at the
/// `NSTextView` layer, not the prompt itself).
private struct VimPromptView: View {
  let prompt: VimController.Prompt
  let theme: Theme

  var body: some View {
    HStack(spacing: 0) {
      Text(prefix)
        .foregroundStyle(theme.text.opacity(0.85))
      Text(prompt.buffer)
        .foregroundStyle(theme.text)
      TimelineView(.periodic(from: .now, by: 0.55)) { context in
        let visible = Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
        Text("▏")
          .foregroundStyle(theme.text.opacity(visible ? 0.95 : 0))
      }
    }
    .font(.system(size: 11, weight: .regular, design: .monospaced))
    .lineLimit(1)
    .truncationMode(.head)
  }

  private var prefix: String {
    prompt.kind == .command ? ":" : "/"
  }
}
