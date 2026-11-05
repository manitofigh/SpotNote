import Foundation

/// Collects `name = expression` assignments from the lines above the
/// caret so later expressions can reference them (`rate = 42`, then
/// `rate * 8`). Assignments evaluate top-down, so a variable can use any
/// variable defined above it, and a later assignment overrides an earlier
/// one. Lines that don't evaluate are ignored.
///
/// Work is capped so big notes don't cause typing lag: only the nearest
/// `maxLines` lines above the caret are scanned and lines longer than
/// `maxLineLength` UTF-16 units are skipped without being copied.
enum MathVariables {
  static let maxLines = 500
  static let maxLineLength = 200
  private static let reserved: Set<String> = ["in", "to", "of"]

  /// Variables defined in `text` before `end`, which must be the start of
  /// a line (0 or just past a newline).
  /// - Complexity: O(min(n, maxLines * maxLineLength)) where n is `end`.
  static func collect(in text: NSString, before end: Int) -> [String: MathValue] {
    var variables: [String: MathValue] = [:]
    for assignment in assignments(in: text, before: end).reversed() {
      guard let tokens = MathTokenizer.tokenize(assignment.expression, variables: variables),
        let value = MathExpression.evaluate(tokens),
        value.value.isFinite
      else { continue }
      variables[assignment.name] = value
    }
    return variables
  }

  /// Assignment-looking lines, nearest first.
  private static func assignments(in text: NSString, before end: Int) -> [(name: String, expression: String)] {
    var found: [(name: String, expression: String)] = []
    var upper = min(end, text.length)
    var scanned = 0
    while upper > 0, scanned < maxLines {
      // `upper - 1` is the newline terminating the line being examined.
      let newline = text.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: upper - 1))
      let start = newline.location == NSNotFound ? 0 : newline.location + 1
      let length = upper - 1 - start
      let range = NSRange(location: start, length: length)
      if length <= maxLineLength, startsLikeAssignment(text, in: range) {
        if let assignment = parseAssignment(text.substring(with: range)) { found.append(assignment) }
      }
      upper = start
      scanned += 1
    }
    return found
  }

  /// Cheap pre-filter: the first non-blank character must be able to
  /// start an identifier.
  private static func startsLikeAssignment(_ text: NSString, in range: NSRange) -> Bool {
    var idx = range.location
    while idx < NSMaxRange(range) {
      let unit = text.character(at: idx)
      guard unit == 0x20 || unit == 0x09 else {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return MathTokenizer.isIdentifierStart(Character(scalar))
      }
      idx += 1
    }
    return false
  }

  static func parseAssignment(_ line: String) -> (name: String, expression: String)? {
    guard let equals = line.firstIndex(of: "=") else { return nil }
    let name = line[..<equals].trimmingCharacters(in: .whitespaces)
    let expression = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = name.first, MathTokenizer.isIdentifierStart(first),
      name.allSatisfy(MathTokenizer.isIdentifierBody),
      !reserved.contains(name),
      !expression.isEmpty, !expression.hasPrefix("=")
    else { return nil }
    return (name, expression)
  }
}
