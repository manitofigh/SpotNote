// swiftlint:disable function_body_length large_tuple
import Combine
import Foundation

/// Tiny shared text-editing helpers used by the find bar and fuzzy
/// palette. Their search fields are SwiftUI `TextField`s, which don't
/// expose cursor position or word-deletion commands the way an
/// `NSTextView` does -- so ⌃W operates on the trailing word of the
/// current query string. That's good enough because the cursor in a
/// short search field practically always sits at the end.
enum SearchTextEditing {
  static func deleteWordBackward(_ value: String) -> String {
    var trimmed = value
    while let last = trimmed.last, last.isWhitespace { trimmed.removeLast() }
    while let last = trimmed.last, !last.isWhitespace { trimmed.removeLast() }
    return trimmed
  }
}

/// State for the inline find-in-current-note bar (⌘F).
@MainActor
final class FindController: ObservableObject {
  @Published private(set) var isVisible: Bool = false
  @Published var query: String = ""
  @Published private(set) var matches: [NSRange] = []
  @Published private(set) var currentIndex: Int = 0

  init() {}

  var currentMatch: NSRange? {
    guard !matches.isEmpty, matches.indices.contains(currentIndex) else { return nil }
    return matches[currentIndex]
  }

  func open() {
    isVisible = true
  }

  func close() {
    isVisible = false
    query = ""
    matches = []
    currentIndex = 0
  }

  func toggle(text: String) {
    if isVisible {
      close()
    } else {
      open()
      if !query.isEmpty { search(in: text) }
    }
  }

  func search(in text: String) {
    if query.isEmpty {
      matches = []
      currentIndex = 0
      return
    }
    let nsText = text as NSString
    var found: [NSRange] = []
    var location = 0
    while location < nsText.length {
      let remaining = NSRange(location: location, length: nsText.length - location)
      let range = nsText.range(of: query, options: [.caseInsensitive], range: remaining)
      if range.location == NSNotFound { break }
      found.append(range)
      location = range.location + max(1, range.length)
    }
    matches = found
    currentIndex = found.isEmpty ? 0 : min(currentIndex, found.count - 1)
  }

  func next() {
    guard !matches.isEmpty else { return }
    currentIndex = (currentIndex + 1) % matches.count
  }

  func previous() {
    guard !matches.isEmpty else { return }
    currentIndex = (currentIndex - 1 + matches.count) % matches.count
  }
}

/// One item in the command palette (⌘K).
struct CommandItem: Identifiable, Equatable {
  let id: String
  let title: String
  let subtitle: String
  let category: String
  let icon: String
  let chord: String?
  let executableAction: ShortcutAction?
}

/// State for the command palette (⌘K). Searches over settings and
/// shortcut bindings -- not notes (that's ⌘P / ⌘F).
@MainActor
final class CommandController: ObservableObject {
  @Published private(set) var isVisible: Bool = false
  @Published var query: String = ""
  @Published private(set) var results: [CommandItem] = []
  @Published var selectedIndex: Int = 0
  @Published private(set) var focusRequest: Int = 0

  private var corpus: [CommandItem] = []

  func open(shortcuts: ShortcutStore, preferences: ThemePreferences) {
    corpus = Self.buildCorpus(shortcuts: shortcuts, preferences: preferences)
    isVisible = true
    selectedIndex = 0
    query = ""
    results = corpus
    requestFocus()
  }

  func close() {
    isVisible = false
    query = ""
    results = []
    selectedIndex = 0
  }

  func toggle(shortcuts: ShortcutStore, preferences: ThemePreferences) {
    if isVisible { close() } else { open(shortcuts: shortcuts, preferences: preferences) }
  }

  func setQuery(_ value: String) {
    query = value
    selectedIndex = 0
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      results = corpus
      return
    }
    var ranked: [(item: CommandItem, score: Int)] = []
    for item in corpus {
      let combined = "\(item.title) \(item.subtitle) \(item.category)"
      if let hit = FuzzyMatch.score(query: trimmed, in: combined) {
        ranked.append((item, hit.score))
      }
    }
    ranked.sort { $0.score > $1.score }
    results = ranked.map(\.item)
  }

  func moveSelection(by delta: Int) {
    guard !results.isEmpty else { return }
    selectedIndex = (selectedIndex + delta + results.count) % results.count
  }

  func selectedExecutableAction() -> ShortcutAction? {
    guard results.indices.contains(selectedIndex) else { return nil }
    return results[selectedIndex].executableAction
  }

  func requestFocus() {
    focusRequest &+= 1
  }

  // periphery:ignore:parameters preferences - kept on the API even when
  // no current pane reads from it; future entries (e.g. theme submenu)
  // will need it.
  static func buildCorpus(
    shortcuts: ShortcutStore,
    preferences: ThemePreferences
  ) -> [CommandItem] {
    var items: [CommandItem] = []
    for shortcutAction in ShortcutAction.allCases {
      let chord = shortcuts.binding(for: shortcutAction).displayString
      items.append(
        CommandItem(
          id: "shortcut.\(shortcutAction.rawValue)",
          title: shortcutAction.displayName,
          subtitle: shortcutAction.subtitle,
          category: "Shortcuts",
          icon: "command",
          chord: chord,
          executableAction: executableAction(for: shortcutAction)
        )
      )
    }
    let settings: [(String, String, String)] = [
      ("Line numbers", "Show line numbers on the left side of the HUD.", "lineNumbers"),
      ("Menu bar icon", "Show the SpotNote icon in the macOS menu bar.", "menuBarIcon"),
      ("Max visible lines", "Panel grows up to this many rows before scrolling.", "maxVisibleLines"),
      ("Hints bar", "Show the keyboard shortcut hint strip above the editor.", "hintsBar"),
      ("Vim mode", "Use vim-style keybindings for modal editing.", "vimMode"),
      ("Dim instead of hide", "Keep HUD visible at reduced opacity on focus loss.", "dimOnFocusLoss"),
      ("Unfocused opacity", "How transparent the HUD becomes when unfocused.", "unfocusedOpacity"),
      (
        "Dim background while writing",
        "Reduce only the HUD background opacity while the editor is focused.",
        "dimBackgroundWhileFocused"
      ),
      (
        "Focused background opacity",
        "How transparent the HUD background is while writing.",
        "focusedBackgroundOpacity"
      )
    ]
    for (title, subtitle, key) in settings {
      items.append(
        CommandItem(
          id: "setting.\(key)",
          title: title,
          subtitle: subtitle,
          category: "Editor",
          icon: "gearshape",
          chord: nil,
          executableAction: nil
        )
      )
    }
    for theme in ThemeCatalog.all {
      items.append(
        CommandItem(
          id: "theme.\(theme.id)",
          title: theme.name,
          subtitle: "\(theme.mode == .dark ? "Dark" : "Light") theme",
          category: "Themes",
          icon: "paintpalette",
          chord: nil,
          executableAction: nil
        )
      )
    }
    return items
  }

  private static func executableAction(for action: ShortcutAction) -> ShortcutAction? {
    switch action {
    case .toggleHotkey, .appendToLastNote, .commandPalette:
      return nil
    default:
      return action
    }
  }
}
