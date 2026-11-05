import Foundation

/// Where `ChatStore` keeps its notes. The built-in directory always
/// exists (it doubles as the backup and the emergency fallback while a
/// Markdown folder is active); `markdownFolder` switches the primary
/// storage to a user-chosen folder of `.md` files.
public struct StorageConfiguration: Sendable, Equatable {
  public var builtInDirectory: URL
  public var markdownFolder: URL?

  public init(builtInDirectory: URL, markdownFolder: URL? = nil) {
    self.builtInDirectory = builtInDirectory
    self.markdownFolder = markdownFolder
  }
}

/// Disk side of `ChatStore`. Owned and mutated only by the actor, so
/// implementations are plain value types without their own locking.
protocol ChatStorageBackend {
  /// Reads every note currently on disk and resets any change tracking.
  mutating func loadAll() throws -> [UUID: Chat]

  /// Writes one note.
  /// - Parameter conflictStamp: marks the file as a conflict copy when the
  ///   backend names files after their content.
  /// - Returns: the on-disk version that was replaced, when it had been
  ///   edited by someone else since this backend last read or wrote it.
  ///   The caller must keep that version (as a conflict copy) so neither
  ///   edit is lost.
  mutating func write(_ chat: Chat, conflictStamp: String?) throws -> Chat?

  mutating func remove(id: UUID) throws

  /// Detects edits made by other processes since the last sync.
  mutating func rescan(known: [UUID: Chat]) throws -> StorageChanges
}

struct StorageChanges: Equatable {
  var upserted: [Chat] = []
  var removed: [UUID] = []

  var isEmpty: Bool { upserted.isEmpty && removed.isEmpty }
}

/// The original storage: one `<uuid>.json` per note in the app container.
/// Nothing else writes there, so it never reports external changes.
struct JSONChatDirectory: ChatStorageBackend {
  let directory: URL

  init(directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.directory = directory
  }

  func loadAll() -> [UUID: Chat] {
    let urls: [URL]
    do {
      urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    } catch {
      StorageLog.logger.error("listing \(directory.path, privacy: .public) failed: \(error, privacy: .public)")
      return [:]
    }
    let decoder = JSONDecoder()
    var result: [UUID: Chat] = [:]
    for url in urls where url.pathExtension == "json" {
      do {
        let chat = try decoder.decode(Chat.self, from: Data(contentsOf: url))
        result[chat.id] = chat
      } catch {
        StorageLog.logger.error(
          "skipping unreadable \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)"
        )
      }
    }
    return result
  }

  func write(_ chat: Chat, conflictStamp: String?) throws -> Chat? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(chat).write(to: fileURL(for: chat.id), options: .atomic)
    return nil
  }

  func remove(id: UUID) throws {
    let url = fileURL(for: id)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  func rescan(known: [UUID: Chat]) -> StorageChanges { StorageChanges() }

  private func fileURL(for id: UUID) -> URL {
    directory.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
  }
}
