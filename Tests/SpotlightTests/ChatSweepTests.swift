import Core
import Foundation
import Testing

@testable import Spotlight

@MainActor
@Suite("Chat sweep regressions")
struct ChatSweepTests {
  private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-sweep-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test("jumping away and back keeps the edits made before leaving")
  func jumpBackDoesNotRestoreStaleText() async throws {
    let store = try ChatStore(directory: makeTempDirectory(), debounce: .milliseconds(20))
    _ = try await store.create()
    try await Task.sleep(for: .milliseconds(5))
    _ = try await store.create()
    let session = ChatSession(store: store)
    await session.bootstrap()
    let editedID = try #require(session.currentID)
    let otherChat = try #require(session.chats.first(where: { $0.id != editedID }))

    session.currentText = "edited before leaving"
    session.persistIfNeeded()
    session.jump(to: otherChat)

    // The palette / append chord hand back the entry from `session.chats`.
    let back = try #require(session.chats.first(where: { $0.id == editedID }))
    session.jump(to: back)
    #expect(session.currentText == "edited before leaving")
  }

  @Test("export to a folder keeps notes whose titles differ only by case")
  func exportCaseInsensitiveNames() throws {
    let directory = try makeTempDirectory()
    let date = Date(timeIntervalSinceReferenceDate: 42)
    let chats = [
      Chat(createdAt: date, updatedAt: date, text: "Todo\nfirst"),
      Chat(createdAt: date, updatedAt: date, text: "todo\nsecond")
    ]

    let urls = try ChatTransferService.writeMarkdownFiles(chats: chats, to: directory)

    #expect(Set(urls.map { $0.lastPathComponent.lowercased() }).count == 2)
    let contents = try urls.map { try String(contentsOf: $0, encoding: .utf8) }
    #expect(contents == ["Todo\nfirst", "todo\nsecond"])
  }

  @Test("importing a file with a UTF-8 byte-order mark drops the mark")
  func importStripsBOM() throws {
    let url = try makeTempDirectory().appending(path: "bom.md", directoryHint: .notDirectory)
    try Data([0xEF, 0xBB, 0xBF] + Array("Title\nbody".utf8)).write(to: url)

    let chat = try ChatTransferService.readMarkdown(from: url)

    #expect(chat.text == "Title\nbody")
  }

  @Test("flush writes pending edits immediately instead of waiting out the debounce")
  func flushWritesImmediately() async throws {
    let dir = try makeTempDirectory()
    let store = try ChatStore(directory: dir, debounce: .seconds(30))
    let chat = try await store.create()
    await store.update(id: chat.id, text: "must survive quit")

    await store.flush()

    let url = dir.appending(path: "\(chat.id.uuidString).json", directoryHint: .notDirectory)
    let onDisk = try JSONDecoder().decode(Chat.self, from: Data(contentsOf: url))
    #expect(onDisk.text == "must survive quit")
  }
}
