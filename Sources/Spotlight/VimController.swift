import AppKit
import Combine
import SwiftUI

@MainActor
final class VimController: ObservableObject {
  enum PromptKind: Equatable { case command, search }

  enum MessageKind: Equatable { case info, success, error }

  struct Message: Equatable {
    let text: String
    let kind: MessageKind
  }

  struct Prompt: Equatable {
    let kind: PromptKind
    var buffer: String
  }

  struct SearchOutcome: Equatable {
    let current: Int
    let total: Int
  }

  @Published var mode: VimMode = .normal
  @Published var prompt: Prompt?
  @Published var message: Message?
  /// Sticky status from the last `/` search or `n`/`N` step (e.g.
  /// "2/5", "no matches"). Cleared on `:noh` or when a new search runs.
  @Published var searchStatus: String?

  /// Editor-side handlers wired by `PlaceholderTextView` once it has a
  /// reference to the live text view. They are reset to `nil` when the
  /// HUD closes so we don't leak the AppKit view across panel teardowns.
  var lineJumpHandler: ((Int) -> Bool)?
  var substituteHandler: ((SubstituteRequest) -> Int)?

  /// Top-level command runner installed by the `SpotlightWindowController`
  /// so commands can reach the session, find controller, theme catalog,
  /// and the close-HUD path.
  var commandRunner: ((VimCommand) -> Message?)?

  /// Search handler installed by the window controller. Returns the
  /// resulting current/total match counts (or `nil` for no matches) so
  /// the bottom bar can render a vim-native indicator instead of
  /// opening the find bar.
  var searchHandler: ((String) -> SearchOutcome?)?

  /// Step handler for normal-mode `n` / `N`. Same return semantics as
  /// `searchHandler`.
  var findStepHandler: ((Int) -> SearchOutcome?)?

  private var messageClearTask: Task<Void, Never>?
  private static let messageDuration: Duration = .seconds(2)

  func updateMode(_ newMode: VimMode) {
    if mode != newMode { mode = newMode }
    if newMode == .insert {
      if prompt != nil { prompt = nil }
      // Search counters refer to a stale match index the moment the user
      // starts editing -- drop them so they don't linger as a confusing
      // "2/5" while typing unrelated text.
      if searchStatus != nil { searchStatus = nil }
    }
  }

  func enterPrompt(_ kind: PromptKind) {
    prompt = Prompt(kind: kind, buffer: "")
    message = nil
    messageClearTask?.cancel()
    messageClearTask = nil
  }

  func cancelPrompt() {
    prompt = nil
  }

  func appendToPrompt(_ text: String) {
    guard var current = prompt else { return }
    current.buffer.append(text)
    prompt = current
  }

  func backspacePrompt() {
    guard var current = prompt else { return }
    if current.buffer.isEmpty {
      prompt = nil
      return
    }
    current.buffer.removeLast()
    prompt = current
  }

  /// Returns `true` if the prompt was submitted (and therefore should be
  /// dismissed by the caller); always dismisses on completion.
  @discardableResult
  func submitPrompt() -> Bool {
    guard let current = prompt else { return false }
    let buffer = current.buffer
    prompt = nil
    switch current.kind {
    case .command:
      let trimmed = buffer.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { return true }
      runCommand(trimmed)
    case .search:
      let trimmed = buffer.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        searchStatus = nil
      } else {
        applySearchOutcome(searchHandler?(buffer))
      }
    }
    return true
  }

  func findStep(_ delta: Int) {
    applySearchOutcome(findStepHandler?(delta))
  }

  func clearSearchStatus() {
    searchStatus = nil
  }

  private func applySearchOutcome(_ outcome: SearchOutcome?) {
    if let outcome, outcome.total > 0 {
      searchStatus = "\(outcome.current)/\(outcome.total)"
    } else {
      searchStatus = "no matches"
    }
  }

  func showMessage(_ text: String, kind: MessageKind) {
    let msg = Message(text: text, kind: kind)
    message = msg
    messageClearTask?.cancel()
    let duration = Self.messageDuration
    messageClearTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      if self?.message == msg { self?.message = nil }
    }
  }

  func runCommand(_ raw: String) {
    let parsed = VimCommandParser.parse(raw)
    switch parsed {
    case .invalid(let text):
      showMessage(text, kind: .error)
    case .valid(let command):
      let result = commandRunner?(command)
      if let result {
        showMessage(result.text, kind: result.kind)
      }
    }
  }
}

