/// A compact byte-level edit that turns one UTF-8 note body into the
/// next. Stored as an ordered list of hunks: each hunk replaces
/// `removeCount` bytes at `offset` in the *base* with `inserted`.
///
/// Hunks are found with a line-level diff (so edits in several places
/// of a long note stay small), then each hunk is trimmed to its common
/// byte prefix/suffix (so a one-character fix inside a long line stores
/// one byte, not the whole line). Operating on raw UTF-8 bytes keeps
/// the round-trip byte-exact even when a hunk boundary falls inside a
/// multi-byte scalar.
struct HistoryDelta: Equatable, Sendable {
  struct Hunk: Equatable, Sendable {
    let offset: Int
    let removeCount: Int
    let inserted: [UInt8]
  }

  let hunks: [Hunk]

  /// Edits beyond this many changed lines fall back to one replacement
  /// hunk to bound diff time on wholesale rewrites.
  static let maxLineEdits = 600

  var isEmpty: Bool { hunks.isEmpty }
  var insertedByteCount: Int { hunks.reduce(0) { $0 + $1.inserted.count } }

  /// - Complexity: O(N + M + (n+m)·D) where N/M are byte counts and
  ///   n/m/D line counts and changed lines of the differing middle.
  static func between(_ base: [UInt8], _ target: [UInt8]) -> HistoryDelta {
    let prefix = commonPrefix(base[...], target[...])
    let suffix = commonSuffix(base[prefix...], target[prefix...])
    let baseEnd = base.count - suffix
    let targetEnd = target.count - suffix
    if prefix == baseEnd, prefix == targetEnd { return HistoryDelta(hunks: []) }
    let baseSide = Side(bytes: base, lines: splitLines(base, prefix..<baseEnd), end: baseEnd)
    let targetSide = Side(bytes: target, lines: splitLines(target, prefix..<targetEnd), end: targetEnd)
    let (oldIDs, newIDs) = LineDiff.intern(
      baseSide.lines.map { base[$0] },
      targetSide.lines.map { target[$0] }
    )
    guard let matches = LineDiff.matches(oldIDs, newIDs, maxEdits: maxLineEdits) else {
      let whole = Hunk(offset: prefix, removeCount: baseEnd - prefix, inserted: Array(target[prefix..<targetEnd]))
      return HistoryDelta(hunks: [whole])
    }
    return HistoryDelta(hunks: hunks(from: matches, base: baseSide, target: targetSide))
  }

  /// - Throws: `NoteHistoryError.corrupted` when a hunk points outside
  ///   `base` (a damaged or mismatched history file).
  /// - Complexity: O(N + inserted bytes).
  func apply(to base: [UInt8]) throws -> [UInt8] {
    var output: [UInt8] = []
    output.reserveCapacity(base.count + insertedByteCount)
    var cursor = 0
    for hunk in hunks {
      guard hunk.offset >= cursor, hunk.removeCount >= 0, hunk.offset + hunk.removeCount <= base.count else {
        throw NoteHistoryError.corrupted
      }
      output.append(contentsOf: base[cursor..<hunk.offset])
      output.append(contentsOf: hunk.inserted)
      cursor = hunk.offset + hunk.removeCount
    }
    output.append(contentsOf: base[cursor...])
    return output
  }

  /// Lines added / removed between two versions, for the +/- badge in
  /// the version browser. Uses the same line diff as `between`, but
  /// before byte-level trimming, so a modified line counts as -1 +1.
  ///
  /// - Complexity: O(N + M + (n+m)·D), as `between`.
  static func lineStats(from base: [UInt8], to target: [UInt8]) -> (added: Int, removed: Int) {
    let prefix = commonPrefix(base[...], target[...])
    let lineStart = base[..<prefix].lastIndex(of: newline).map { $0 + 1 } ?? 0
    var suffix = commonSuffix(base[lineStart...], target[lineStart...])
    // Snap the shared tail to a line start so partial lines never compare.
    func startsLine(_ bytes: [UInt8], _ index: Int) -> Bool { index <= lineStart || bytes[index - 1] == newline }
    while suffix > 0, !startsLine(base, base.count - suffix) || !startsLine(target, target.count - suffix) {
      suffix -= 1
    }
    let baseLines = splitLines(base, lineStart..<(base.count - suffix))
    let targetLines = splitLines(target, lineStart..<(target.count - suffix))
    let (oldIDs, newIDs) = LineDiff.intern(baseLines.map { base[$0] }, targetLines.map { target[$0] })
    let matched = LineDiff.matches(oldIDs, newIDs, maxEdits: maxLineEdits)?.count ?? 0
    return (targetLines.count - matched, baseLines.count - matched)
  }

