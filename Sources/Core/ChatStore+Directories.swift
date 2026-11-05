import Foundation

extension ChatStore {
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
}
