import Foundation

/// Actor-backed chat persistence. Every edit is held in memory and
/// written to disk after a small debounce window, so keystrokes (even
/// inside a large pasted chunk) never trigger a synchronous file write.
/// Large buffers still round-trip through a single atomic write per
/// window rather than a write per character.
public actor ChatStore {
  private let directory: URL
  private let debounce: Duration
  private var chats: [UUID: Chat] = [:]
  private var pendingWrites: [UUID: Task<Void, Never>] = [:]

  public init(directory: URL, debounce: Duration = .milliseconds(300)) throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    self.directory = directory
    self.debounce = debounce
    self.chats = Self.loadAll(from: directory)
  }

  /// Default on-disk location for saved chats.
  ///
  /// Sandboxed production builds store this under the app container.
  /// Unsandboxed local debug builds prefer that same container when it
  /// already exists, so debug and production inspect the same notes.
  public static func defaultDirectory() throws -> URL {
    let container = productionContainerDirectory()
    if FileManager.default.fileExists(atPath: container.path) {
      return container
    }
    return try standardDirectory()
  }

  private static func standardDirectory() throws -> URL {
    let appSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return chatsDirectory(in: appSupport)
  }

  private static func productionContainerDirectory() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return
      home
      .appending(path: "Library/Containers", directoryHint: .isDirectory)
      .appending(path: AppInfo.bundleIdentifier, directoryHint: .isDirectory)
      .appending(path: "Data/Library/Application Support", directoryHint: .isDirectory)
      .appending(path: "SpotNote", directoryHint: .isDirectory)
      .appending(path: "Chats", directoryHint: .isDirectory)
  }

  private static func chatsDirectory(in appSupport: URL) -> URL {
    appSupport
      .appending(path: "SpotNote", directoryHint: .isDirectory)
      .appending(path: "Chats", directoryHint: .isDirectory)
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
    let now = Date()
    let chat = Chat(id: UUID(), createdAt: now, updatedAt: now, text: "")
    chats[chat.id] = chat
    try persistNow(chat)
    return chat
  }

  /// Applies an edit to the in-memory chat and schedules a debounced
  /// write. Repeated calls within the debounce window collapse into one
  /// disk write at the end of the window -- this is what keeps large
  /// paste-then-edit flows cheap.
  public func update(id: UUID, text: String) {
    guard var chat = chats[id] else { return }
    chat.text = text
    chat.updatedAt = Date()
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
    let url = fileURL(for: id)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  /// Awaits every pending debounced write. Call before app termination
  /// or when the user triggers an explicit navigation that should
  /// observe current on-disk state.
  public func flush() async {
    let tasks = Array(pendingWrites.values)
    for task in tasks { await task.value }
  }

  // MARK: - Private

  /// Nonisolated so it can run during `init` before `self` is fully
  /// established on the actor.
  private static func loadAll(from directory: URL) -> [UUID: Chat] {
    let urls =
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      )) ?? []
    let decoder = JSONDecoder()
    var result: [UUID: Chat] = [:]
    for url in urls where url.pathExtension == "json" {
      guard let data = try? Data(contentsOf: url),
        let chat = try? decoder.decode(Chat.self, from: data)
      else { continue }
      result[chat.id] = chat
    }
    return result
  }

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
    try? persistNow(chat)
  }

  private func persistNow(_ chat: Chat) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(chat)
    try data.write(to: fileURL(for: chat.id), options: .atomic)
  }

  private func fileURL(for id: UUID) -> URL {
    directory.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
  }
}
