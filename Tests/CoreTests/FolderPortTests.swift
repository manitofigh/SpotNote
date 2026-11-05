import Foundation
import Testing
// OSAllocatedUnfairLock for the test clock. swift-format orders imports
// case-sensitively, SwiftLint case-insensitively; they disagree on `os`.
// swiftlint:disable:next sorted_imports
import os

@testable import Core

/// Re-ports into a previously used folder must not resurrect notes that
/// were deleted from it, while still carrying over genuinely new edits.
@Suite("Folder port ledger")
struct FolderPortTests {
  private static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

  /// Manually advanced test clock.
  private final class TestClock: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: FolderPortTests.t0)

    func advance(seconds: TimeInterval) {
      state.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    var now: @Sendable () -> Date {
      { [state] in state.withLock { $0 } }
    }
  }

  private struct Env {
    let builtIn: URL
    let folder: URL
    let clock = TestClock()

    init() throws {
      builtIn = try TempFolder.make()
      folder = try TempFolder.make()
    }

    func builtInStore() throws -> ChatStore {
      try ChatStore(
        configuration: StorageConfiguration(builtInDirectory: builtIn),
        debounce: .milliseconds(10),
        now: clock.now
      )
    }

    func folderStore() throws -> ChatStore {
      try ChatStore(
        configuration: StorageConfiguration(builtInDirectory: builtIn, markdownFolder: folder),
        debounce: .milliseconds(10),
        now: clock.now
      )
    }

    /// Built-in library with notes "A" and "B", then ported into `folder`.
    func portedStore() async throws -> PortedLibrary {
      let store = try builtInStore()
      let noteA = try await note("A", in: store)
      let noteB = try await note("B", in: store)
      clock.advance(seconds: 60)
      _ = try await store.useMarkdownFolder(folder)
      clock.advance(seconds: 60)
      return PortedLibrary(store: store, noteA: noteA, noteB: noteB)
    }

    func note(_ text: String, in store: ChatStore) async throws -> Chat {
      let chat = try await store.create()
      await store.update(id: chat.id, text: text)
      await store.flush()
      return try #require(await store.get(chat.id))
    }

    func fileName(of id: UUID) throws -> String {
      let short = MarkdownFileName.shortID(id)
      return try #require(
        try FileManager.default.contentsOfDirectory(atPath: folder.path).first { $0.hasSuffix(" \(short).md") }
      )
    }
  }

  @Test(
    "a note deleted in folder mode stays deleted when the same folder is re-enabled",
    arguments: [false, true]
  )
  func deleteThenReenable(copyingFolderNotes: Bool) async throws {
    let env = try Env()
    let ported = try await env.portedStore()
    let store = ported.store
    let noteA = ported.noteA
    let noteB = ported.noteB
    try await store.delete(id: noteA.id)
    env.clock.advance(seconds: 60)
    try await store.useBuiltInStorage(copyingFolderNotes: copyingFolderNotes)
    #expect(await store.get(noteA.id) != nil, "the built-in backup still has it")
    env.clock.advance(seconds: 60)

    let summary = try await store.useMarkdownFolder(env.folder)

    #expect(summary.copied == 0)
    #expect(summary.conflictCopies == 0)
    #expect(await store.list().map(\.id) == [noteB.id])
  }

  @Test("a note deleted on another device stays deleted after a fallback launch and retry")
  func externalDeleteThenRetry() async throws {
    let env = try Env()
    let ported = try await env.portedStore()
    let store = ported.store
    let noteA = ported.noteA
    let noteB = ported.noteB
    try FileManager.default.removeItem(at: env.folder.appending(path: try env.fileName(of: noteA.id)))
    #expect(try await store.rescan())

    // Next launch: folder unavailable -> built-in fallback; later "Retry Folder".
    let fallback = try env.builtInStore()
    env.clock.advance(seconds: 60)
    _ = try await fallback.useMarkdownFolder(env.folder)
    #expect(await fallback.list().map(\.id) == [noteB.id])

    // Re-sync path (folder mode launch with a pending resync) as well.
    let resynced = try env.folderStore()
    #expect(try await resynced.copyBuiltInNotesIntoFolder() == PortSummary(copied: 0, skipped: 2, conflictCopies: 0))
    #expect(await resynced.list().map(\.id) == [noteB.id])
  }

  @Test("edits made during a fallback are carried into the folder on re-sync")
  func fallbackEditsCarriedOver() async throws {
    let env = try Env()
    let ported = try await env.portedStore()
    let noteA = ported.noteA

    // Launch fallback: built-in storage, the user edits A and adds C.
    let fallback = try env.builtInStore()
    await fallback.update(id: noteA.id, text: "A edited offline")
    let noteC = try await env.note("C new offline", in: fallback)
    env.clock.advance(seconds: 60)

    let folder = try env.folderStore()
    let summary = try await folder.copyBuiltInNotesIntoFolder()

    #expect(summary == PortSummary(copied: 1, skipped: 1, conflictCopies: 1))
    #expect(await folder.get(noteC.id)?.text == "C new offline")
    #expect(await folder.list().map(\.text).sorted() == ["A", "A edited offline", "B", "C new offline"])
  }

  @Test("edits that fell back mid-session are carried into the folder")
  func midSessionFallbackCarriedOver() async throws {
    let env = try Env()
    let ported = try await env.portedStore()
    let store = ported.store
    let noteA = ported.noteA
    let away = env.folder.deletingLastPathComponent().appending(path: "away-\(UUID().uuidString)")
    try FileManager.default.moveItem(at: env.folder, to: away)
    await store.update(id: noteA.id, text: "A while offline")
    await store.flush()
    #expect(await store.takeFallbackWrites())
    try FileManager.default.moveItem(at: away, to: env.folder)
    env.clock.advance(seconds: 60)

    let summary = try await store.copyBuiltInNotesIntoFolder()

    #expect(summary.conflictCopies == 0, "the folder copy has the same text already")
    #expect(summary.skipped == 2)
    #expect(
      try String(contentsOf: env.folder.appending(path: try env.fileName(of: noteA.id)), encoding: .utf8)
        .hasSuffix("A while offline")
    )
  }

  @Test("a folder chosen for the first time gets a full copy")
  func newFolderFullCopy() async throws {
    let env = try Env()
    let ported = try await env.portedStore()
    let store = ported.store
    try await store.useBuiltInStorage(copyingFolderNotes: false)
    let second = try TempFolder.make()

    let summary = try await store.useMarkdownFolder(second)

    #expect(summary.copied == 2)
    #expect(await store.list().map(\.text).sorted() == ["A", "B"])
  }

  @Test("the ledger file does not show up as a note")
  func ledgerIsNotANote() async throws {
    let env = try Env()
    _ = try await env.portedStore()
    #expect(FileManager.default.fileExists(atPath: env.builtIn.appending(path: "folder-ports.plist").path))
    #expect(await (try env.builtInStore()).list().count == 2)
  }
}

private struct PortedLibrary {
  let store: ChatStore
  let noteA: Chat
  let noteB: Chat
}
