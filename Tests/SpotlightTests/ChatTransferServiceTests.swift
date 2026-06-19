import Core
import Foundation
import Testing

@testable import Spotlight

@MainActor
@Suite("Markdown note transfer")
struct ChatTransferServiceTests {
  @Test("checklists encode to and decode from Markdown markers")
  func checklistConversion() {
    let internalText = "☐ empty\n☑ done\nprefix ☐ embedded"
    let markdown = MarkdownNoteCodec.encode(internalText)

    #expect(markdown == "[ ] empty\n[x] done\nprefix [ ] embedded")
    #expect(MarkdownNoteCodec.decode(markdown) == internalText)
    #expect(MarkdownNoteCodec.decode("[X] uppercase") == "☑ uppercase")
  }

  @Test("writing and reading a Markdown note round trips text")
  func markdownFileRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-markdown-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let date = Date(timeIntervalSinceReferenceDate: 42)
    let chat = Chat(
      createdAt: date,
      updatedAt: date,
      text: "Tasks\n☐ first\n☑ second",
      isPinned: true
    )
    let requestedURL = directory.appending(path: "Tasks", directoryHint: .notDirectory)

    let output = try ChatTransferService.writeMarkdown(chat: chat, to: requestedURL)
    let raw = try String(contentsOf: output, encoding: .utf8)
    let imported = try ChatTransferService.readMarkdown(from: output)

    #expect(output.pathExtension == "md")
    #expect(raw == "Tasks\n[ ] first\n[x] second")
    #expect(imported.text == chat.text)
    #expect(!imported.isPinned)
  }

  @Test("suggested filenames use the first note line and md extension")
  func suggestedFileName() {
    let date = Date(timeIntervalSinceReferenceDate: 42)
    let chat = Chat(
      createdAt: date,
      updatedAt: date,
      text: "\n  Release / checklist  \nbody"
    )

    #expect(ChatTransferService.suggestedFileName(for: chat) == "Release - checklist.md")
  }
}