  /// `true` when the edit only adds or removes ASCII whitespace (the
  /// non-whitespace content of every hunk is unchanged) and the net
  /// whitespace change is at most `limit` bytes -- e.g. a stray trailing
  /// space or newline.
  func isWhitespaceOnly(base: [UInt8], limit: Int) -> Bool {
    var touched = 0
    for hunk in hunks {
      let end = min(base.count, hunk.offset + hunk.removeCount)
      let removed = base[min(hunk.offset, end)..<end]
      touched += abs(hunk.inserted.count - removed.count)
      guard touched <= limit else { return false }
      guard removed.filter({ !Self.isWhitespace($0) }) == hunk.inserted.filter({ !Self.isWhitespace($0) }) else {
        return false
      }
    }
    return true
  }

  // MARK: - Private

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
  }

  private static func commonPrefix(_ lhs: ArraySlice<UInt8>, _ rhs: ArraySlice<UInt8>) -> Int {
    var count = 0
    let limit = min(lhs.count, rhs.count)
    var left = lhs.startIndex
    var right = rhs.startIndex
    while count < limit, lhs[left] == rhs[right] {
      count += 1
      left += 1
      right += 1
    }
    return count
  }

  private static func commonSuffix(_ lhs: ArraySlice<UInt8>, _ rhs: ArraySlice<UInt8>) -> Int {
    var count = 0
    let limit = min(lhs.count, rhs.count)
    var left = lhs.endIndex
    var right = rhs.endIndex
    while count < limit, lhs[left - 1] == rhs[right - 1] {
      count += 1
      left -= 1
      right -= 1
    }
    return count
  }

  /// Splits `range` of `bytes` into line ranges that keep their
  /// trailing `\n`, using absolute indices so hunks map straight back to
  /// offsets in the full buffer.
  private static func splitLines(_ bytes: [UInt8], _ range: Range<Int>) -> [Range<Int>] {
    var lines: [Range<Int>] = []
    var start = range.lowerBound
    for index in range where bytes[index] == newline {
      lines.append(start..<(index + 1))
      start = index + 1
    }
    if start < range.upperBound { lines.append(start..<range.upperBound) }
    return lines
  }

  private struct Side {
    let bytes: [UInt8]
    let lines: [Range<Int>]
    let end: Int

    func boundary(_ line: Int) -> Int {
      line < lines.count ? lines[line].lowerBound : end
    }
  }

  private static func hunks(from matches: [LineDiff.Match], base: Side, target: Side) -> [Hunk] {
    var result: [Hunk] = []
    var oldLine = 0
    var newLine = 0
    let sentinel = LineDiff.Match(old: base.lines.count, new: target.lines.count)
    for match in matches + [sentinel] {
      if match.old > oldLine || match.new > newLine {
        let removed = base.bytes[base.boundary(oldLine)..<base.boundary(match.old)]
        let inserted = target.bytes[target.boundary(newLine)..<target.boundary(match.new)]
        result.append(trimmedHunk(removed: removed, inserted: inserted))
      }
      oldLine = match.old + 1
      newLine = match.new + 1
    }
    return result
  }

  private static func trimmedHunk(removed: ArraySlice<UInt8>, inserted: ArraySlice<UInt8>) -> Hunk {
    let prefix = commonPrefix(removed, inserted)
    let suffix = commonSuffix(removed.dropFirst(prefix), inserted.dropFirst(prefix))
    let insertedCore = inserted.dropFirst(prefix).dropLast(suffix)
    return Hunk(
      offset: removed.startIndex + prefix,
      removeCount: removed.count - prefix - suffix,
      inserted: Array(insertedCore)
    )
  }
}

private let newline: UInt8 = 0x0A
