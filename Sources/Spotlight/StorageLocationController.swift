import AppKit
import Core
import os

/// Owns the user's choice of storage location: the security-scoped
/// bookmark for a Markdown folder, access to it for the app's lifetime,
/// and the fallback to built-in storage when it cannot be reached.
///
/// Lifecycle: `launchConfiguration(builtInDirectory:)` once before the
/// `ChatStore` is created, `sync(store:)` whenever the app becomes
/// active, and the Settings actions (`chooseFolder`, `switchToBuiltIn`,
/// `importFolder`) in between.
@MainActor
public final class StorageLocationController: ObservableObject {
  public struct Status: Equatable {
    public let isError: Bool
    public let message: String
  }

  /// The folder currently in use, nil while on built-in storage.
  @Published public private(set) var activeFolder: URL?
  /// Persistent warning (folder unavailable, fell back to built-in).
  @Published public private(set) var issue: String?
  /// Result of the last Settings action.
  @Published private(set) var status: Status?
  @Published private(set) var isBusy = false

  private let defaults: UserDefaults
  /// URL we called `startAccessingSecurityScopedResource` on.
  private var scopedURL: URL?
  private static let bookmarkKey = "storage.markdownFolderBookmark"
  /// Set while built-in storage received edits that the folder lacks
  /// (launch fallback or failed folder writes); cleared after re-porting.
  private static let needsResyncKey = "storage.needsResync"
  private static let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "storage")

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  private var needsResync: Bool {
    get { defaults.bool(forKey: Self.needsResyncKey) }
    set { defaults.set(newValue, forKey: Self.needsResyncKey) }
  }

  // MARK: - Launch

  /// Resolves the saved bookmark (refreshing it when stale) and starts
  /// accessing the folder. Any failure keeps the bookmark -- an external
  /// drive may simply be unplugged -- and returns built-in storage with a
  /// visible `issue`.
  public func launchConfiguration(builtInDirectory: URL) -> StorageConfiguration {
    let builtIn = StorageConfiguration(builtInDirectory: builtInDirectory)
    guard let data = defaults.data(forKey: Self.bookmarkKey) else { return builtIn }
    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      beginAccess(url)
      if isStale { saveBookmark(for: url) }
      activeFolder = url
      return StorageConfiguration(builtInDirectory: builtInDirectory, markdownFolder: url)
    } catch {
      fallBack(reason: "SpotNote couldn't find your notes folder (\(error.localizedDescription)).")
      return builtIn
    }
  }

  /// Call when `ChatStore(configuration:)` threw for the folder returned by
  /// `launchConfiguration`; the caller then opens built-in storage.
  public func reportLaunchFailure(_ error: any Error) {
    let name = activeFolder?.lastPathComponent ?? "your notes folder"
    fallBack(reason: "SpotNote couldn't open “\(name)” (\(error.localizedDescription)).")
  }

  // MARK: - Sync

  /// Flushes pending edits, picks up external changes and, after a
  /// fallback, re-ports built-in edits into the folder.
  /// - Returns: whether the library changed and the HUD should reload.
  public func sync(store: ChatStore) async -> Bool {
    await store.flush()
    if await store.takeFallbackWrites() {
      needsResync = true
      issue = "The notes folder is unavailable. New edits are saved in SpotNote's app storage for now."
    }
    guard await store.isUsingMarkdownFolder else { return false }
    do {
      var changed = try await store.rescan()
      if needsResync {
        changed = try await store.copyBuiltInNotesIntoFolder().changedFolder || changed
        needsResync = false
      }
      issue = nil
      return changed
    } catch {
      issue = "The notes folder is unavailable (\(error.localizedDescription)). Edits are kept safely."
      return false
    }
  }

  // MARK: - Settings actions

  func chooseFolder(store: ChatStore, onLibraryChanged: @escaping @MainActor () -> Void) {
    let panel = NSOpenPanel()
    panel.title = "Choose Notes Folder"
    panel.prompt = "Use Folder"
    panel.message = "SpotNote will copy your notes into this folder as Markdown files and keep them there."
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    activate(url, store: store, onLibraryChanged: onLibraryChanged)
  }

  /// True while a folder is configured but could not be opened.
  var hasUnavailableFolder: Bool {
    activeFolder == nil && defaults.data(forKey: Self.bookmarkKey) != nil
  }

  /// Tries the saved folder again after a fallback. Built-in notes
  /// (including edits made meanwhile) are ported into it.
  func retrySavedFolder(store: ChatStore, onLibraryChanged: @escaping @MainActor () -> Void) {
    guard let data = defaults.data(forKey: Self.bookmarkKey) else { return }
    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      activate(url, store: store, onLibraryChanged: onLibraryChanged)
    } catch {
      status = Status(isError: true, message: error.localizedDescription)
    }
  }

  private func activate(_ url: URL, store: ChatStore, onLibraryChanged: @escaping @MainActor () -> Void) {
    run { [weak self] in
      guard let self else { return }
      let previousScope = self.scopedURL
      self.scopedURL = nil
      self.beginAccess(url)
      do {
        let summary = try await store.useMarkdownFolder(url)
        if previousScope != url { previousScope?.stopAccessingSecurityScopedResource() }
        self.saveBookmark(for: url)
        self.needsResync = false
        self.activeFolder = url
        self.issue = nil
        self.status = Status(isError: false, message: Self.portMessage(summary, folder: url))
        onLibraryChanged()
      } catch {
        if self.scopedURL != previousScope { self.scopedURL?.stopAccessingSecurityScopedResource() }
        self.scopedURL = previousScope
        self.status = Status(isError: true, message: error.localizedDescription)
      }
    }
  }

  func switchToBuiltIn(store: ChatStore, onLibraryChanged: @escaping @MainActor () -> Void) {
    let alert = NSAlert()
    alert.messageText = "Stop using the folder?"
    alert.informativeText =
      "SpotNote will go back to saving notes in its own app storage, which still has your notes as they were "
      + "before you started using the folder (notes you deleted since then will reappear).\n\n"
      + "“Copy Notes & Switch” also brings over everything you created or edited in the folder. "
      + "“Switch Only” doesn't. Either way the folder and its files are left as they are."
    alert.addButton(withTitle: "Copy Notes & Switch")
    alert.addButton(withTitle: "Switch Only")
    alert.addButton(withTitle: "Cancel")
    let response = alert.runModal()
    guard response != .alertThirdButtonReturn else { return }
    let copy = response == .alertFirstButtonReturn
    run { [weak self] in
      guard let self else { return }
      do {
        let copied = try await store.useBuiltInStorage(copyingFolderNotes: copy)
        self.defaults.removeObject(forKey: Self.bookmarkKey)
        self.needsResync = false
        self.scopedURL?.stopAccessingSecurityScopedResource()
        self.scopedURL = nil
        self.activeFolder = nil
        self.issue = nil
        let detail = copy ? " Copied \(Self.noteCount(copied))." : ""
        self.status = Status(isError: false, message: "Now saving notes in app storage.\(detail)")
        onLibraryChanged()
      } catch {
        self.status = Status(isError: true, message: error.localizedDescription)
      }
    }
  }

  func importFolder(store: ChatStore, onLibraryChanged: @escaping @MainActor () -> Void) {
    let panel = NSOpenPanel()
    panel.title = "Import Notes from Folder"
    panel.prompt = "Import"
    panel.message = "Imports .md, .markdown and .txt files, including subfolders. The folder is not modified."
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    run { [weak self] in
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do {
        let scan = try await MarkdownFolderImporter.scan(url)
        let summary = try await store.importNewChats(scan.chats)
        var message = "Imported \(Self.noteCount(summary.inserted.count))"
        if summary.duplicates > 0 { message += ", skipped \(summary.duplicates) already in SpotNote" }
        if scan.unavailable > 0 { message += ", \(scan.unavailable) not readable yet" }
        self?.status = Status(isError: false, message: message + ".")
        if !summary.inserted.isEmpty { onLibraryChanged() }
      } catch {
        self?.status = Status(isError: true, message: error.localizedDescription)
      }
    }
  }

  func revealActiveFolder() {
    guard let activeFolder else { return }
    NSWorkspace.shared.activateFileViewerSelecting([activeFolder])
  }

  // MARK: - Private

  /// Settings actions are user-initiated and short; the task's lifetime is
  /// bounded by the store call and `isBusy` prevents overlap.
  private func run(_ work: @escaping @MainActor () async -> Void) {
    guard !isBusy else { return }
    isBusy = true
    Task { @MainActor [weak self] in
      await work()
      self?.isBusy = false
    }
  }

  private func beginAccess(_ url: URL) {
    // Returns false for URLs that need no scope (unsandboxed debug
    // builds); access then simply works without a matching stop call.
    if url.startAccessingSecurityScopedResource() { scopedURL = url }
  }

  private func saveBookmark(for url: URL) {
    do {
      let data = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      defaults.set(data, forKey: Self.bookmarkKey)
    } catch {
      // Folder mode still works this session; the next launch falls back
      // to built-in storage with a visible message.
      Self.logger.error("bookmark for \(url.path, privacy: .public) failed: \(error, privacy: .public)")
    }
  }

  private func fallBack(reason: String) {
    scopedURL?.stopAccessingSecurityScopedResource()
    scopedURL = nil
    activeFolder = nil
    needsResync = true
    issue = "\(reason) Notes are saved in SpotNote's app storage for now and copied to the folder once it's back."
  }

  private static func portMessage(_ summary: PortSummary, folder: URL) -> String {
    var message = "Now saving notes in “\(folder.lastPathComponent)”. Copied \(noteCount(summary.copied))"
    if summary.conflictCopies > 0 { message += ", \(summary.conflictCopies) as conflict copies" }
    return message + ". The originals stay in app storage, so nothing is lost if you switch back."
  }

  private static func noteCount(_ count: Int) -> String {
    count == 1 ? "1 note" : "\(count) notes"
  }
}
