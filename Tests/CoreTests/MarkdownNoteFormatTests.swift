import Foundation
import Testing

@testable import Core

@Suite("Markdown note format")
struct MarkdownNoteFormatTests {
  private let id = UUID(uuidString: "6F1C0A52-0E4B-4C55-9D0B-6B0C7B1E2A11") ?? UUID()
  private let created = Date(timeIntervalSince1970: 1_790_000_000)

  @Test("serialising and parsing round-trips id, created, pinned and text")
  func roundTrip() {
    let document = MarkdownNoteDocument(
      id: id,
      createdAt: created,
      isPinned: true,
      extraFrontMatter: [],
      body: "☐ milk\n☑ eggs\n\n---\nnot front matter"
    )
    let serialized = document.serialized()
    #expect(serialized.hasPrefix("---\nid: \(id.uuidString)\ncreated: 2026-09-21T"))
    #expect(serialized.contains("pinned: true\n---\n[ ] milk\n[x] eggs"))
    #expect(MarkdownNoteDocument(parsing: serialized) == document)
  }

  @Test("unpinned notes omit the pinned key")
  func unpinnedOmitsKey() {
    let document = MarkdownNoteDocument(id: id, createdAt: nil, isPinned: false, extraFrontMatter: [], body: "x")
    #expect(document.serialized() == "---\nid: \(id.uuidString)\n---\nx")
  }

  @Test("foreign front matter is preserved verbatim and not shown as text")
  func foreignFrontMatterPreserved() {
    let raw = "---\ntags: [work]\nid: not-a-uuid\ncreated: yesterday\naliases:\n  - foo\n---\nBody"
    let document = MarkdownNoteDocument(parsing: raw)
    #expect(document.id == nil)
    #expect(document.createdAt == nil)
    #expect(document.body == "Body")
    #expect(
      document.extraFrontMatter == ["tags: [work]", "id: not-a-uuid", "created: yesterday", "aliases:", "  - foo"]
    )
    var updated = document
    updated.id = id
    #expect(MarkdownNoteDocument(parsing: updated.serialized()).extraFrontMatter == document.extraFrontMatter)
  }

  @Test(
    "files without a complete front matter block load as plain text",
    arguments: ["# Title\nbody", "---\nunterminated: yes\nbody", "\u{FEFF}plain\r\nwindows"]
  )
  func plainMarkdown(raw: String) {
    let document = MarkdownNoteDocument(parsing: raw)
    #expect(document.id == nil)
    #expect(document.body == MarkdownNoteCodec.normalizeNewlines(raw))
  }

  @Test("quoted values and CRLF front matter are understood")
  func quotedValues() {
    let raw = "---\r\nid: \"\(id.uuidString)\"\r\npinned: 'true'\r\n---\r\nhi"
    let document = MarkdownNoteDocument(parsing: raw)
    #expect(document.id == id)
    #expect(document.isPinned)
    #expect(document.body == "hi")
  }

  @Test(
    "titles are sanitised for file names",
    arguments: [
      ("Groceries for Sunday", "Groceries for Sunday"),
      ("  ## Heading: with / slashes?  ", "Heading with slashes"),
      ("\n\n   \nsecond line wins", "second line wins"),
      ("...hidden-ish.", "hidden-ish"),
      ("[[link]] #tag ^block | pipe", "link tag block pipe"),
      ("", "")
    ]
  )
  func sanitising(input: String, expected: String) {
    #expect(MarkdownFileName.title(from: input) == expected)
  }

  @Test("titles are capped by characters and UTF-8 bytes")
  func titleLengthCap() {
    #expect(MarkdownFileName.title(from: String(repeating: "a", count: 200)).count == 60)
    #expect(MarkdownFileName.title(from: String(repeating: "😀", count: 100)).utf8.count <= 180)
  }

  @Test("generated names carry the short id and are recognised as generated")
  func generatedNames() {
    let name = MarkdownFileName.make(title: "", id: id)
    #expect(name == "Untitled 6f1c0a52.md")
    #expect(MarkdownFileName.isGenerated(name, for: id))
    #expect(!MarkdownFileName.isGenerated("Untitled.md", for: id))
    let conflict = MarkdownFileName.make(title: "Plan", id: id, conflictStamp: "2026-11-05 1230")
    #expect(conflict == "Plan (conflict 2026-11-05 1230) 6f1c0a52.md")
  }

  @Test("unique names never collide with existing files")
  func uniqueNames() throws {
    let folder = try TempFolder.make()
    try Data().write(to: folder.appending(path: "a.md"))
    try Data().write(to: folder.appending(path: "a 2.md"))
    #expect(MarkdownFileName.unique("a.md", in: folder) == "a 3.md")
    #expect(MarkdownFileName.unique("b.md", in: folder) == "b.md")
  }

  @Test("derived ids are stable per file name")
  func derivedIDs() {
    #expect(MarkdownChatFolder.derivedID(for: "a.md") == MarkdownChatFolder.derivedID(for: "a.md"))
    #expect(MarkdownChatFolder.derivedID(for: "a.md") != MarkdownChatFolder.derivedID(for: "b.md"))
  }

  @Test("content digests ignore trailing whitespace and line endings")
  func digests() {
    #expect(ContentDigest.of("a\r\nb\n\n") == ContentDigest.of("a\nb"))
    #expect(ContentDigest.of("a") != ContentDigest.of("b"))
    #expect(ContentDigest.isBlank(" \n\t"))
  }
}

enum TempFolder {
  static func make() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-folder-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
