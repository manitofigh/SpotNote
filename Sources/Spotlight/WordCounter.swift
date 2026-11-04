/// Counts prose-like tokens in the same whitespace-oriented way as common
/// document counters: punctuation attached to a token stays with that word.
enum WordCounter {
  /// Counts non-whitespace tokens that contain at least one letter or number.
  ///
  /// This keeps `well-being`, `don't`, `hello,world`, URLs, and numbers as
  /// single words when there is no whitespace between their characters. It
  /// also avoids treating standalone punctuation or emoji as words.
  ///
  /// - Complexity: O(n), where n is the number of characters in `text`.
  static func count(in text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).reduce(into: 0) { count, token in
      if token.contains(where: { $0.isLetter || $0.isNumber }) {
        count += 1
      }
    }
  }
}
