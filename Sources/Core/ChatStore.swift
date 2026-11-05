import Foundation

/// Actor-backed chat persistence. Every edit is held in memory and
/// written to disk after a small debounce window, so keystrokes (even
/// inside a large pasted chunk) never trigger a synchronous file write.
/// Large buffers still round-trip through a single atomic write per
/// window rather than a write per character.
///
/// Disk I/O is delegated to a `ChatStorageBackend`: the built-in JSON
/// directory, or a user-chosen Markdown folder (see `StorageConfiguration`
/// and the storage-location extension at the end of this file).
public actor ChatStore {
  private var configuration: StorageConfiguration
  private let debounce: Duration
  private let now: @Sendable () -> Date
  private var backend: any ChatStorageBackend
  private var chats: [UUID: Chat] = [:]
  private var pendingWrites: [UUID: Task<Void, Never>] = [:]
  /// Set when a Markdown-folder write failed and the note was saved to the
  /// built-in directory instead (see `persistNow`).
  private var hasFallbackWrites = false

  /// - Parameter now: clock for `createdAt` / `updatedAt` and conflict
  ///   names; injectable for tests.
  /// - Throws: `MarkdownFolderError.folderUnavailable` (or the listing
  ///   error) when `configuration.markdownFolder` cannot be read. Callers
  ///   fall back to the built-in directory.
  public init(
    configuration: StorageConfiguration,
    debounce: Duration = .milliseconds(300),
    now: @escaping @Sendable () -> Date = { Date() }
  ) throws {
    var backend = try Self.makeBackend(for: configuration)
    self.chats = try backend.loadAll()
    self.backend = backend
    self.configuration = configuration
    self.debounce = debounce
    self.now = now
  }

  /// Built-in storage only. Not a delegating init: lizard misparses
  /// `self.init(...)` as a 200-line function.
  public init(directory: URL, debounce: Duration = .milliseconds(300)) throws {
    let configuration = StorageConfiguration(builtInDirectory: directory)
    var backend = try Self.makeBackend(for: configuration)
    self.chats = try backend.loadAll()
    self.backend = backend
    self.configuration = configuration
    self.debounce = debounce
    self.now = { Date() }
  }

  /// All chats -- pinned first, then unpinned, each group sorted by
  /// most-recently-edited.
  public func list() -> [Chat] {
    chats.values.sorted { lhs, rhs in
      if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
      return lhs.updatedAt > rhs.updatedAt
    }
  }

  public func get(_ id: UUID) -> Chat? { chats[id] }

  /// Creates a new empty chat and writes it synchronously so it exists
  /// on disk before the caller takes further action (e.g. switching the
  /// UI to it).
  public func create() throws -> Chat {
    let date = now()
    let chat = Chat(id: UUID(), createdAt: date, updatedAt: date, text: "")
    // Persist before inserting so a failed write doesn't leave a ghost
    // chat that is listed in memory but vanishes on next launch.
    try persistNow(chat)
    chats[chat.id] = chat
    return chat
  }

  /// Applies an edit to the in-memory chat and schedules a debounced
  /// write. Repeated calls within the debounce window collapse into one
  /// disk write at the end of the window -- this is what keeps large
  /// paste-then-edit flows cheap.
  public func update(id: UUID, text: String) {
    // Unchanged text is a no-op, so callers can safely re-send the live
    // editor contents (e.g. on quit) without bumping `updatedAt` and
    // reshuffling the note order.
    guard var chat = chats[id], chat.text != text else { return }
    chat.text = text
    chat.updatedAt = now()
    chats[id] = chat
    scheduleWrite(id: id)
  }

  /// Re-inserts a chat that was previously removed via `delete`. Used by
  /// the session-level undo path, so the original `id`, `createdAt`, and
  /// last-edited text are preserved on restore.
  public func restore(_ chat: Chat) throws {
    chats[chat.id] = chat
    try persistNow(chat)
  }

  /// Imports chats from external files. Existing chats are never
  /// overwritten; an incoming duplicate id is assigned a fresh id while
  /// preserving text, timestamps, and pin state.
  @discardableResult
  public func importChats(_ imported: [Chat]) throws -> [Chat] {
    var inserted: [Chat] = []
    for chat in imported {
      let resolved = uniqueImportedChat(from: chat)
      try persistNow(resolved)
      chats[resolved.id] = resolved
      inserted.append(resolved)
    }
    return inserted
  }

  public func togglePin(id: UUID) throws {
    guard var chat = chats[id] else { return }
    chat.isPinned.toggle()
    chats[id] = chat
    try persistNow(chat)
  }

  public func delete(id: UUID) throws {
    pendingWrites[id]?.cancel()
    pendingWrites[id] = nil
    chats[id] = nil
    try backend.remove(id: id)
  }

  /// Awaits every pending debounced write. Call before app termination
  /// or when the user triggers an explicit navigation that should
  /// observe current on-disk state.
  ///
  /// Pending writes are performed immediately rather than waiting out
  /// the remaining debounce window, and without suspending, so an edit
  /// arriving mid-flush can't slip past it and quitting stays fast.
  public func flush() async {
    let ids = Array(pendingWrites.keys)
    for id in ids {
      pendingWrites[id]?.cancel()
      pendingWrites[id] = nil
      guard let chat = chats[id] else { continue }
      persistLogged(chat)
    }
  }

  // MARK: - Private

  private func scheduleWrite(id: UUID) {
    pendingWrites[id]?.cancel()
    let window = debounce
    pendingWrites[id] = Task { [weak self] in
      do { try await Task.sleep(for: window) } catch { return }
      await self?.performDebouncedWrite(id: id)
    }
  }

  private func performDebouncedWrite(id: UUID) {
    pendingWrites[id] = nil
    guard let chat = chats[id] else { return }
    persistLogged(chat)
  }

  /// Debounced / flushed writes have no caller to report to; the edit
  /// stays in memory and is retried by the next edit or flush.
  private func persistLogged(_ chat: Chat) {
    do {
      try persistNow(chat)
    } catch {
      StorageLog.logger.error("saving note \(chat.id, privacy: .public) failed: \(error, privacy: .public)")
    }
  }

  /// Single funnel for every write. In Markdown-folder mode an external
  /// edit displaced by this write is kept as a conflict copy, and a failed
  /// write (folder went offline mid-session) falls back to the built-in
  /// directory so the edit is never lost.
  private func persistNow(_ chat: Chat) throws {
    do {
      if let displaced = try backend.write(chat, conflictStamp: nil), displaced.text != chat.text {
        try saveConflictCopy(of: displaced)
      }
    } catch  where configuration.markdownFolder != nil {
      StorageLog.logger.error("folder write failed, saving to built-in storage: \(error, privacy: .public)")
      _ = try JSONChatDirectory(directory: configuration.builtInDirectory).write(chat, conflictStamp: nil)
      hasFallbackWrites = true
    }
  }

  /// Keeps `version` as a separate, clearly named note so neither side of
  /// a conflicting edit is lost.
  private func saveConflictCopy(of version: Chat) throws {
    let date = now()
    let copy = Chat(createdAt: version.createdAt, updatedAt: date, text: version.text)
    _ = try backend.write(copy, conflictStamp: MarkdownFileName.conflictStamp(for: date))
    chats[copy.id] = copy
  }

  private func uniqueImportedChat(from chat: Chat) -> Chat {
    guard chats[chat.id] != nil else { return chat }
    return Chat(
      id: UUID(),
      createdAt: chat.createdAt,
      updatedAt: chat.updatedAt,
      text: chat.text,
      isPinned: chat.isPinned
    )
  }
}

