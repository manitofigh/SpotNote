import Foundation
import Testing

@testable import Spotlight

@Suite("MathSuggester variables")
struct MathVariablesTests {
  private func suggest(_ text: String) -> String? {
    MathSuggester.suggestion(text: text, cursorOffset: (text as NSString).length)?.answer
  }

  @Test(
    "expressions use variables assigned on earlier lines",
    arguments: [
      ("rate = 42\nrate * 8", "336"),
      ("rent = 1.2k\nrent * 12", "14400"),
      ("a = 2\nb = a * 3\na + b", "8"),
      ("x = 1\nx = 5\nx * 2", "10"),
      ("tax = 8%\n150 + tax", "162"),
      ("price = 80\ntip = 15%\ntip of price", "12"),
      ("  width = 3\n\theight = 4\nwidth * height", "12"),
      ("first_value = 10\nv2 = first_value / 4\nv2 + 0", "2.5"),
      ("base = 0x10\nbase + 1", "17"),
      ("n = 10\nnotes here\n- bullet\nn ^ 2", "100"),
      ("rate = 42\r\nrate + 1", "43")
    ]
  )
  func variablesResolve(text: String, expected: String) {
    #expect(suggest(text) == expected)
  }

  @Test("an assignment line suggests its own right-hand side")
  func assignmentLineSuggests() {
    #expect(suggest("rate = 40\ntotal = rate * 2 + 1") == "81")
  }

  @Test(
    "unknown, later, or invalid variables do not resolve",
    arguments: [
      "rate * 8",
      "rate * 8\nrate = 42",
      "bad = 5 +\nbad * 2",
      "a == 5\na + 1",
      "x: 5\nx + 1",
      "of = 5\nof + 1",
      "- rate = 4\nrate + 1"
    ]
  )
  func unresolvedVariables(text: String) {
    // The last line is the one under the cursor in the first case; for
    // the rest, the cursor sits at the end of the whole text.
    #expect(suggest(text) == nil)
  }

  @Test("a variable defined below the cursor line is ignored")
  func variableBelowCursorIgnored() {
    let text = "rate * 8\nrate = 42"
    let cursor = (text as NSString).range(of: "rate * 8").upperBound
    #expect(MathSuggester.suggestion(text: text, cursorOffset: cursor) == nil)
  }

  @Test("the cursor's own line never defines a variable for itself")
  func selfReferenceRejected() {
    #expect(suggest("x = x + 1") == nil)
  }

  @Test(
    "prose mentioning a defined name does not trigger",
    arguments: ["rate = 42\nthe rate is high", "rate = 42\nrate - check later"]
  )
  func proseWithVariableNameRejected(text: String) {
    #expect(suggest(text) == nil)
  }

  @Test(
    "assignment parsing accepts identifiers and rejects everything else",
    arguments: [
      ("rate = 42", "rate", "42"),
      (" _tmp=1+1 ", "_tmp", "1+1"),
      ("v2 = v1 * 3", "v2", "v1 * 3")
    ]
  )
  func parseAssignmentAccepts(line: String, name: String, expression: String) throws {
    let parsed = try #require(MathVariables.parseAssignment(line))
    #expect(parsed.name == name)
    #expect(parsed.expression == expression)
  }

  @Test(
    "non-assignment lines are rejected by the parser",
    arguments: ["rate == 42", "2x = 4", "a b = 3", "in = 3", "to = 1", "x =", "= 5", "no equals here"]
  )
  func parseAssignmentRejects(line: String) {
    #expect(MathVariables.parseAssignment(line) == nil)
  }

  @Test("variables beyond the scan window are not collected")
  func scanWindowIsCapped() {
    let filler = Array(repeating: "filler", count: MathVariables.maxLines).joined(separator: "\n")
    let text = "far = 7\n" + filler + "\nnear = 3\n"
    let variables = MathVariables.collect(in: text as NSString, before: (text as NSString).length)
    #expect(variables["far"] == nil)
    #expect(variables["near"] == MathValue(3))
  }

  @Test("overlong lines are skipped by the scan")
  func longLinesSkipped() {
    let padding = String(repeating: " ", count: MathVariables.maxLineLength)
    let text = "long = 1" + padding + "\nshort = 2\n"
    let variables = MathVariables.collect(in: text as NSString, before: (text as NSString).length)
    #expect(variables["long"] == nil)
    #expect(variables["short"] == MathValue(2))
  }

  @Test("a large note still resolves the nearest variables")
  func largeNote() {
    let filler = Array(repeating: "some prose line - with a dash", count: 5000).joined(separator: "\n")
    let text = filler + "\nqty = 12\nqty * 2"
    #expect(suggest(text) == "24")
  }
}
