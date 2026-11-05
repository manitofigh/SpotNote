import Foundation

/// File names for notes SpotNote writes into a Markdown folder:
/// `<sanitised first line> <first 8 hex digits of the id>.md`, e.g.
/// `Groceries for Sunday 6f1c0a52.md`. The id suffix keeps names unique
/// and marks the file as SpotNote-named, which is the only case in which
/// SpotNote ever renames a file (when the note's first line changes).
enum MarkdownFileName {
  static let fileExtension = "md"
  static let untitled = "Untitled"
  private static let maxTitleCharacters = 60
  /// APFS / HFS+ cap names at 255 UTF-8 bytes; keep the title well below
  /// that so suffixes always fit.
  private static let maxTitleBytes = 180
  /// Characters that are illegal or awkward in file names on macOS,
  /// Windows (Dropbox / git users) or as Obsidian link targets.
  private static let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]{}")
    .union(.controlCharacters)
    .union(.newlines)

  /// Sanitised title from the first non-empty line, with leading Markdown
  /// heading markers removed. Empty when the note has no usable text.
  /// - Complexity: O(n) in the length of the first non-empty line.
  static func title(from text: String) -> String {
    let firstLine =
      text
      .split(separator: "\n", omittingEmptySubsequences: true)
      .lazy
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces)) }
      .first(where: { !$0.isEmpty }) ?? ""
    let replaced = String(
      String.UnicodeScalarView(firstLine.unicodeScalars.map { forbidden.contains($0) ? " " : $0 })
    )
    var title =
      replaced
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: CharacterSet(charactersIn: ". -"))
    title = String(title.prefix(maxTitleCharacters))
    while title.utf8.count > maxTitleBytes { title.removeLast() }
    return title.trimmingCharacters(in: CharacterSet(charactersIn: ". -"))
  }

  static func shortID(_ id: UUID) -> String {
    String(id.uuidString.prefix(8)).lowercased()
  }

  /// - Parameter conflictStamp: when set, the name is marked as a conflict
  ///   copy, e.g. `Groceries (conflict 2026-11-05 1230) 1a2b3c4d.md`.
  static func make(title: String, id: UUID, conflictStamp: String? = nil) -> String {
    var base = title.isEmpty ? untitled : title
    if let conflictStamp { base += " (conflict \(conflictStamp))" }
    return "\(base) \(shortID(id)).\(fileExtension)"
  }

  /// True for names SpotNote generated for `id` (and may therefore rename).
  static func isGenerated(_ fileName: String, for id: UUID) -> Bool {
    fileName.hasSuffix(" \(shortID(id)).\(fileExtension)")
  }

  static func conflictStamp(for date: Date) -> String {
    let parts = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
    return String(
      format: "%04d-%02d-%02d %02d%02d",
      parts.year ?? 0,
      parts.month ?? 0,
      parts.day ?? 0,
      parts.hour ?? 0,
      parts.minute ?? 0
    )
  }

  /// Returns `preferred` if free, otherwise `preferred` with ` 2`, ` 3`, ...
  /// inserted before the extension. Never returns an existing file name.
  static func unique(_ preferred: String, in folder: URL) -> String {
    let stem = (preferred as NSString).deletingPathExtension
    let ext = (preferred as NSString).pathExtension
    var candidate = preferred
    var counter = 2
    while FileManager.default.fileExists(atPath: folder.appending(path: candidate).path) {
      candidate = "\(stem) \(counter).\(ext)"
      counter += 1
    }
    return candidate
  }
}
