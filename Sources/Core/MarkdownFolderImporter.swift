import Foundation

/// Reads notes from an arbitrary folder for a one-off import (the folder
/// is only read, never modified). Walks subfolders, skipping hidden ones
/// (`.git`, `.obsidian`, ...) and iCloud files that are not downloaded.
/// Deduplication happens in `ChatStore.importNewChats`.
public enum MarkdownFolderImporter {
  public struct Scan: Sendable {
    public var chats: [Chat] = []
    /// Files that exist but could not be read now (not UTF-8, or still
    /// downloading from iCloud).
    public var unavailable = 0
  }

  static let extensions: Set<String> = ["md", "markdown", "txt"]

  /// - Complexity: O(total size of matching files).
  public static func scan(_ folder: URL) async throws -> Scan {
    let listing = try MarkdownFolderListing.scan(folder, extensions: extensions, recursive: true)
    var scan = Scan(unavailable: listing.pending.count)
    for entry in listing.entries.sorted(by: { $0.url.path < $1.url.path }) {
      try Task.checkCancellation()
      do {
        let raw = try String(contentsOf: entry.url, encoding: .utf8)
        scan.chats.append(chat(from: raw, isMarkdown: entry.url.pathExtension.lowercased() != "txt", stat: entry.stat))
      } catch {
        StorageLog.logger.error("import skipped \(entry.name, privacy: .public): \(error, privacy: .public)")
        scan.unavailable += 1
      }
    }
    return scan
  }

  static func chat(from raw: String, isMarkdown: Bool, stat: FileStat) -> Chat {
    guard isMarkdown else {
      let text = MarkdownNoteCodec.normalizeNewlines(raw)
      return Chat(createdAt: stat.createdAt ?? stat.modifiedAt, updatedAt: stat.modifiedAt, text: text)
    }
    let document = MarkdownNoteDocument(parsing: raw)
    // Imported notes live outside the folder format, so another tool's
    // front matter (tags, aliases) is kept as part of the text instead of
    // being dropped.
    let text =
      document.extraFrontMatter.isEmpty
      ? document.body
      : (["---"] + document.extraFrontMatter + ["---", document.body]).joined(separator: "\n")
    return Chat(
      id: document.id ?? UUID(),
      createdAt: document.createdAt ?? stat.createdAt ?? stat.modifiedAt,
      updatedAt: stat.modifiedAt,
      text: text,
      isPinned: document.isPinned
    )
  }
}
