import Foundation

/// Remembers, per Markdown folder, when the built-in library was last in
/// sync with it (last port in, or last switch back out). Re-ports only
/// carry built-in notes edited after that moment, so a note deleted from
/// the folder -- in SpotNote or on another device -- is not resurrected
/// from the frozen built-in backup.
///
/// Stored next to the built-in notes (this Mac's library) rather than in
/// the folder, because it describes this machine's built-in store: another
/// Mac enabling the same synced folder must still get a full first copy.
/// The `.plist` extension keeps it out of the JSON note loader.
struct FolderPortLedger {
  private let fileURL: URL
  private static let fileName = "folder-ports.plist"

  init(builtInDirectory: URL) {
    fileURL = builtInDirectory.appending(path: Self.fileName, directoryHint: .notDirectory)
  }

  /// Nil for a folder never synced from this library -> full copy.
  func lastSync(with folder: URL) -> Date? {
    entries()[Self.key(for: folder)]
  }

  /// Failing to record is logged, not thrown: the port itself succeeded,
  /// and the worst outcome is that a later re-port copies too much (never
  /// too little).
  func recordSync(with folder: URL, at date: Date) {
    var all = entries()
    all[Self.key(for: folder)] = date
    do {
      try PropertyListEncoder().encode(all).write(to: fileURL, options: .atomic)
    } catch {
      StorageLog.logger.error("recording folder sync failed: \(error, privacy: .public)")
    }
  }

  private func entries() -> [String: Date] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
    do {
      return try PropertyListDecoder().decode([String: Date].self, from: Data(contentsOf: fileURL))
    } catch {
      // Treated as "never synced": a full, idempotent copy is the safe side.
      StorageLog.logger.error("folder sync ledger unreadable: \(error, privacy: .public)")
      return [:]
    }
  }

  private static func key(for folder: URL) -> String {
    folder.standardizedFileURL.resolvingSymlinksInPath().path
  }
}
