import Foundation
import Testing

@testable import Spotlight

@Suite("MathSuggester")
struct MathSuggesterTests {
  @Test("simple addition is suggested regardless of spacing")
  func additionSpacingTolerance() throws {
    let cases = ["12 + 4", "12+4", "12 +4", "12+ 4"]
    for input in cases {
      let result = try #require(MathSuggester.suggestionForLine(input))
      #expect(result.answer == "16", "input: \(input)")
    }
  }

  @Test("subtraction, multiplication, division, modulo, power")
  func everyBasicOperator() throws {
    #expect(MathSuggester.suggestionForLine("10 - 3")?.answer == "7")
    #expect(MathSuggester.suggestionForLine("4 * 2")?.answer == "8")
    #expect(MathSuggester.suggestionForLine("9 / 3")?.answer == "3")
    #expect(MathSuggester.suggestionForLine("10 % 3")?.answer == "1")
    #expect(MathSuggester.suggestionForLine("2 ^ 8")?.answer == "256")
  }

  @Test("operator precedence and parentheses are honored")
  func precedence() throws {
    #expect(MathSuggester.suggestionForLine("2 + 3 * 4")?.answer == "14")
    #expect(MathSuggester.suggestionForLine("(2 + 3) * 4")?.answer == "20")
    #expect(MathSuggester.suggestionForLine("2 * (3 + 4) - 5")?.answer == "9")
  }

  @Test("division by zero is rejected without crashing")
  func divisionByZero() {
    #expect(MathSuggester.suggestionForLine("5 / 0") == nil)
  }

  @Test("a bare number with no operator does not trigger a suggestion")
  func bareNumbersDontTrigger() {
    #expect(MathSuggester.suggestionForLine("42") == nil)
    #expect(MathSuggester.suggestionForLine("0xff") == nil)
    #expect(MathSuggester.suggestionForLine("0b1010") == nil)
  }

  @Test("non-math text does not trigger a suggestion")
  func freeTextRejected() {
    #expect(MathSuggester.suggestionForLine("hello world") == nil)
    #expect(MathSuggester.suggestionForLine("note 1 of 5") == nil)
  }

  @Test("hex operands produce a hex-formatted answer")
  func hexBase() throws {
    let result = try #require(MathSuggester.suggestionForLine("0x10 + 1"))
    #expect(result.answer == "0x11")
    #expect(MathSuggester.suggestionForLine("0xff + 0x1")?.answer == "0x100")
  }

  @Test("binary operands produce a binary-formatted answer")
  func binaryBase() throws {
    let result = try #require(MathSuggester.suggestionForLine("0b1010 + 0b1"))
    #expect(result.answer == "0b1011")
  }

  @Test("octal operands produce an octal-formatted answer")
  func octalBase() throws {
    let result = try #require(MathSuggester.suggestionForLine("0o17 + 0o1"))
    #expect(result.answer == "0o20")
  }

  @Test("trailing math at the end of free text is detected")
  func mathAtEndOfFreeText() throws {
    let result = try #require(MathSuggester.suggestionForLine("Note: 5 + 3"))
    #expect(result.answer == "8")
  }

  @Test("an incomplete trailing operator is rejected")
  func incompleteExpression() {
    #expect(MathSuggester.suggestionForLine("5 + ") == nil)
    #expect(MathSuggester.suggestionForLine("5 +") == nil)
    #expect(MathSuggester.suggestionForLine("(5 + 3") == nil)
  }

  @Test("decimal results are formatted without trailing zeros")
  func floatFormatting() throws {
    let result = try #require(MathSuggester.suggestionForLine("1 / 4"))
    #expect(result.answer == "0.25")
  }

  @Test("the suggestion is based on the line ending at the cursor offset")
  func usesLineUpToCursor() throws {
    // Cursor is at the end of "5 + 3"; the trailing "extra" should be
    // ignored because it sits past the cursor.
    let text = "5 + 3 extra"
    let cursor = (text as NSString).range(of: "5 + 3").upperBound
    let result = try #require(MathSuggester.suggestion(text: text, cursorOffset: cursor))
    #expect(result.answer == "8")
  }

  // MARK: - Regression guards

  @Test("nested parentheses evaluate correctly")
  func nestedParentheses() throws {
    let result = try #require(MathSuggester.suggestionForLine("((2 + 3) * (4 - 1))"))
    #expect(result.answer == "15")
  }

  @Test("right-associative exponentiation: 2 ^ 3 ^ 2 = 2^(3^2) = 512")
  func rightAssociativeExponent() throws {
    let result = try #require(MathSuggester.suggestionForLine("2 ^ 3 ^ 2"))
    #expect(result.answer == "512")
  }

  @Test("large hex values compute and format correctly")
  func largeHex() throws {
    let result = try #require(MathSuggester.suggestionForLine("0xFFFF + 0x1"))
    #expect(result.answer == "0x10000")
  }

