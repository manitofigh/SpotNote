import Combine
import Core
import Foundation

/// One ranked hit shown in the fuzzy palette.
struct TextRange: Equatable, Sendable {
  let location: Int
  let length: Int
}

struct FuzzyResult: Equatable, Sendable, Identifiable {
  let chat: Chat
  let score: Int
  let snippet: String
  let matchRanges: [TextRange]
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
    if needle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let computed = Self.rank(query: needle, in: snapshot, limit: limit)
      results = computed
      if selectedIndex >= computed.count { selectedIndex = max(0, computed.count - 1) }
      pendingSearch = nil
      return
    }
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

  func selectedResult() -> FuzzyResult? {
    guard results.indices.contains(selectedIndex) else { return nil }
    return results[selectedIndex]
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
            matchRanges: [],
            position: index + 1
          )
        }
      )
    }
    let terms = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    var ranked: [FuzzyResult] = []
    for (index, chat) in chats.enumerated() {
      let position = index + 1
      if let hit = bestHit(for: terms, in: chat.text) {
        ranked.append(
          FuzzyResult(
            chat: chat,
            score: hit.score,
            snippet: hit.snippet,
            matchRanges: hit.ranges,
            position: position
          )
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

  private struct RankedHit {
    let score: Int
    let snippet: String
    let ranges: [TextRange]
  }

  private nonisolated static func bestHit(for terms: [String], in text: String) -> RankedHit? {
    let title = firstNonEmptyLine(in: text)
    let titleHit = score(terms: terms, in: title.text, baseOffset: title.offset).map { hit in
      RankedHit(
        score: hit.score + 30,
        snippet: snippet(in: text, around: hit.ranges.first?.location),
        ranges: hit.ranges
      )
    }
    let bodyHit = score(terms: terms, in: text, baseOffset: 0).map { hit in
      RankedHit(
        score: hit.score,
        snippet: snippet(in: text, around: hit.ranges.first?.location),
        ranges: hit.ranges
      )
    }
    switch (titleHit, bodyHit) {
    case (.some(let title), .some(let body)): return title.score >= body.score ? title : body
    case (.some(let title), .none): return title
    case (.none, .some(let body)): return body
    case (.none, .none): return nil
    }
  }

  private nonisolated static func score(
    terms: [String],
    in text: String,
    baseOffset: Int
  ) -> (score: Int, ranges: [TextRange])? {
    var total = 0
    var ranges: [TextRange] = []
    for term in terms {
      guard let hit = termHit(term, in: text, baseOffset: baseOffset) else { return nil }
      total += hit.score
      ranges.append(contentsOf: hit.ranges)
    }
    return (total, ranges.sorted { $0.location < $1.location })
  }

  private nonisolated static func termHit(
    _ term: String,
    in text: String,
    baseOffset: Int
  ) -> (score: Int, ranges: [TextRange])? {
    if let exact = exactTermHit(term, in: text, baseOffset: baseOffset) {
      return exact
    }
    guard let fuzzy = FuzzyMatch.score(query: term, in: text) else { return nil }
    return (
      fuzzy.score,
      contiguousRanges(from: fuzzy.matches, baseOffset: baseOffset)
    )
  }

  private nonisolated static func exactTermHit(
    _ term: String,
    in text: String,
    baseOffset: Int
  ) -> (score: Int, ranges: [TextRange])? {
    guard let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else {
      return nil
    }
    let location = text.distance(from: text.startIndex, to: range.lowerBound)
    let length = text.distance(from: range.lowerBound, to: range.upperBound)
    let boundaryBonus = isBoundaryStart(range.lowerBound, in: text) ? 24 : 0
    return (
      term.count * 32 + 40 + boundaryBonus - min(location / 8, 24),
      [TextRange(location: baseOffset + location, length: length)]
    )
  }

  private nonisolated static func isBoundaryStart(_ index: String.Index, in text: String) -> Bool {
    guard index > text.startIndex else { return true }
    let previous = text[text.index(before: index)]
    return previous.isWhitespace || !previous.isLetter && !previous.isNumber
  }

  private nonisolated static func contiguousRanges(
    from matches: [Int],
    baseOffset: Int
  ) -> [TextRange] {
    guard let first = matches.first else { return [] }
    var ranges: [TextRange] = []
    var start = first
    var previous = first
    for offset in matches.dropFirst() {
      if offset == previous + 1 {
        previous = offset
      } else {
        ranges.append(TextRange(location: baseOffset + start, length: previous - start + 1))
        start = offset
        previous = offset
      }
    }
    ranges.append(TextRange(location: baseOffset + start, length: previous - start + 1))
    return ranges
  }

  private nonisolated static func firstNonEmptyLine(in text: String) -> (text: String, offset: Int) {
    var offset = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let raw = String(line)
      let leadingWhitespace = raw.prefix(while: \.isWhitespace).count
      let trimmed = raw.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty { return (trimmed, offset + leadingWhitespace) }
      offset += raw.count + 1
    }
    return ("", 0)
  }

  private nonisolated static func snippet(in text: String, around offset: Int?) -> String {
    guard let offset, !text.isEmpty else { return previewLine(text) }
    let clamped = max(0, min(offset, text.count - 1))
    let index = text.index(text.startIndex, offsetBy: clamped)
    let start = text[..<index].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
    let end = text[index...].firstIndex(of: "\n") ?? text.endIndex
    let line = text[start..<end].trimmingCharacters(in: .whitespaces)
    if line.isEmpty { return previewLine(text) }
    return String(line.prefix(120))
  }
}
