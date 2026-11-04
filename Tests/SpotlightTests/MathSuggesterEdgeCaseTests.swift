import Foundation
import Testing

@testable import Spotlight

@Suite("MathSuggester edge cases")
struct MathSuggesterEdgeCaseTests {
  @Test(
    "overflow and domain errors produce no suggestion instead of ∞ / NaN",
    arguments: ["2^10000", "10^400 * 10", "(0 - 8) ^ 0.5"]
  )
  func nonFiniteRejected(expr: String) {
    #expect(MathSuggester.suggestionForLine(expr) == nil)
  }

  @Test(
    "unary minus is evaluated",
    arguments: [
      ("-5 + 3", "-2"),
      ("-10 / 2 + 1", "-4"),
      ("2 * -3", "-6"),
      ("1 - -2", "3"),
      ("-(1 + 2) * 3", "-9"),
      ("-2^2", "-4"),
      ("2^-1", "0.5"),
      ("+4 - 1", "3")
    ]
  )
  func unaryMinus(expr: String, expected: String) {
    #expect(MathSuggester.suggestionForLine(expr)?.answer == expected)
  }

  @Test("a lone negative literal does not trigger a suggestion")
  func loneNegativeLiteral() {
    #expect(MathSuggester.suggestionForLine("temp -5") == nil)
    #expect(MathSuggester.suggestionForLine("-5") == nil)
  }

  @Test("a markdown bullet dash is not treated as negation")
  func bulletDash() {
    #expect(MathSuggester.suggestionForLine("- 2 + 2")?.answer == "4")
  }

  @Test("decimal answers always use '.' regardless of locale")
  func decimalSeparatorIsLocaleIndependent() {
    #expect(MathSuggester.suggestionForLine("1 / 4")?.answer == "0.25")
    #expect(MathSuggester.suggestionForLine("1 / 3")?.answer == "0.333333")
  }
}
