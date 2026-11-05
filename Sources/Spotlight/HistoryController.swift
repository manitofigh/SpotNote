import Combine
import Core
import Foundation

/// A version's text split into lines, each flagged when it does not
/// appear in the note's current text -- what restoring would bring back.
struct HistoryPreview: Equatable, Sendable {
  struct Line: Equatable, Sendable, Identifiable {
    let id: Int
    let text: String
    let isChanged: Bool
  }

  static let lineLimit = 400

  let lines: [Line]
  let isTruncated: Bool

  /// - Complexity: O(n + m) lines (multiset membership, not a full diff).
  static func make(version: String, current: String) -> HistoryPreview {
    var available: [Substring: Int] = [:]
    for line in current.split(separator: "\n", omittingEmptySubsequences: false) {
      available[line, default: 0] += 1
    }
    let all = version.split(separator: "\n", omittingEmptySubsequences: false)
    var lines: [Line] = []
    lines.reserveCapacity(min(all.count, lineLimit))
    for (index, line) in all.prefix(lineLimit).enumerated() {
      let remaining = available[line, default: 0]
      if remaining > 0 { available[line] = remaining - 1 }
      lines.append(Line(id: index, text: String(line), isChanged: remaining == 0))
    }
    return HistoryPreview(lines: lines, isTruncated: all.count > lineLimit)
  }
}

/// State for the version-history browser of the open note (⌘Y).
@MainActor
final class HistoryController: ObservableObject {
  @Published private(set) var isVisible = false
  @Published private(set) var versions: [NoteVersion] = []
  @Published private(set) var selectedIndex = 0
  @Published private(set) var preview: HistoryPreview?
  @Published private(set) var isLoading = false
  @Published private(set) var isEnabled = true

  /// Invoked with the selected version's text on Return. Set by the
  /// window controller, which owns the editor (for undoable replacement).
  var onRestore: ((String) -> Void)?

  private var history: NoteHistoryStore?
  private var noteID: UUID?
  private var currentText = ""
  private var selectedText: String?
  /// Loads the version list, then the preview; replaced (and cancelled)
  /// by every selection change and by `close()`.
  private var loadTask: Task<Void, Never>?

  func toggle(noteID: UUID?, currentText: String, history: NoteHistoryStore?) {
    if isVisible {
      close()
    } else {
      open(noteID: noteID, currentText: currentText, history: history)
    }
  }

  func open(noteID: UUID?, currentText: String, history: NoteHistoryStore?) {
    self.history = history
    self.noteID = noteID
    self.currentText = currentText
    isEnabled = history != nil && NoteHistoryStore.isEnabled()
    versions = []
    selectedIndex = 0
    preview = nil
    selectedText = nil
    isVisible = true
    guard let history, let noteID else { return }
    isLoading = true
    loadTask?.cancel()
    loadTask = Task { [weak self] in
      // Flush the open note as a version first, so the list includes the
      // text the user is looking at right now.
      await history.record(noteID, text: currentText, trigger: .checkpoint)
      let versions = await history.versions(of: noteID)
      guard !Task.isCancelled, let self else { return }
      self.versions = versions
      self.isLoading = false
      self.loadPreview()
    }
  }

  func close() {
    loadTask?.cancel()
    loadTask = nil
    isVisible = false
    versions = []
    preview = nil
    selectedText = nil
    isLoading = false
  }

  func moveSelection(by delta: Int) {
    guard !versions.isEmpty else { return }
    selectedIndex = (selectedIndex + delta + versions.count) % versions.count
    loadPreview()
  }

  func select(_ index: Int) {
    guard versions.indices.contains(index), index != selectedIndex else { return }
    selectedIndex = index
    loadPreview()
  }

  func restoreSelected() {
    guard let selectedText else { return }
    close()
    onRestore?(selectedText)
  }

  private func loadPreview() {
    guard let history, let noteID, versions.indices.contains(selectedIndex) else { return }
    let version = versions[selectedIndex]
    let current = currentText
    selectedText = nil
    loadTask?.cancel()
    loadTask = Task { [weak self] in
      let text = await history.text(of: noteID, version: version)
      guard !Task.isCancelled, let self else { return }
      self.selectedText = text
      self.preview = text.map { HistoryPreview.make(version: $0, current: current) }
    }
  }
}
