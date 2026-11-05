import Foundation
import Testing

@testable import Spotlight

@Suite("MathSuggester magnitude suffixes and percentages")
struct MathMagnitudePercentTests {
  // MARK: Magnitude suffixes

  @Test(
    "magnitude suffixes scale their number and answer in plain digits",
    arguments: [
      ("100k/2k", "50"),
      ("1.5m*2", "3000000"),
      ("1.5M * 2", "3000000"),
      ("2b + 1", "2000000001"),
      ("3B - 1b", "2000000000"),
      ("1t / 1b", "1000"),
      ("2T + 0", "2000000000000"),
      ("1K + 1k", "2000"),
      ("0.5k * 3", "1500"),
      ("(10k + 5k) / 3", "5000"),
      ("-2k + 500", "-1500"),
      ("1k / 3", "333.333333")
    ]
  )
  func magnitudeSuffixes(expr: String, expected: String) {
    #expect(MathSuggester.suggestionForLine(expr)?.answer == expected)
  }

  @Test(
    "a suffix glued to more letters is not a magnitude",
    arguments: ["5km + 1", "2kb * 3", "3mo + 1", "10bn - 1"]
  )
  func suffixMustEndWord(expr: String) {
    #expect(MathSuggester.suggestionForLine(expr) == nil)
  }

  @Test("a '10b' operand is ten billion, not a binary literal")
  func billionIsNotBinary() {
    #expect(MathSuggester.suggestionForLine("10b + 1")?.answer == "10000000001")
  }

  @Test("'0b' and '0x' without digits are not zero-with-suffix")
  func bareZeroPrefixRejected() {
    #expect(MathSuggester.suggestionForLine("0b + 1") == nil)
    #expect(MathSuggester.suggestionForLine("0x + 1") == nil)
  }

  @Test("hex literals still win over suffix parsing")
  func hexUnaffectedBySuffixes() {
    #expect(MathSuggester.suggestionForLine("0xb + 1")?.answer == "0xc")
    #expect(MathSuggester.suggestionForLine("0b1 + 0b1")?.answer == "0b10")
  }

  @Test(
    "prose with magnitude-looking words does not trigger",
    arguments: [
      "5k run",
      "I ran a 5k",
      "ran a 5k - it was fun",
      "costs 5k + tax",
      "plan B - 2",
      "the 1980s - 1970s",
      "Q3 - 2k",
      "call at 5pm - ok"
    ]
  )
  func suffixProseRejected(line: String) {
    #expect(MathSuggester.suggestionForLine(line) == nil)
  }

  @Test("a trailing suffixed expression after prose is still found")
  func suffixAfterProse() {
    #expect(MathSuggester.suggestionForLine("budget 5k + 2.5k")?.answer == "7500")
  }

  // MARK: Percentages

  @Test(
    "percent of, percent increase, and percent decrease",
    arguments: [
      ("20% of 150", "30"),
      ("150 + 10%", "165"),
      ("150 - 10%", "135"),
      ("150 * 10%", "15"),
      ("150 / 50%", "300"),
      ("50% of 1k", "500"),
      ("(100 + 20%) * 2", "240"),
      ("100 + 10% + 10%", "121"),
      ("12.5% of 80", "10"),
      ("200 - 7.5%", "185"),
      ("50% + 10%", "60%"),
      ("50% - 60%", "-10%"),
      ("100 + -10%", "90")
    ]
  )
  func percentages(expr: String, expected: String) {
    #expect(MathSuggester.suggestionForLine(expr)?.answer == expected)
  }

  @Test(
    "'%' followed by an operand stays modulo",
    arguments: [
      ("10 % 3", "1"),
      ("10%3", "1"),
      ("7.5 % 2", "1.5"),
      ("10 % (2 + 1)", "1"),
      ("10 % -3", "1"),
      ("17 % 5 + 1", "3"),
      ("10% 4", "2")
    ]
  )
  func moduloStillWorks(expr: String, expected: String) {
    #expect(MathSuggester.suggestionForLine(expr)?.answer == expected)
  }

  @Test(
    "a lone percentage or misplaced 'of' produces no suggestion",
    arguments: ["10%", "-10%", "20% of", "of 5", "(10)% of"]
  )
  func percentWithoutOperationRejected(expr: String) {
    #expect(MathSuggester.suggestionForLine(expr) == nil)
  }

  @Test(
    "prose with percentages does not trigger",
    arguments: ["100% sure", "I'm 100%", "50% off today", "up 10% to 5", "note 1 of 5"]
  )
  func percentProseRejected(line: String) {
    #expect(MathSuggester.suggestionForLine(line) == nil)
  }

  @Test("a trailing percent expression after prose is found")
  func percentAfterProse() {
    let result = MathSuggester.suggestionForLine("tip: 15% of 80")
    #expect(result?.answer == "12")
    #expect(result?.consumed == 9)
  }
}
