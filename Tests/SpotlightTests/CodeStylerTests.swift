import AppKit
import Foundation
import Testing

@testable import Spotlight

@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {
  @Test("line comment beginning with // is tokenized")
  func lineCommentSlash() {
    let tokens = SyntaxHighlighter.tokens(in: "let x = 1 // trailing", language: "swift")
    #expect(tokens.contains { $0.category == .comment })
  }

  @Test("hash-style comment is tokenized")
  func hashComment() {
    let tokens = SyntaxHighlighter.tokens(in: "x = 1  # note", language: "python")
    #expect(tokens.contains { $0.category == .comment })
  }

  @Test("double-quoted strings are tokenized as strings")
  func doubleQuotedString() {
    let tokens = SyntaxHighlighter.tokens(in: "let s = \"hello world\"", language: "swift")
    #expect(tokens.contains { $0.category == .string })
  }

  @Test("integers and floats are tokenized as numbers")
  func numbers() {
    let tokens = SyntaxHighlighter.tokens(in: "let n = 42 + 3.14", language: "swift")
    let numberCount = tokens.filter { $0.category == .number }.count
    #expect(numberCount == 2)
  }

  @Test("language-specific keywords are flagged only for that language")
  func languageSpecificKeywords() {
    let swift = SyntaxHighlighter.tokens(in: "func f() {}", language: "swift")
    let python = SyntaxHighlighter.tokens(in: "func f() {}", language: "python")
    // `func` is a Swift keyword but NOT a Python one.
    #expect(swift.contains { $0.category == .keyword })
    #expect(!python.contains { $0.category == .keyword })
  }

  @Test("unknown languages fall back to a common keyword set")
  func fallbackKeywords() {
    let tokens = SyntaxHighlighter.tokens(in: "if x return", language: "unknown-lang")
    let keywords = tokens.filter { $0.category == .keyword }.count
    #expect(keywords >= 2, "both 'if' and 'return' should hit the fallback set")
  }

  @Test("identifiers not in any keyword set produce no token")
  func nonKeywordIdentifierIgnored() {
    let tokens = SyntaxHighlighter.tokens(in: "myValue other", language: nil)
    #expect(tokens.isEmpty)
  }

  @Test("splitLanguage recognizes the language on the first line")
  func splitLanguageRecognized() {
    let input = "swift\nlet x = 1\n"
    let split = SyntaxHighlighter.splitLanguage(from: input)
    #expect(split.language == "swift")
    #expect(split.code == "let x = 1\n")
  }

  @Test("splitLanguage returns nil when no tag is present")
  func splitLanguageAbsent() {
    let input = "let x = 1\n"
    let split = SyntaxHighlighter.splitLanguage(from: input)
    #expect(split.language == nil)
    #expect(split.code == input)
  }

  @Test("comment tokens extend to end of line but not past it")
  func lineCommentBounded() {
    let tokens = SyntaxHighlighter.tokens(in: "a // first\nb + 1", language: "swift")
    let comments = tokens.filter { $0.category == .comment }
    #expect(comments.count == 1)
    // The number `1` on the next line should still be tokenized.
    #expect(tokens.contains { $0.category == .number })
  }
}
