import Foundation

/// Cheap change-detection fingerprint of a file: compared on every rescan
/// instead of re-reading contents.
struct FileStat: Equatable, Sendable {
  let modifiedAt: Date
  let size: Int
  let createdAt: Date?
}

/// Lists note files in a folder using only directory metadata. iCloud
/// files that are not downloaded yet (`.Name.md.icloud` placeholders or
/// dataless files) are never read -- a download is requested and they are
/// reported in `pending` so callers neither import junk nor mistake them
/// for deletions.
enum MarkdownFolderListing {
  struct Entry: Equatable {
    let url: URL
    let stat: FileStat

    var name: String { url.lastPathComponent }
  }

  struct Listing {
    var entries: [Entry] = []
    /// Names of matching files that exist but are still downloading.
    var pending: Set<String> = []
  }

  private static let keys: [URLResourceKey] = [
    .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .creationDateKey,
    .ubiquitousItemDownloadingStatusKey
  ]
  private static let placeholderSuffix = ".icloud"

  /// - Parameter recursive: descend into non-hidden subfolders (import);
  ///   storage folders are flat.
  /// - Throws: when the folder itself cannot be listed (missing, offline,
  ///   permission revoked). Callers must not interpret that as "empty".
  /// - Complexity: O(n) in the number of directory entries.
  static func scan(_ folder: URL, extensions: Set<String>, recursive: Bool) throws -> Listing {
    let urls =
      recursive
      ? try recursiveContents(of: folder)
      : try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
    var listing = Listing()
    for url in urls {
      classify(url, extensions: extensions, into: &listing)
    }
    return listing
  }

  // MARK: - Private

  private static func classify(_ url: URL, extensions: Set<String>, into listing: inout Listing) {
    let name = url.lastPathComponent
    if name.hasPrefix(".") {
      guard name.hasSuffix(placeholderSuffix) else { return }
      let realName = String(name.dropFirst().dropLast(placeholderSuffix.count))
      guard extensions.contains((realName as NSString).pathExtension.lowercased()) else { return }
      requestDownload(url.deletingLastPathComponent().appending(path: realName))
      listing.pending.insert(realName)
      return
    }
    guard extensions.contains(url.pathExtension.lowercased()) else { return }
    let values: URLResourceValues
    do {
      values = try url.resourceValues(forKeys: Set(keys))
    } catch {
      StorageLog.logger.error("stat \(name, privacy: .public) failed: \(error, privacy: .public)")
      return
    }
    guard values.isRegularFile == true else { return }
    if let status = values.ubiquitousItemDownloadingStatus, status != .current {
      requestDownload(url)
      listing.pending.insert(name)
      return
    }
    let stat = FileStat(
      modifiedAt: values.contentModificationDate ?? .distantPast,
      size: values.fileSize ?? 0,
      createdAt: values.creationDate
    )
    listing.entries.append(Entry(url: url, stat: stat))
  }

  private static func recursiveContents(of folder: URL) throws -> [URL] {
    // Surface "folder missing / not permitted" as a thrown error up front;
    // the enumerator would otherwise just yield nothing.
    _ = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    guard
      let enumerator = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: keys,
        options: [.skipsPackageDescendants]
      )
    else { return [] }
    var urls: [URL] = []
    for case let url as URL in enumerator {
      let isHiddenDirectory =
        url.lastPathComponent.hasPrefix(".")
        && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      if isHiddenDirectory {
        // .git, .obsidian, .trash, ... never contain user notes to import.
        enumerator.skipDescendants()
      } else {
        urls.append(url)
      }
    }
    return urls
  }

  private static func requestDownload(_ url: URL) {
    do {
      try FileManager.default.startDownloadingUbiquitousItem(at: url)
    } catch {
      // Best effort: not an iCloud item, or offline. The next scan retries.
      StorageLog.logger.debug(
        "download request for \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)"
      )
    }
  }
}
