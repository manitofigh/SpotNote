import CryptoKit
import Foundation

/// Content fingerprint used to recognise already-imported notes without
/// keeping a second copy of every note's text around.
enum ContentDigest {
  /// SHA-256 of the text with line endings normalised and trailing
  /// whitespace removed, so a re-saved file with a final newline added
  /// still counts as the same note.
  static func of(_ text: String) -> SHA256Digest {
    SHA256.hash(data: Data(normalized(text).utf8))
  }

  static func isBlank(_ text: String) -> Bool {
    normalized(text).isEmpty
  }

  private static func normalized(_ text: String) -> String {
    var result = MarkdownNoteCodec.normalizeNewlines(text)
    while let last = result.last, last.isWhitespace { result.removeLast() }
    return result
  }
}
