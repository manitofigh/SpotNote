import CryptoKit
import Foundation

enum MarkdownFolderError: LocalizedError, Equatable {
  case folderUnavailable(URL)

  var errorDescription: String? {
    switch self {
    case .folderUnavailable(let url):
      return "The folder “\(url.lastPathComponent)” is not available."
    }
  }
}

/// Storage backend for a user-chosen, flat folder of Markdown files (see
/// `MarkdownNoteDocument` for the format, `MarkdownFileName` for naming).
///
/// Only per-file metadata is kept in memory (name, mtime, size, title and
/// foreign front matter) -- note text lives once, in `ChatStore`. Rescans
/// list the folder and re-read only files whose mtime or size changed.
struct MarkdownChatFolder: ChatStorageBackend {
  let folder: URL
  private var records: [UUID: FileRecord] = [:]
  /// Files that failed to decode, keyed by name; retried only once their
  /// stat changes.
  private var unreadable: [String: FileStat] = [:]

  static let extensions: Set<String> = ["md", "markdown"]

  private struct FileRecord {
    var fileName: String
    var stat: FileStat
    var title: String
    var extraFrontMatter: [String]
  }

  init(folder: URL) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
    else { throw MarkdownFolderError.folderUnavailable(folder) }
    self.folder = folder
  }

  mutating func loadAll() throws -> [UUID: Chat] {
    records = [:]
    unreadable = [:]
    let changes = try rescan(known: [:])
    return Dictionary(changes.upserted.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
  }

  /// - Complexity: O(n) directory metadata plus O(size) reads of changed
  ///   or new files only.
  mutating func rescan(known: [UUID: Chat]) throws -> StorageChanges {
    let listing = try MarkdownFolderListing.scan(folder, extensions: Self.extensions, recursive: false)
    let present = listing.pending.union(listing.entries.map(\.name))
    var idByName = Dictionary(records.map { ($1.fileName, $0) }, uniquingKeysWith: { first, _ in first })
    var changes = StorageChanges()
    for entry in listing.entries.sorted(by: { $0.name < $1.name }) {
      if let id = idByName[entry.name], let record = records[id] {
        guard record.stat != entry.stat, let chat = load(entry, as: id, fallbackCreatedAt: known[id]?.createdAt)
        else { continue }
        changes.upserted.append(chat)
      } else if unreadable[entry.name] != entry.stat, let chat = adopt(entry, present: present) {
        idByName[entry.name] = chat.id
        changes.upserted.append(chat)
      }
    }
    for (id, record) in records where !present.contains(record.fileName) {
      records[id] = nil
      changes.removed.append(id)
    }
    unreadable = unreadable.filter { present.contains($0.key) }
    return changes
  }

  mutating func write(_ chat: Chat, conflictStamp: String?) throws -> Chat? {
    var record = records[chat.id]
    var displaced: Chat?
    if let current = record, let diskStat = externalChange(to: current) {
      // Edited elsewhere since we last synced: hand the disk version back
      // to the caller instead of silently overwriting it.
      if let document = read(current.fileName, stat: diskStat) {
        displaced = makeChat(document, id: chat.id, stat: diskStat, fallbackCreatedAt: chat.createdAt)
        record?.extraFrontMatter = document.extraFrontMatter
      } else {
        // Not decodable -- leave that file alone and write ours anew.
        record = nil
      }
    }
    let title = MarkdownFileName.title(from: chat.text)
    let fileName = resolveFileName(for: chat.id, record: record, title: title, conflictStamp: conflictStamp)
    let url = folder.appending(path: fileName, directoryHint: .notDirectory)
    let document = MarkdownNoteDocument(
      id: chat.id,
      createdAt: chat.createdAt,
      isPinned: chat.isPinned,
      extraFrontMatter: record?.extraFrontMatter ?? [],
      body: chat.text
    )
    try Data(document.serialized().utf8).write(to: url, options: .atomic)
    do {
      // `updatedAt` is not in the front matter; the mtime carries it, so
      // ported / restored notes keep their place in the recency order.
      try FileManager.default.setAttributes([.modificationDate: chat.updatedAt], ofItemAtPath: url.path)
    } catch {
      StorageLog.logger.error("setting mtime of \(fileName, privacy: .public) failed: \(error, privacy: .public)")
    }
    guard let stat = Self.stat(of: url) else { throw MarkdownFolderError.folderUnavailable(folder) }
    records[chat.id] = FileRecord(
      fileName: fileName,
      stat: stat,
      title: title,
      extraFrontMatter: document.extraFrontMatter
    )
    return displaced
  }

  mutating func remove(id: UUID) throws {
    guard let record = records[id] else { return }
    let url = folder.appending(path: record.fileName, directoryHint: .notDirectory)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    records[id] = nil
  }

  // MARK: - Private

  /// The file's current stat when it differs from what we last saw.
  private func externalChange(to record: FileRecord) -> FileStat? {
    guard let stat = Self.stat(of: folder.appending(path: record.fileName)), stat != record.stat else { return nil }
    return stat
  }

  private mutating func adopt(_ entry: MarkdownFolderListing.Entry, present: Set<String>) -> Chat? {
    guard let document = read(entry.name, stat: entry.stat) else { return nil }
    let id = identity(for: document.id, fileName: entry.name, present: present)
    return register(document, id: id, entry: entry, fallbackCreatedAt: nil)
  }

  private mutating func load(_ entry: MarkdownFolderListing.Entry, as id: UUID, fallbackCreatedAt: Date?) -> Chat? {
    guard let document = read(entry.name, stat: entry.stat) else { return nil }
    return register(document, id: id, entry: entry, fallbackCreatedAt: fallbackCreatedAt)
  }

  private mutating func register(
    _ document: MarkdownNoteDocument,
    id: UUID,
    entry: MarkdownFolderListing.Entry,
    fallbackCreatedAt: Date?
  ) -> Chat {
    records[id] = FileRecord(
      fileName: entry.name,
      stat: entry.stat,
      title: MarkdownFileName.title(from: document.body),
      extraFrontMatter: document.extraFrontMatter
    )
    return makeChat(document, id: id, stat: entry.stat, fallbackCreatedAt: fallbackCreatedAt)
  }

  /// Front-matter id when it is free -- or belongs to a file that just
  /// vanished, i.e. the file was renamed externally. Otherwise (no id, or a
  /// duplicated file) an id derived from the file name, so notes without
  /// front matter keep a stable identity across launches without SpotNote
  /// having to rewrite them.
  private func identity(for claimed: UUID?, fileName: String, present: Set<String>) -> UUID {
    if let claimed {
      guard let owner = records[claimed] else { return claimed }
      if !present.contains(owner.fileName) { return claimed }
    }
    let derived = Self.derivedID(for: fileName)
    return records[derived] == nil ? derived : UUID()
  }

  private func makeChat(_ document: MarkdownNoteDocument, id: UUID, stat: FileStat, fallbackCreatedAt: Date?) -> Chat {
    Chat(
      id: id,
      createdAt: document.createdAt ?? fallbackCreatedAt ?? stat.createdAt ?? stat.modifiedAt,
      updatedAt: stat.modifiedAt,
      text: document.body,
      isPinned: document.isPinned
    )
  }

  private func resolveFileName(for id: UUID, record: FileRecord?, title: String, conflictStamp: String?) -> String {
    let preferred = MarkdownFileName.make(title: title, id: id, conflictStamp: conflictStamp)
    guard let record else { return MarkdownFileName.unique(preferred, in: folder) }
    guard record.title != title, MarkdownFileName.isGenerated(record.fileName, for: id) else {
      return record.fileName
    }
    let target = MarkdownFileName.unique(preferred, in: folder)
    let source = folder.appending(path: record.fileName, directoryHint: .notDirectory)
    // Deleted externally: nothing to move, the write recreates it.
    guard FileManager.default.fileExists(atPath: source.path) else { return target }
    do {
      // Move first, then write atomically: a crash in between leaves the
      // previous content under the new name, never a lost note.
      try FileManager.default.moveItem(at: source, to: folder.appending(path: target, directoryHint: .notDirectory))
      return target
    } catch {
      StorageLog.logger.error("rename to \(target, privacy: .public) failed: \(error, privacy: .public)")
      return record.fileName
    }
  }

  private mutating func read(_ fileName: String, stat: FileStat) -> MarkdownNoteDocument? {
    do {
      let raw = try String(contentsOf: folder.appending(path: fileName), encoding: .utf8)
      unreadable[fileName] = nil
      return MarkdownNoteDocument(parsing: raw)
    } catch {
      StorageLog.logger.error("skipping unreadable \(fileName, privacy: .public): \(error, privacy: .public)")
      unreadable[fileName] = stat
      return nil
    }
  }

  static func stat(of url: URL) -> FileStat? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
      let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey])
      return FileStat(
        modifiedAt: values.contentModificationDate ?? .distantPast,
        size: values.fileSize ?? 0,
        createdAt: values.creationDate
      )
    } catch {
      StorageLog.logger.error("stat \(url.lastPathComponent, privacy: .public) failed: \(error, privacy: .public)")
      return nil
    }
  }

  /// Deterministic UUID (version-5 layout) from a file name.
  static func derivedID(for fileName: String) -> UUID {
    var bytes = Array(SHA256.hash(data: Data("spotnote-file:\(fileName)".utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    let hex = bytes.map { String(format: "%02X", $0) }.joined()
    let parts = [
      hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4), hex.dropFirst(16).prefix(4),
      hex.dropFirst(20)
    ]
    return UUID(uuidString: parts.joined(separator: "-")) ?? UUID()
  }
}
