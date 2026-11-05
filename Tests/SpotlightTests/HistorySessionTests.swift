import Core
import Foundation
import Testing

@testable import Spotlight

@MainActor
@Suite("Version history (UI side)")
struct HistorySessionTests {
  private func makeDirectory(_ tag: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-\(tag)-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test("deleting a note snapshots its text so the history outlives the delete")
  func deleteSnapshotsHistory() async throws {
    let store = try ChatStore(directory: makeDirectory("chats"), debounce: .milliseconds(20))
    let history = NoteHistoryStore(directory: try makeDirectory("history"))
    _ = try await store.create()
    let session = ChatSession(store: store, history: history)
    await session.bootstrap()
    let id = try #require(session.currentID)
    session.currentText = "about to be deleted"

    await session.deleteCurrent()

    let versions = await history.versions(of: id)
    let newest = try #require(versions.first)
    #expect(await history.text(of: id, version: newest) == "about to be deleted")
  }

  @Test("preview highlights only lines absent from the current note")
  func previewHighlightsChangedLines() {
    let preview = HistoryPreview.make(version: "keep\nold line\nkeep", current: "keep\nnew line")
    #expect(preview.lines.map(\.isChanged) == [false, true, true])
    #expect(!preview.isTruncated)
  }

  @Test("the browser lists versions newest first and restores the selected one")
  func controllerRestoresSelection() async throws {
    let history = NoteHistoryStore(directory: try makeDirectory("history"))
    let id = UUID()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    await history.record(id, text: "first", trigger: .destructive, now: start)
    await history.record(id, text: "second", trigger: .destructive, now: start + 1)

    let controller = HistoryController()
    var restored: String?
    controller.onRestore = { restored = $0 }
    controller.open(noteID: id, currentText: "second", history: history)
    try await waitUntil { controller.versions.count == 2 && controller.preview != nil }
    controller.moveSelection(by: 1)
    try await waitUntil { controller.preview?.lines.first?.text == "first" }
    controller.restoreSelected()

    #expect(restored == "first")
    #expect(!controller.isVisible)
  }

  /// Event-driven wait: yields until `condition` holds (bounded).
  private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<1_000 where !condition() {
      await Task.yield()
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(condition())
  }
}
