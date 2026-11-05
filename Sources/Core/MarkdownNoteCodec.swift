import Foundation

/// Converts SpotNote's internal checklist glyphs (`☐` / `☑`) to and from
/// the GitHub-flavoured Markdown task markers other tools understand.
/// Shared by the Markdown export path and the Markdown-folder storage
/// backend so both produce identical files.
public enum MarkdownNoteCodec {
  /// Internal note text -> Markdown.
  public static func encode(_ text: String) -> String {
    text
      .replacingOccurrences(of: "☐", with: "[ ]")
      .replacingOccurrences(of: "☑", with: "[x]")
  }

  /// Markdown -> internal note text. Also normalises CRLF / CR line endings.
  public static func decode(_ markdown: String) -> String {
    normalizeNewlines(markdown)
      .replacingOccurrences(of: "[x]", with: "☑", options: .caseInsensitive)
      .replacingOccurrences(of: "[ ]", with: "☐")
  }

  /// Normalises line endings and drops a leading byte-order mark:
  /// `String(contentsOf:encoding: .utf8)` keeps it (common in files saved
  /// by Windows editors) and the note would start with an invisible U+FEFF.
  static func normalizeNewlines(_ text: String) -> String {
    var unmarked = text
    if unmarked.unicodeScalars.first == "\u{FEFF}" {
      unmarked = String(unmarked.unicodeScalars.dropFirst())
    }
    return
      unmarked
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }
}
