// swiftlint:disable function_body_length large_tuple
import Combine
import Core
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
}

/// State for the command palette (⌘K). Searches over settings and
/// shortcut bindings -- not notes (that's ⌘P / ⌘F).
@MainActor
final class CommandController: ObservableObject {
  @Published private(set) var isVisible: Bool = false
  @Published var query: String = ""
  @Published private(set) var results: [CommandItem] = []
  @Published var selectedIndex: Int = 0

  private var corpus: [CommandItem] = []

  func open(shortcuts: ShortcutStore, preferences: ThemePreferences) {
    corpus = Self.buildCorpus(shortcuts: shortcuts, preferences: preferences)
    isVisible = true
    selectedIndex = 0
    query = ""
    results = corpus
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
          chord: chord
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
      ("Unfocused opacity", "How transparent the HUD becomes when unfocused.", "unfocusedOpacity")
    ]
    for (title, subtitle, key) in settings {
      items.append(
        CommandItem(
          id: "setting.\(key)",
          title: title,
          subtitle: subtitle,
          category: "Editor",
          icon: "gearshape",
          chord: nil
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
          chord: nil
        )
      )
    }
    return items
  }
}

/// One ranked hit shown in the fuzzy palette.
struct FuzzyResult: Equatable, Sendable, Identifiable {
  let chat: Chat
  let score: Int
  let snippet: String
  /// 1-based position in the most-recently-edited corpus, surfaced in
  /// the palette so users can correlate hits with the ⌃N/⌃P "note N of
  /// M" indicator.
  let position: Int
  var id: UUID { chat.id }
}

/// State for the fuzzy "open any note" palette (⌘P). Search runs on a
/// background priority task so a 1k-note corpus stays responsive even
/// while the user is mid-keystroke; results trickle back to the main
/// actor and replace the published list.
@MainActor
final class FuzzyController: ObservableObject {
  @Published private(set) var isVisible: Bool = false
  @Published var query: String = ""
  @Published private(set) var results: [FuzzyResult] = []
  @Published var selectedIndex: Int = 0

  static let resultLimit = 50

  private var corpus: [Chat] = []
  private var pendingSearch: Task<Void, Never>?
  private let debounce: Duration

  init(debounce: Duration = .milliseconds(40)) {
    self.debounce = debounce
  }

  func open(corpus: [Chat]) {
    self.corpus = corpus
    isVisible = true
    selectedIndex = 0
    refresh()
  }

  func close() {
    pendingSearch?.cancel()
    pendingSearch = nil
    isVisible = false
    query = ""
    results = []
    selectedIndex = 0
  }

  func toggle(corpus: [Chat]) {
    if isVisible { close() } else { open(corpus: corpus) }
  }

  func setQuery(_ value: String) {
    query = value
    selectedIndex = 0
    pendingSearch?.cancel()
    let snapshot = corpus
    let needle = value
    let limit = Self.resultLimit
    let delay = debounce
    pendingSearch = Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      let computed = await Task.detached(priority: .userInitiated) {
        FuzzyController.rank(query: needle, in: snapshot, limit: limit)
      }.value
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let self, self.isVisible, self.query == needle else { return }
        self.results = computed
        if self.selectedIndex >= computed.count { self.selectedIndex = max(0, computed.count - 1) }
      }
    }
  }

  func selectedChat() -> Chat? {
    guard results.indices.contains(selectedIndex) else { return nil }
    return results[selectedIndex].chat
  }

  func moveSelection(by delta: Int) {
    guard !results.isEmpty else { return }
    let next = (selectedIndex + delta + results.count) % results.count
    selectedIndex = next
  }

  /// Updates the in-memory corpus without resetting the visible query.
  /// Called when the chat list changes (e.g. after a delete) so a
  /// keep-open palette stays in sync.
  func updateCorpus(_ chats: [Chat]) {
    corpus = chats
    if isVisible { refresh() }
  }

  private func refresh() {
    setQuery(query)
  }

  /// Pure scoring entry point used by both the palette refresh path
  /// and the test suite. Marked `nonisolated` so the detached search
  /// task can call it without bouncing through the main actor.
  nonisolated static func rank(
    query: String,
    in chats: [Chat],
    limit: Int
  ) -> [FuzzyResult] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return Array(
        chats.prefix(limit).enumerated().map { index, chat in
          FuzzyResult(
            chat: chat,
            score: 0,
            snippet: previewLine(chat.text),
            position: index + 1
          )
        }
      )
    }
    var ranked: [FuzzyResult] = []
    for (index, chat) in chats.enumerated() {
      let snippet = previewLine(chat.text)
      let position = index + 1
      // Title match outranks body match by a small constant so a hit
      // in the first line is almost always preferred.
      if let titleHit = FuzzyMatch.score(query: trimmed, in: snippet) {
        ranked.append(
          FuzzyResult(
            chat: chat,
            score: titleHit.score + 5,
            snippet: snippet,
            position: position
          )
        )
        continue
      }
      if let bodyHit = FuzzyMatch.score(query: trimmed, in: chat.text) {
        ranked.append(
          FuzzyResult(chat: chat, score: bodyHit.score, snippet: snippet, position: position)
        )
      }
    }
    ranked.sort { $0.score > $1.score }
    return Array(ranked.prefix(limit))
  }

  nonisolated static func previewLine(_ text: String) -> String {
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty { return String(trimmed.prefix(120)) }
    }
    return ""
  }
}
