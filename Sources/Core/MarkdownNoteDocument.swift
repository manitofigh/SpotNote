import Foundation

/// One note as stored in a Markdown folder:
///
/// ```
/// ---
/// id: 6F1C0A52-0E4B-4C55-9D0B-6B0C7B1E2A11
/// created: 2026-11-05T12:30:00Z
/// pinned: true
/// ---
/// First line of the note
/// ```
///
/// The front matter is deliberately minimal YAML so Obsidian & co. show it
/// as ordinary properties. `pinned` is only written when true. `updatedAt`
/// is not stored -- it comes from the file's modification date. Front
/// matter lines SpotNote does not own (tags, aliases, ...) are carried in
/// `extraFrontMatter` and written back verbatim, so editing a note in
/// SpotNote never strips another tool's metadata.
struct MarkdownNoteDocument: Equatable, Sendable {
  var id: UUID?
  var createdAt: Date?
  var isPinned = false
  var extraFrontMatter: [String] = []
  /// Internal note text (checklist glyphs decoded, LF line endings).
  var body: String

  private static let fence = "---"

  init(id: UUID?, createdAt: Date?, isPinned: Bool, extraFrontMatter: [String], body: String) {
    self.id = id
    self.createdAt = createdAt
    self.isPinned = isPinned
    self.extraFrontMatter = extraFrontMatter
    self.body = body
  }

  /// Parses a Markdown file. A file without a well-formed front matter
  /// block is treated as body-only, so arbitrary Markdown loads as-is.
  /// - Complexity: O(n) in the file length.
  init(parsing raw: String) {
    let text = MarkdownNoteCodec.normalizeNewlines(raw)
    guard let (header, body) = Self.splitFrontMatter(text) else {
      self.init(id: nil, createdAt: nil, isPinned: false, extraFrontMatter: [], body: MarkdownNoteCodec.decode(text))
      return
    }
    self.init(id: nil, createdAt: nil, isPinned: false, extraFrontMatter: [], body: MarkdownNoteCodec.decode(body))
    header.forEach { absorb(line: $0) }
  }

  func serialized() -> String {
    var lines = [Self.fence]
    if let id { lines.append("id: \(id.uuidString)") }
    if let createdAt { lines.append("created: \(createdAt.formatted(.iso8601))") }
    if isPinned { lines.append("pinned: true") }
    lines.append(contentsOf: extraFrontMatter)
    lines.append(Self.fence)
    return lines.joined(separator: "\n") + "\n" + MarkdownNoteCodec.encode(body)
  }

  // MARK: - Private

  private static func splitFrontMatter(_ text: String) -> ([String], String)? {
    guard text.hasPrefix(fence + "\n") else { return nil }
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
    var header: [String] = []
    while let line = lines.first {
      lines = lines.dropFirst()
      if line.trimmingCharacters(in: .whitespaces) == fence {
        return (header, lines.joined(separator: "\n"))
      }
      header.append(String(line))
    }
    return nil
  }

  private mutating func absorb(line: String) {
    guard let colon = line.firstIndex(of: ":") else {
      extraFrontMatter.append(line)
      return
    }
    let key = line[..<colon].trimmingCharacters(in: .whitespaces)
    let value = line[line.index(after: colon)...]
      .trimmingCharacters(in: .whitespaces)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    switch key {
    case "id" where id == nil:
      if let parsed = UUID(uuidString: value) {
        id = parsed
        return
      }
    case "created" where createdAt == nil:
      // A date in another format is not an error: it stays as foreign
      // front matter and the file's creation date is used instead.
      if let parsed = try? Date.ISO8601FormatStyle().parse(value) {
        createdAt = parsed
        return
      }
    case "pinned":
      if value == "true" || value == "false" {
        isPinned = value == "true"
        return
      }
    default:
      break
    }
    extraFrontMatter.append(line)
  }
}
