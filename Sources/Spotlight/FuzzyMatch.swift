import Foundation

/// VSCode/Sublime-style subsequence fuzzy matcher. Each character of
/// `query` must appear in `candidate`, in order, case-insensitive. The
/// returned score rewards consecutive runs and matches landing at word
/// starts (start of string or after a non-alphanumeric byte) so
/// "spnt" -> "**Sp**ot**N**o**t**e" outranks scattered hits.
enum FuzzyMatch {
  struct Result: Equatable, Sendable {
    let score: Int
    /// UTF-8 byte offsets into the lowercased candidate where each
    /// character of the query landed. Useful for highlight overlays.
    let matches: [Int]
  }

  /// Returns `nil` when the query is not a subsequence of the
  /// candidate. An empty query is treated as a zero-score hit so the
  /// palette can render the full corpus while the user is still typing.
  static func score(query: String, in candidate: String) -> Result? {
    if query.isEmpty { return Result(score: 0, matches: []) }
    let queryBytes = Array(query.lowercased().utf8)
    let candBytes = Array(candidate.lowercased().utf8)
    var matches: [Int] = []
    matches.reserveCapacity(queryBytes.count)
    var qi = 0
    var prevMatch = -2
    var total = 0
    for ci in 0..<candBytes.count where qi < queryBytes.count && candBytes[ci] == queryBytes[qi] {
      var bonus = 1
      if prevMatch == ci - 1 { bonus += 5 }
      if ci == 0 || !Self.isWordChar(candBytes[ci - 1]) { bonus += 8 }
      total += bonus
      matches.append(ci)
      prevMatch = ci
      qi += 1
    }
    return qi == queryBytes.count ? Result(score: total, matches: matches) : nil
  }

  private static func isWordChar(_ byte: UInt8) -> Bool {
    (byte >= 0x30 && byte <= 0x39)  // 0-9
      || (byte >= 0x41 && byte <= 0x5A)  // A-Z
      || (byte >= 0x61 && byte <= 0x7A)  // a-z
  }
}
