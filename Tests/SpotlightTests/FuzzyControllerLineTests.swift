import Core
import Foundation
import Testing

@testable import Spotlight

@Suite("FuzzyController line handling")
struct FuzzyControllerLineTests {
  private func chat(_ text: String) -> Chat {
    Chat(createdAt: Date(), updatedAt: Date(), text: text)
  }

  /// Returns the substring each highlight range covers, using the same
  /// Character offsets the preview card applies.
  private func highlighted(_ result: FuzzyResult) -> [String] {
    let chars = Array(result.chat.text)
    return result.matchRanges.map { String(chars[$0.location..<($0.location + $0.length)]) }
  }

  @Test("title highlight is not shifted when the note starts with a carriage return")
  func leadingCarriageReturn() throws {
    let note = chat("\r\rhello world")
    let result = try #require(FuzzyController.rank(query: "hello", in: [note], limit: 5).first)
    #expect(highlighted(result) == ["hello"])
  }

  @Test("CRLF notes: snippet and preview show the matching line, not the whole note")
  func crlfLines() throws {
    let note = chat("first line\r\nsecond target line\r\nthird")
    let result = try #require(FuzzyController.rank(query: "target", in: [note], limit: 5).first)
    #expect(result.snippet == "second target line")
    #expect(highlighted(result) == ["target"])
    #expect(FuzzyController.previewLine("\r\n  title\r\nbody") == "title")
  }
}
