import Foundation

/// Summary of one stored version, newest-first in the browser.
public struct NoteVersion: Sendable, Equatable, Identifiable {
  /// Position in the note's log (0 = oldest). Stable until the next
  /// thinning pass; `date` disambiguates across one.
  public let id: Int
  public let date: Date
  /// Lines added / removed relative to the previous version.
  public let addedLines: Int
  public let removedLines: Int
}

/// Decoded, in-memory history of a single note. Pure value type -- the
/// actor owns persistence.
struct NoteHistoryLog: Sendable {
  private(set) var entries: [HistoryEntry] = []
  /// UTF-8 body of the newest version (empty when there are none).
  private(set) var latest: [UInt8] = []
  private var sinceKeyframe = 0

  init() {}

  /// Rebuilds the log from decoded file entries.
  /// - Throws: `NoteHistoryError.corrupted` if the delta chain is broken.
  /// - Complexity: O(n · text size).
  init(entries: [HistoryEntry]) throws {
    var text: [UInt8] = []
    var since = 0
    var hasKeyframe = false
    for entry in entries {
      switch entry.payload {
      case .keyframe(let bytes):
        text = bytes
        since = 0
        hasKeyframe = true
      case .delta(let delta):
        guard hasKeyframe else { throw NoteHistoryError.corrupted }
        text = try delta.apply(to: text)
        since += 1
      }
    }
    self.entries = entries
    self.latest = text
    self.sinceKeyframe = since
  }

  var isEmpty: Bool { entries.isEmpty }
  var lastDate: Date? { entries.last?.date }

  /// Appends `bytes` as a new version: a delta against `latest`, or a
  /// keyframe when the chain is due for one (every `keyframeInterval`)
  /// or the delta would not be meaningfully smaller than the text.
  @discardableResult
  mutating func append(_ bytes: [UInt8], delta: HistoryDelta?, date: Date, keyframeInterval: Int) -> HistoryEntry {
    let entry: HistoryEntry
    let isChainDue = entries.isEmpty || sinceKeyframe + 1 >= keyframeInterval
    if let delta, !isChainDue, delta.insertedByteCount * 2 < bytes.count {
      entry = HistoryEntry(date: date, payload: .delta(delta))
      sinceKeyframe += 1
    } else {
      entry = HistoryEntry(date: date, payload: .keyframe(bytes))
      sinceKeyframe = 0
    }
    entries.append(entry)
    latest = bytes
    return entry
  }

  /// Full text of version `index`, replaying from the nearest keyframe.
  /// - Complexity: O(K · text size), K = keyframe interval.
  func bytes(at index: Int) throws -> [UInt8] {
    guard entries.indices.contains(index) else { throw NoteHistoryError.corrupted }
    let start = entries[...index].lastIndex { entry in
      if case .keyframe = entry.payload { return true }
      return false
    }
    guard let start, case .keyframe(var text) = entries[start].payload else { throw NoteHistoryError.corrupted }
    for entry in entries[start...index].dropFirst() {
      if case .delta(let delta) = entry.payload { text = try delta.apply(to: text) }
    }
    return text
  }

  /// Version summaries with +/- line counts, newest first.
  /// - Complexity: O(n · text size).
  func summaries() throws -> [NoteVersion] {
    var previous: [UInt8] = []
    var result: [NoteVersion] = []
    result.reserveCapacity(entries.count)
    for (index, entry) in entries.enumerated() {
      let current: [UInt8]
      switch entry.payload {
      case .keyframe(let bytes): current = bytes
      case .delta(let stored): current = try stored.apply(to: previous)
      }
      let stats = HistoryDelta.lineStats(from: previous, to: current)
      result.append(NoteVersion(id: index, date: entry.date, addedLines: stats.added, removedLines: stats.removed))
      previous = current
    }
    return result.reversed()
  }

  /// Re-encodes only the versions at `kept` with a fresh keyframe chain.
  /// - Complexity: O(n · text size).
  func compacted(keeping kept: [Int], keyframeInterval: Int) throws -> NoteHistoryLog {
    var keptSet = Set(kept)
    var rebuilt = NoteHistoryLog()
    var text: [UInt8] = []
    for (index, entry) in entries.enumerated() {
      switch entry.payload {
      case .keyframe(let bytes): text = bytes
      case .delta(let delta): text = try delta.apply(to: text)
      }
      guard keptSet.remove(index) != nil else { continue }
      let delta = rebuilt.isEmpty ? nil : HistoryDelta.between(rebuilt.latest, text)
      rebuilt.append(text, delta: delta, date: entry.date, keyframeInterval: keyframeInterval)
    }
    return rebuilt
  }
}