// MARK: - Storage location

extension ChatStore {
  public var isUsingMarkdownFolder: Bool { configuration.markdownFolder != nil }

  /// Makes `folder` the primary storage. The notes currently in the
  /// library are COPIED into it (see `PortSummary`); the built-in JSON
  /// directory is never modified, so it remains a backup. Re-enabling the
  /// same folder is idempotent: notes already there (by id) are skipped.
  public func useMarkdownFolder(_ folder: URL) async throws -> PortSummary {
    await flush()
    let source = Array(chats.values)
    var markdown = try MarkdownChatFolder(folder: folder)
    let folderChats = try markdown.loadAll()
    let previous = (backend, chats, configuration)
    backend = markdown
    chats = folderChats
    configuration.markdownFolder = folder
    do {
      return try port(source)
    } catch {
      (backend, chats, configuration) = previous
      throw error
    }
  }

  /// Returns to the built-in JSON directory. With `copyingFolderNotes`,
  /// notes from the folder that are new, or newer than their built-in
  /// copy, are written into the built-in directory first. The folder
  /// itself is left untouched either way.
  /// - Returns: the number of notes copied.
  @discardableResult
  public func useBuiltInStorage(copyingFolderNotes: Bool) async throws -> Int {
    await flush()
    guard isUsingMarkdownFolder else { return 0 }
    let json = try JSONChatDirectory(directory: configuration.builtInDirectory)
    var builtIn = json.loadAll()
    var copied = 0
    if copyingFolderNotes {
      for chat in chats.values {
        if let existing = builtIn[chat.id], existing.text == chat.text || existing.updatedAt >= chat.updatedAt {
          continue
        }
        _ = try json.write(chat, conflictStamp: nil)
        builtIn[chat.id] = chat
        copied += 1
      }
    }
    backend = json
    chats = builtIn
    configuration.markdownFolder = nil
    return copied
  }

