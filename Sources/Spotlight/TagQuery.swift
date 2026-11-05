import Foundation

/// A fuzzy-palette query split into `#tag` filters and free text.
///
/// - Completed tag tokens (followed by whitespace) must match a note tag
///   exactly, or be a parent of one (`#proj` matches `proj/alpha`).
/// - The final token, while the user is still typing it, is a prefix
///   match (`#wo` matches `work`).
/// - A lone `#` and tokens that are not valid tags (`#123`, `#a.b`) stay
///   in the free-text remainder, so they are fuzzy-matched as before.
struct TagQuery: Equatable, Sendable {
  let tags: [String]
  let typingPrefix: String?
  let remainder: String

  init(_ query: String) {
    let tokens = query.split(whereSeparator: \.isWhitespace)
    let endsWithSpace = query.last?.isWhitespace ?? true
    var tags: [String] = []
    var prefix: String?
    var words: [Substring] = []
    for (offset, token) in tokens.enumerated() {
      guard let name = Self.tagName(of: token) else {
        words.append(token)
        continue
      }
      let isLast = offset == tokens.count - 1
      if isLast && !endsWithSpace { prefix = name } else { tags.append(name) }
    }
    self.tags = tags
    self.typingPrefix = prefix
    self.remainder = words.joined(separator: " ")
  }

  var hasFilter: Bool { !tags.isEmpty || typingPrefix != nil }

  /// `true` when a note carrying `noteTags` satisfies every tag filter.
  /// - Complexity: O(f * t) for f filters and t note tags.
  func matches(_ noteTags: Set<String>) -> Bool {
    let completed = tags.allSatisfy { tag in
      noteTags.contains(tag) || noteTags.contains { $0.hasPrefix(tag + "/") }
    }
    guard completed else { return false }
    guard let typingPrefix else { return true }
    return noteTags.contains { $0.hasPrefix(typingPrefix) }
  }

  private static func tagName(of token: Substring) -> String? {
    guard token.first == "#" else { return nil }
    let body = token.dropFirst()
    guard TagParser.isValidBody(body.unicodeScalars) else { return nil }
    return TagParser.normalize(String(body))
  }
}
