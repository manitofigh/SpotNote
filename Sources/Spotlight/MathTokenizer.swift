import Foundation

/// Turns an expression string into `MathExpression.Token`s.
///
/// Grammar notes:
/// - Literals: decimal (`1.5`), `0x` / `0b` / `0o` integers, and decimal
///   literals with a glued magnitude suffix: `k` = 1e3, `m` = 1e6,
///   `b` = 1e9, `t` = 1e12 (either case). The suffix must end the word,
///   so `5km` is a number followed by an identifier (rejected), not 5000m.
/// - Identifiers resolve against `variables`; unknown names fail the
///   whole tokenization, which is what keeps prose from triggering.
/// - `%` is *percent* (postfix) when followed by end of input, `)`, the
///   word `of`, or an operator; it is *modulo* when followed by an operand
///   (a number, `(`, an identifier, or a sign glued to one, as in
///   `10 % -3`).
/// - `of` is only valid right after a percentage and means multiplication.
enum MathTokenizer {
  typealias Token = MathExpression.Token

  private static let magnitudes: [Character: Double] = [
    "k": 1e3, "K": 1e3, "m": 1e6, "M": 1e6, "b": 1e9, "B": 1e9, "t": 1e12, "T": 1e12
  ]

  /// - Complexity: O(n) in the length of `expr`.
  static func tokenize(_ expr: String, variables: [String: MathValue] = [:]) -> [Token]? {
    var tokens: [Token] = []
    let chars = Array(expr)
    var idx = 0
    while idx < chars.count {
      guard let next = step(chars, at: idx, tokens: &tokens, variables: variables) else { return nil }
      idx = next
    }
    return tokens.isEmpty ? nil : tokens
  }

  static func isIdentifierStart(_ ch: Character) -> Bool {
    ch.isASCII && (ch.isLetter || ch == "_")
  }

  static func isIdentifierBody(_ ch: Character) -> Bool {
    ch.isASCII && (ch.isLetter || ch.isNumber || ch == "_")
  }

  /// Returns the index after the consumed token, or nil when the input
  /// can't be tokenized.
  private static func step(
    _ chars: [Character],
    at idx: Int,
    tokens: inout [Token],
    variables: [String: MathValue]
  ) -> Int? {
    let ch = chars[idx]
    if ch.isWhitespace { return idx + 1 }
    if let parsed = parseNumber(chars, at: idx) {
      guard expectsOperand(after: tokens.last) else { return nil }
      tokens.append(.number(MathValue(parsed.value)))
      return parsed.next
    }
    if isIdentifierStart(ch) {
      return identifier(chars, at: idx, tokens: &tokens, variables: variables)
    }
    return symbol(chars, at: idx, tokens: &tokens)
  }

  /// True when the next token must start an operand (so a sign is unary
  /// and a number / `(` is allowed).
  private static func expectsOperand(after previous: Token?) -> Bool {
    switch previous {
    case nil, .op, .lparen: return true
    case .number, .rparen, .percent: return false
    }
  }

  private static func identifier(
    _ chars: [Character],
    at start: Int,
    tokens: inout [Token],
    variables: [String: MathValue]
  ) -> Int? {
    var end = start
    while end < chars.count, isIdentifierBody(chars[end]) { end += 1 }
    let name = String(chars[start..<end])
    if name == "of" {
      guard followsPercent(tokens.last) else { return nil }
      tokens.append(.op("*"))
      return end
    }
    guard expectsOperand(after: tokens.last), let value = variables[name] else { return nil }
    tokens.append(.number(value))
    return end
  }

  /// `of` needs a percentage on its left: a literal `20%` or a variable
  /// that holds one (`tip = 15%`, then `tip of 80`).
  private static func followsPercent(_ previous: Token?) -> Bool {
    switch previous {
    case .percent: return true
    case .number(let value): return value.isPercent
    case nil, .op, .lparen, .rparen: return false
    }
  }