  /// Re-runs the port from the built-in directory into the active folder.
  /// Used after a session that had to fall back to built-in storage, so
  /// edits made meanwhile reach the folder (as conflict copies when the
  /// folder's version also changed).
  public func copyBuiltInNotesIntoFolder() throws -> PortSummary {
    guard isUsingMarkdownFolder else { return PortSummary() }
    let source = try JSONChatDirectory(directory: configuration.builtInDirectory).loadAll()
    return try port(Array(source.values))
  }

  /// True once (then reset) if any write had to fall back to the built-in
  /// directory because the folder was unavailable.
  public func takeFallbackWrites() -> Bool {
    defer { hasFallbackWrites = false }
    return hasFallbackWrites
  }

  /// Picks up files added, edited, renamed or deleted by other processes.
  /// Only files whose mtime or size changed are re-read. A note with an
  /// unsaved local edit keeps that edit; the external version becomes a
  /// conflict copy. A note deleted externally while it has an unsaved edit
  /// is re-created by the pending write.
  /// - Returns: whether the library changed.
  /// - Throws: when the folder cannot be listed; nothing is removed then.
  public func rescan() throws -> Bool {
    let changes = try backend.rescan(known: chats)
    guard !changes.isEmpty else { return false }
    for disk in changes.upserted {
      guard pendingWrites[disk.id] != nil, let local = chats[disk.id] else {
        chats[disk.id] = disk
        continue
      }
      if local.text != disk.text { try saveConflictCopy(of: disk) }
    }
    for id in changes.removed where pendingWrites[id] == nil {
      chats[id] = nil
    }
    return true
  }

  /// Imports notes, skipping any whose text (ignoring trailing whitespace
  /// and line-ending style) already exists in the library or earlier in
  /// `incoming`. Importing the same folder twice therefore adds nothing
  /// the second time; a file edited in between imports as a new note.
  /// - Complexity: O(total text size) for hashing.
  public func importNewChats(_ incoming: [Chat]) throws -> ImportSummary {
    var seen = Set(chats.values.map { ContentDigest.of($0.text) })
    var summary = ImportSummary()
    for chat in incoming {
      let digest = ContentDigest.of(chat.text)
      guard !ContentDigest.isBlank(chat.text), seen.insert(digest).inserted else {
        summary.duplicates += 1
        continue
      }
      let resolved = uniqueImportedChat(from: chat)
      try persistNow(resolved)
      chats[resolved.id] = resolved
      summary.inserted.append(resolved)
    }
    return summary
  }

  private static func makeBackend(for configuration: StorageConfiguration) throws -> any ChatStorageBackend {
    if let folder = configuration.markdownFolder {
      return try MarkdownChatFolder(folder: folder)
    }
    return try JSONChatDirectory(directory: configuration.builtInDirectory)
  }

  /// Copy rule: new id -> copy; same id and same text, or the folder's
  /// version is at least as new -> skip; otherwise -> conflict copy.
  /// Never overwrites a file in the folder.
  private func port(_ source: [Chat]) throws -> PortSummary {
    var summary = PortSummary()
    for chat in source.sorted(by: { $0.createdAt < $1.createdAt }) {
      guard let existing = chats[chat.id] else {
        _ = try backend.write(chat, conflictStamp: nil)
        chats[chat.id] = chat
        summary.copied += 1
        continue
      }
      if existing.text == chat.text || chat.updatedAt <= existing.updatedAt {
        summary.skipped += 1
      } else {
        try saveConflictCopy(of: chat)
        summary.conflictCopies += 1
      }
    }
    return summary
  }
}
