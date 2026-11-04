import Core
import Foundation
import Testing

@testable import Spotlight

@MainActor
@Suite("Open-issue fixes")
struct OpenIssueFixTests {
  private func makeStore() throws -> ChatStore {
    let dir = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-open-issues-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return try ChatStore(directory: dir, debounce: .milliseconds(20))
  }

  @Test("append-to-last-note target is the most recently edited note, not a pinned one")
  func mostRecentlyEditedSkipsPinned() async throws {
    let store = try makeStore()
    let pinned = try await store.create()
    await store.update(id: pinned.id, text: "pinned")
    try await store.togglePin(id: pinned.id)
    try await Task.sleep(for: .milliseconds(5))
    let recent = try await store.create()
    await store.update(id: recent.id, text: "recent")
    let session = ChatSession(store: store)
    await session.bootstrap()
    #expect(session.chats.first?.id == pinned.id)
    #expect(session.mostRecentlyEditedChat()?.id == recent.id)
  }

  @Test("live edits to the open note count as most recent")
  func liveEditsCountAsRecent() async throws {
    let store = try makeStore()
    let older = try await store.create()
    await store.update(id: older.id, text: "older")
    try await Task.sleep(for: .milliseconds(5))
    let newer = try await store.create()
    await store.update(id: newer.id, text: "newer")
    let session = ChatSession(store: store)
    await session.bootstrap()
    guard let olderChat = session.chats.first(where: { $0.id == older.id }) else {
      Issue.record("missing chat")
      return
    }
    session.jump(to: olderChat)
    try await Task.sleep(for: .milliseconds(5))
    session.currentText = "older, edited just now"
    session.persistIfNeeded()
    #expect(session.mostRecentlyEditedChat()?.id == older.id)
  }

  @Test("re-sending unchanged text does not bump updatedAt")
  func unchangedUpdateIsNoOp() async throws {
    let store = try makeStore()
    let chat = try await store.create()
    await store.update(id: chat.id, text: "hello")
    let before = await store.get(chat.id)?.updatedAt
    try await Task.sleep(for: .milliseconds(5))
    await store.update(id: chat.id, text: "hello")
    #expect(await store.get(chat.id)?.updatedAt == before)
  }

  @Test("legacy shifted shortcut keys are migrated to base keys")
  func legacyShortcutMigration() {
    let shifted = ShortcutStore.migrated(Shortcut(key: ">", modifiers: [.command, .shift]))
    #expect(shifted == Shortcut(key: ".", modifiers: [.command, .shift]))
    let ret = ShortcutStore.migrated(Shortcut(key: "\r", modifiers: [.command]))
    #expect(ret == Shortcut(key: "return", modifiers: [.command]))
    let plain = ShortcutStore.migrated(Shortcut(key: ">", modifiers: [.command]))
    #expect(plain == Shortcut(key: ">", modifiers: [.command]))
  }

  @Test("edit-driven re-search refreshes matches without requesting a reveal")
  func findRefreshDoesNotReveal() {
    let find = FindController()
    find.query = "ab"
    find.search(in: "ab cd")
    let reveal = find.revealRequest
    find.search(in: "xx ab cd ab", reveal: false)
    #expect(find.matches == [NSRange(location: 3, length: 2), NSRange(location: 9, length: 2)])
    #expect(find.revealRequest == reveal)
    find.next()
    #expect(find.revealRequest == reveal + 1)
  }
}