  private static func symbol(_ chars: [Character], at idx: Int, tokens: inout [Token]) -> Int? {
    let ch = chars[idx]
    let wantsOperand = expectsOperand(after: tokens.last)
    if ch == "%", !wantsOperand, isPercentSign(chars, at: idx) {
      tokens.append(.percent)
      return idx + 1
    }
    if ch == "-" || ch == "+", wantsOperand, idx + 1 < chars.count, !chars[idx + 1].isWhitespace {
      // Prefix sign glued to its operand. A sign followed by a space
      // ("- 2 + 2", a markdown bullet) stays binary and is rejected,
      // letting the retry path evaluate the rest of the line.
      if ch == "-" { tokens.append(.op(MathExpression.unaryMinus)) }
      return idx + 1
    }
    if MathExpression.operators.contains(ch) {
      tokens.append(.op(ch))
    } else if ch == "(" {
      guard wantsOperand else { return nil }
      tokens.append(.lparen)
    } else if ch == ")" {
      tokens.append(.rparen)
    } else {
      return nil
    }
    return idx + 1
  }

  private static func isPercentSign(_ chars: [Character], at idx: Int) -> Bool {
    var next = idx + 1
    while next < chars.count, chars[next].isWhitespace { next += 1 }
    guard next < chars.count else { return true }
    let ch = chars[next]
    if ch == ")" { return true }
    if ch == "+" || ch == "-" {
      // A sign glued to the following operand reads as a signed modulo
      // operand: `10 % -3`.
      return next + 1 >= chars.count || chars[next + 1].isWhitespace
    }
    if MathExpression.operators.contains(ch) { return true }
    let isOf = next + 1 < chars.count && ch == "o" && chars[next + 1] == "f"
    return isOf && (next + 2 >= chars.count || !isIdentifierBody(chars[next + 2]))
  }

  // MARK: Numbers

  private static func parseNumber(_ chars: [Character], at start: Int) -> (value: Double, next: Int)? {
    if let parsed = parsePrefixedInt(chars, at: start) { return parsed }
    guard let parsed = parseDecimal(chars, at: start) else { return nil }
    return applyMagnitude(parsed, chars: chars, start: start)
  }

  private static func applyMagnitude(
    _ parsed: (value: Double, next: Int),
    chars: [Character],
    start: Int
  ) -> (value: Double, next: Int) {
    let end = parsed.next
    guard end < chars.count, let multiplier = magnitudes[chars[end]] else { return parsed }
    // The suffix must end the word (`5km` is not 5k + "m"), and a bare
    // `0` keeps `0b` / `0x` typos from reading as "zero billion".
    let endsWord = end + 1 >= chars.count || !isIdentifierBody(chars[end + 1])
    let isBareZero = end - start == 1 && chars[start] == "0"
    guard endsWord, !isBareZero else { return parsed }
    return (parsed.value * multiplier, end + 1)
  }

  private static func parsePrefixedInt(_ chars: [Character], at start: Int) -> (value: Double, next: Int)? {
    guard start + 1 < chars.count, chars[start] == "0" else { return nil }
    let radix: Int
    let allowed: (Character) -> Bool
    switch chars[start + 1] {
    case "x", "X":
      radix = 16
      allowed = { $0.isHexDigit }
    case "b", "B":
      radix = 2
      allowed = { $0 == "0" || $0 == "1" }
    case "o", "O":
      radix = 8
      allowed = { ("0"..."7").contains($0) }
    default:
      return nil
    }
    var end = start + 2
    while end < chars.count, allowed(chars[end]) { end += 1 }
    guard end > start + 2 else { return nil }
    guard let value = Int(String(chars[(start + 2)..<end]), radix: radix) else { return nil }
    return (Double(value), end)
  }

  private static func parseDecimal(_ chars: [Character], at start: Int) -> (value: Double, next: Int)? {
    var end = start
    var sawDigit = false
    var sawDot = false
    while end < chars.count {
      let ch = chars[end]
      if ch.isNumber {
        sawDigit = true
        end += 1
        continue
      }
      if ch == ".", !sawDot {
        sawDot = true
        end += 1
        continue
      }
      break
    }
    guard sawDigit, let value = Double(String(chars[start..<end])) else { return nil }
    return (value, end)
  }
}