// MARK: - Commands

enum VimCommand: Equatable {
  case quit
  case writeNoOp
  case newNote
  case deleteNote
  case setLineNumbers(Bool)
  case setVimMode(Bool)
  case setHints(Bool)
  case setTheme(String)
  case setMaxLines(Int)
  case substitute(SubstituteRequest)
  case gotoLine(Int)
  case clearHighlight
  case help
}

struct SubstituteRequest: Equatable {
  /// `true` when prefixed with `%` (operate on whole text). `false` is
  /// "current line only" -- driven by the editor's caret position.
  let global: Bool
  /// `true` when the trailing `g` flag is present (replace every
  /// occurrence in the chosen range, not just the first per line).
  let replaceAll: Bool
  let pattern: String
  let replacement: String
}

enum VimCommandParseResult {
  case valid(VimCommand)
  case invalid(String)
}

enum VimCommandParser {
  /// Static lookup for headword commands. Keeping this off the
  /// switch-statement keeps `parse` under the cyclomatic-complexity cap.
  private static let headwordTable: [String: VimCommand] = [
    "q": .quit, "quit": .quit, "x": .quit,
    "w": .writeNoOp, "write": .writeNoOp, "wq": .writeNoOp,
    "e": .newNote, "enew": .newNote,
    "bd": .deleteNote, "bdelete": .deleteNote,
    "noh": .clearHighlight, "nohlsearch": .clearHighlight,
    "h": .help, "help": .help
  ]

  static func parse(_ raw: String) -> VimCommandParseResult {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return .invalid(notACommand(trimmed)) }
    if let line = Int(trimmed), line > 0 { return .valid(.gotoLine(line)) }
    if trimmed.hasPrefix("s/") { return parseSubstitute(trimmed, global: false) }
    if trimmed.hasPrefix("%s/") {
      return parseSubstitute(String(trimmed.dropFirst()), global: true)
    }
    let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let head = String(parts[0])
    let argument = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
    if head == "set" { return parseSet(argument) }
    if let command = headwordTable[head] { return .valid(command) }
    return .invalid(notACommand(trimmed))
  }

  private static func parseSet(_ argument: String) -> VimCommandParseResult {
    let pieces = argument.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard let first = pieces.first.map(String.init), !first.isEmpty else {
      return .invalid("E518: unknown option")
    }
    let value = pieces.count > 1 ? String(pieces[1]).trimmingCharacters(in: .whitespaces) : ""
    if let toggle = setToggleTable[first] { return .valid(toggle) }
    return parseSetParameterized(first, value: value)
  }

  /// Boolean `:set` flags. Every entry here is a no-argument toggle.
  private static let setToggleTable: [String: VimCommand] = [
    "number": .setLineNumbers(true), "nu": .setLineNumbers(true),
    "nonumber": .setLineNumbers(false), "nonu": .setLineNumbers(false),
    "vim": .setVimMode(true), "novim": .setVimMode(false),
    "hints": .setHints(true), "nohints": .setHints(false)
  ]

  private static func parseSetParameterized(
    _ option: String,
    value: String
  ) -> VimCommandParseResult {
    switch option {
    case "theme":
      guard !value.isEmpty else { return .invalid("E518: theme name required") }
      return .valid(.setTheme(value))
    case "lines":
      guard let count = Int(value), count > 0 else {
        return .invalid("E518: lines must be a positive integer")
      }
      return .valid(.setMaxLines(count))
    default:
      return .invalid("E518: unknown option: \(option)")
    }
  }

  private static func parseSubstitute(_ raw: String, global: Bool) -> VimCommandParseResult {
    // `s/pattern/replacement/flags` -- split on `/`, no escape handling.
    let body = String(raw.dropFirst(2))  // strip `s/`
    let segments = body.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard segments.count >= 2 else {
      return .invalid("E486: invalid substitute syntax")
    }
    let pattern = segments[0]
    let replacement = segments[1]
    let flags = segments.count >= 3 ? segments[2] : ""
    guard !pattern.isEmpty else { return .invalid("E486: pattern required") }
    let replaceAll = flags.contains("g")
    return .valid(
      .substitute(
        SubstituteRequest(
          global: global,
          replaceAll: replaceAll,
          pattern: pattern,
          replacement: replacement
        )
      )
    )
  }

  private static func notACommand(_ raw: String) -> String {
    "E492: not an editor command: \(raw)"
  }
}

