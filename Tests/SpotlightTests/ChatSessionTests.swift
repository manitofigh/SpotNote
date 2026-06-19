import Core
import Foundation
import Testing

@testable import Spotlight

@MainActor
@Suite("ChatSession")
struct ChatSessionTests {
  @Test("committing navigation selection hides the preview list")
  func commitNavigationSelectionHidesPreview() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-session-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try ChatStore(directory: dir, debounce: .milliseconds(20))
    _ = try await store.create()
    _ = try await store.create()
    let session = ChatSession(store: store)
    await session.bootstrap()
    await session.cycleOlder()

    #expect(session.navigationPreview != nil)
    #expect(session.commitNavigationSelection())
    #expect(session.navigationPreview == nil)
    #expect(!session.commitNavigationSelection())
  }
}
