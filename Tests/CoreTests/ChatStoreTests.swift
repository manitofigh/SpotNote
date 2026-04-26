import Foundation
import Testing

@testable import Core

@Suite("ChatStore")
struct ChatStoreTests {
  private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test("create persists a chat synchronously")
  func createPersistsImmediately() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .milliseconds(50))
    let chat = try await store.create()
    let files = try FileManager.default.contentsOfDirectory(
      at: dir,
      includingPropertiesForKeys: nil
    )
    let jsons = files.filter { $0.pathExtension == "json" }
    #expect(jsons.count == 1)
    #expect(jsons.first?.lastPathComponent == "\(chat.id.uuidString).json")
  }

  @Test("update only writes once per debounce window")
  func updateDebounces() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .milliseconds(80))
    let chat = try await store.create()
    for i in 1...20 {
      await store.update(id: chat.id, text: "draft \(i)")
    }
    try await Task.sleep(for: .milliseconds(200))
    await store.flush()
    let loaded = try loadChat(id: chat.id, from: dir)
    #expect(loaded.text == "draft 20", "last value wins after debounce")
  }

  @Test("rehydrates chats from the directory on init")
  func rehydrates() async throws {
    let dir = try makeTempDirectory()
    let firstStore = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let chat = try await firstStore.create()
    await firstStore.update(id: chat.id, text: "hello world")
    await firstStore.flush()

    let secondStore = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let loaded = await secondStore.get(chat.id)
    #expect(loaded?.text == "hello world")
  }

  @Test("list is ordered most-recently-edited first")
  func listOrder() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let older = try await store.create()
    try await Task.sleep(for: .milliseconds(10))
    let newer = try await store.create()
    try await Task.sleep(for: .milliseconds(10))
    await store.update(id: older.id, text: "bumped")
    await store.flush()

    let listing = await store.list()
    #expect(listing.count == 2)
    #expect(listing[0].id == older.id, "bumped chat becomes most recent")
    #expect(listing[1].id == newer.id)
  }

  @Test("delete removes both memory and disk entries")
  func deleteWipes() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let chat = try await store.create()
    try await store.delete(id: chat.id)
    await store.flush()

    let after = await store.get(chat.id)
    #expect(after == nil)
    let files = try FileManager.default.contentsOfDirectory(
      at: dir,
      includingPropertiesForKeys: nil
    )
    #expect(files.filter { $0.pathExtension == "json" }.isEmpty)
  }

  @Test("restore re-inserts a previously deleted chat with its original id")
  func restoreReinsertsDeletedChat() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .milliseconds(20))
    let original = try await store.create()
    await store.update(id: original.id, text: "drafted then dropped")
    await store.flush()
    let snapshot = try #require(await store.get(original.id))
    try await store.delete(id: original.id)
    #expect(await store.get(original.id) == nil)

    try await store.restore(snapshot)

    let restored = try #require(await store.get(original.id))
    #expect(restored.id == original.id, "restore preserves the original id")
    #expect(restored.text == "drafted then dropped")
    let onDisk = try loadChat(id: original.id, from: dir)
    #expect(onDisk.text == "drafted then dropped", "restore writes through to disk")
  }

  @Test("a large paste is written as one atomic blob, not many")
  func largePasteIsOneWrite() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .milliseconds(80))
    let chat = try await store.create()
    let huge = String(repeating: "x", count: 1_000_000)
    await store.update(id: chat.id, text: huge)
    try await Task.sleep(for: .milliseconds(150))
    await store.flush()
    let loaded = try loadChat(id: chat.id, from: dir)
    #expect(loaded.text.count == huge.count)
  }

  private func loadChat(id: UUID, from dir: URL) throws -> Chat {
    let url = dir.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Chat.self, from: data)
  }
}