// MARK: - Reference catalog

/// Static reference list of every command supported by `VimCommandParser`.
/// Surfaced in the Settings -> Vim pane so users have a single source of
/// truth for what the prompt accepts.
enum VimCommandReference {
  struct Entry: Identifiable {
    let id: String
    let usage: String
    let summary: String
  }

  struct Section: Identifiable {
    let id: String
    let title: String
    let entries: [Entry]
  }

  static let sections: [Section] = [
    Section(
      id: "lifecycle",
      title: "Lifecycle",
      entries: [
        Entry(
          id: "q",
          usage: ":q\n:quit",
          summary: "Close the HUD."
        ),
        Entry(
          id: "w",
          usage: ":w\n:write",
          summary: "Symbolic. Left it in because some people have the muscle memory."
        ),
        Entry(
          id: "wq",
          usage: ":wq",
          summary: "Symbolic. Left it in because some people have the muscle memory."
        ),
        Entry(
          id: "x",
          usage: ":x",
          summary: "Close the HUD."
        ),
        Entry(
          id: "e",
          usage: ":e\n:enew",
          summary: "Start a new note."
        ),
        Entry(
          id: "bd",
          usage: ":bd\n:bdelete",
          summary: "Delete the current note."
        )
      ]
    ),
    Section(
      id: "settings",
      title: "Settings (:set)",
      entries: [
        Entry(
          id: "number",
          usage: ":set number\n:set nonumber  (nu / nonu)",
          summary: "Show or hide line numbers."
        ),
        Entry(
          id: "vim",
          usage: ":set vim\n:set novim",
          summary: "Toggle vim mode itself. `:set novim` exits vim entirely."
        ),
        Entry(
          id: "hints",
          usage: ":set hints\n:set nohints",
          summary: "Show or hide the hints bar above the editor."
        ),
        Entry(
          id: "theme",
          usage: ":set theme <name>",
          summary: "Switch theme by name (e.g. `obsidian`, `parchment`)."
        ),
        Entry(
          id: "lines",
          usage: ":set lines <n>",
          summary: "Maximum visible rows before the editor starts scrolling."
        )
      ]
    ),
    Section(
      id: "search",
      title: "Search & navigation",
      entries: [
        Entry(
          id: "subst",
          usage: ":s/foo/bar/[g]\n:%s/foo/bar/[g]",
          summary: "Substitute. `%` operates on the whole note, `g` on every match."
        ),
        Entry(
          id: "linejump",
          usage: ":<n>\n<n>G",
          summary: "Jump caret to line n."
        ),
        Entry(
          id: "noh",
          usage: ":noh\n:nohlsearch",
          summary: "Clear the active search highlight and counter."
        ),
        Entry(
          id: "slash",
          usage: "/<pattern>",
          summary: "Vim-native search. Matches highlight in the editor; the bottom bar shows `i/total`."
        ),
        Entry(
          id: "n",
          usage: "n  ·  N",
          summary: "Next / previous match in the active search."
        )
      ]
    ),
    Section(
      id: "help",
      title: "Help",
      entries: [
        Entry(
          id: "help",
          usage: ":h\n:help",
          summary: "Show the hints bar."
        )
      ]
    )
  ]
}