  @Test("mixed-base expression uses the most interesting base for output")
  func mixedBase() throws {
    #expect(MathSuggester.suggestionForLine("0x10 + 16")?.answer == "0x20")
    #expect(MathSuggester.suggestionForLine("0b100 + 4")?.answer == "0b1000")
    #expect(MathSuggester.suggestionForLine("0o10 + 8")?.answer == "0o20")
  }

  @Test("modulo with floating-point operands returns a decimal result")
  func floatModulo() throws {
    let result = try #require(MathSuggester.suggestionForLine("7.5 % 2"))
    #expect(result.answer == "1.5")
  }

  @Test("consumed count matches the expression length, not the full line")
  func consumedCount() throws {
    let result = try #require(MathSuggester.suggestionForLine("Total: 10 + 5"))
    #expect(result.consumed == 6)
    #expect(result.answer == "15")
  }

  @Test("expression preceded by non-hex text on same line triggers correctly")
  func trailingExpressionAfterText() throws {
    let result = try #require(MathSuggester.suggestionForLine("qty: 100 * 1.08"))
    #expect(result.answer == "108")
  }

  @Test("expression preceded by hex-legal chars is found via retry")
  func hexLegalPrefixRetry() throws {
    let result = try #require(MathSuggester.suggestionForLine("price 100 * 1.08"))
    #expect(result.answer == "108")
  }

  @Test(
    "multiline text: only the cursor line's trailing expression triggers",
    arguments: [
      ("line one\n3 + 4", 14, "7"),
      ("10 + 2\nsecond line\n6 * 7", 24, "42")
    ]
  )
  func multilineCursorLine(text: String, cursor: Int, expected: String) throws {
    let result = try #require(MathSuggester.suggestion(text: text, cursorOffset: cursor))
    #expect(result.answer == expected)
  }

  @Test("cursor in the middle of a multiline file ignores later lines")
  func cursorMidFile() throws {
    let text = "1 + 1\nignored"
    let cursor = 5
    let result = try #require(MathSuggester.suggestion(text: text, cursorOffset: cursor))
    #expect(result.answer == "2")
  }

  @Test("empty or whitespace-only input produces no suggestion")
  func emptyAndWhitespace() {
    #expect(MathSuggester.suggestionForLine("") == nil)
    #expect(MathSuggester.suggestionForLine("   ") == nil)
    #expect(MathSuggester.suggestionForLine("\t") == nil)
  }

  @Test("unmatched parentheses are rejected")
  func unmatchedParens() {
    #expect(MathSuggester.suggestionForLine("(5 + 3") == nil)
    #expect(MathSuggester.suggestionForLine("5 + 3)") == nil)
    #expect(MathSuggester.suggestionForLine("((5 + 3)") == nil)
  }

  @Test("chained operations with all operators")
  func chainedOps() throws {
    let result = try #require(MathSuggester.suggestionForLine("2 + 3 * 4 - 6 / 2"))
    #expect(result.answer == "11")
  }

  @Test("negative result formats without extra signs")
  func negativeResult() throws {
    let result = try #require(MathSuggester.suggestionForLine("3 - 10"))
    #expect(result.answer == "-7")
  }

  @Test("decimal points in operands parse correctly")
  func decimalOperands() throws {
    #expect(MathSuggester.suggestionForLine("1.5 + 2.5")?.answer == "4")
    #expect(MathSuggester.suggestionForLine("0.1 + 0.2")?.answer != nil)
  }

  @Test("cursor offset of zero returns nil for a non-empty text")
  func zeroCursorOffset() {
    #expect(MathSuggester.suggestion(text: "5 + 3", cursorOffset: 0) == nil)
  }

  @Test("cursor offset beyond text length is clamped safely")
  func cursorBeyondLength() throws {
    let result = try #require(MathSuggester.suggestion(text: "2+2", cursorOffset: 999))
    #expect(result.answer == "4")
  }

  @Test(
    "adjacent numbers without an operator are rejected",
    arguments: ["1 2 3", "100 200", "9 6+"]
  )
  func adjacentNumbersRejected(expr: String) {
    #expect(MathSuggester.suggestionForLine(expr) == nil)
  }

  @Test(
    "stray leading number is skipped, valid trailing expression evaluates",
    arguments: [
      ("9 6+12", "18"),
      ("5 3 + 2", "5"),
      ("blah 99 1+2+3", "6")
    ]
  )
  func strayLeadingNumberSkipped(expr: String, expected: String) throws {
    let result = try #require(MathSuggester.suggestionForLine(expr))
    #expect(result.answer == expected)
  }

  @Test(
    "implicit multiplication via juxtaposed number-paren is rejected",
    arguments: ["2(3+1)", "(2+1)(3+1)", "5(6)"]
  )
  func implicitMultiplicationRejected(expr: String) {
    #expect(MathSuggester.suggestionForLine(expr) == nil)
  }

  @Test(
    "valid expressions still work after adjacency guards",
    arguments: [
      ("6+12", "18"),
      ("(3+1) * 2", "8"),
      ("10 - (2 + 3)", "5")
    ]
  )
  func validExpressionsStillWork(expr: String, expected: String) {
    #expect(MathSuggester.suggestionForLine(expr)?.answer == expected)
  }
}
