import Foundation

/// Detects an arithmetic expression at the tail of a line and computes
/// its result. Returns the formatted answer in the most "interesting"
/// base present in the expression -- hex if any operand uses `0x`,
/// binary for `0b`, octal for `0o`, decimal otherwise.
///
/// Implementation: a small shunting-yard parser (`MathExpression`) over
/// `+ - * / % ^` with parentheses and decimal/hex/binary/octal
/// literals. We avoid `NSExpression` because it can't parse
/// base-prefixed literals and has quirky handling of `%` inside format
/// strings.
enum MathSuggester {
  enum Base: Equatable {
    case decimal
    case hex
    case binary
    case octal

    var prefix: String {
      switch self {
      case .decimal: return ""
      case .hex: return "0x"
      case .binary: return "0b"
      case .octal: return "0o"
      }
    }
  }

  struct Result: Equatable {
    /// Formatted answer string, e.g. `"16"`, `"0x11"`, `"0b1011"`.
    let answer: String
    /// Length in characters of the trailing substring of the input that
    /// was consumed as the expression -- useful if the caller wants to
    /// highlight or replace it.
    let consumed: Int
  }

  /// Returns a suggestion when the line ending at `cursorOffset` (a
  /// UTF-16 code unit offset into `text`) ends with a complete
  /// arithmetic expression. The expression must contain at least one
  /// operator -- bare numbers don't trigger.
  static func suggestion(text: String, cursorOffset: Int) -> Result? {
    let nsText = text as NSString
    let safeOffset = max(0, min(cursorOffset, nsText.length))
    let prefix = nsText.substring(with: NSRange(location: 0, length: safeOffset))
    let line = lastLine(of: prefix)
    return suggestionForLine(line)
  }

  static func suggestionForLine(_ line: String) -> Result? {
    let candidate = trailingExpression(in: line)
    let trimmed = candidate.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    guard trimmed.contains(where: { MathExpression.operators.contains($0) }) else { return nil }
    if let result = tryEvaluate(trimmed) { return result }
    return retryWithShorterPrefixes(trimmed)
  }

  private static func tryEvaluate(_ expr: String) -> Result? {
    guard expr.contains(where: { MathExpression.operators.contains($0) }) else { return nil }
    let base = detectBase(in: expr)
    guard let value = MathExpression.evaluate(expr) else { return nil }
    return Result(answer: format(value, base: base), consumed: expr.count)
  }

  /// When the greedy extraction includes stray leading tokens (e.g.
  /// "9 6+12"), skip forward past each whitespace boundary and retry
  /// until a valid expression is found.
  private static func retryWithShorterPrefixes(_ expr: String) -> Result? {
    var rest = expr[...]
    while let spaceIdx = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) {
      let afterSpace = rest[spaceIdx...].drop(while: { $0 == " " || $0 == "\t" })
      guard !afterSpace.isEmpty else { break }
      rest = afterSpace
      let sub = String(rest).trimmingCharacters(in: .whitespaces)
      if let result = tryEvaluate(sub) { return result }
    }
    return nil
  }

  // MARK: - Trailing expression extraction

  private static func lastLine(of text: String) -> String {
    if let lastNewline = text.lastIndex(of: "\n") {
      return String(text[text.index(after: lastNewline)...])
    }
    return text
  }

  /// Walks back from the end of `line` collecting every character that
  /// could plausibly belong to an arithmetic expression. The returned
  /// substring is greedy and may still fail to tokenize -- that's the
  /// downstream evaluator's job to reject.
  private static func trailingExpression(in line: String) -> String {
    let allowed: Set<Character> = Set(
      "0123456789abcdefABCDEFxXbBoO+-*/%^()._ \t"
    )
    var collected: [Character] = []
    for ch in line.reversed() {
      guard allowed.contains(ch) else { break }
      collected.append(ch)
    }
    return String(collected.reversed())
  }

  // MARK: - Base detection + formatting

  private static func detectBase(in expr: String) -> Base {
    let lower = expr.lowercased()
    if lower.contains("0x") { return .hex }
    if lower.contains("0b") { return .binary }
    if lower.contains("0o") { return .octal }
    return .decimal
  }

  private static func format(_ value: Double, base: Base) -> String {
    let isInt = isIntegral(value)
    if base == .decimal {
      return isInt ? String(Int(value)) : shortDecimal(value)
    }
    guard isInt else { return shortDecimal(value) }
    let intValue = Int(value)
    let absStr = String(abs(intValue), radix: radix(for: base))
    return (intValue < 0 ? "-" : "") + base.prefix + absStr
  }

  private static func isIntegral(_ value: Double) -> Bool {
    value.rounded() == value && abs(value) < 1e15 && !value.isInfinite && !value.isNaN
  }

  private static func radix(for base: Base) -> Int {
    switch base {
    case .hex: return 16
    case .binary: return 2
    case .octal: return 8
    case .decimal: return 10
    }
  }

  private static func shortDecimal(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 6
    formatter.minimumFractionDigits = 0
    formatter.usesGroupingSeparator = false
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }
}

/// Tokenizer + shunting-yard evaluator for the supported arithmetic
/// grammar. Lives as a sibling type so neither `MathSuggester` nor this
/// parser exceeds the project's per-type body-length lint threshold.
enum MathExpression {
  static let operators: Set<Character> = ["+", "-", "*", "/", "%", "^"]

  static func evaluate(_ expr: String) -> Double? {
    guard let tokens = tokenize(expr) else { return nil }
    guard let rpn = shuntingYard(tokens) else { return nil }
    return evaluateRPN(rpn)
  }

  enum Token: Equatable {
    case number(Double)
    case op(Character)
    case lparen
    case rparen
  }

  // MARK: Tokenize

  // #lizard forgives
  static func tokenize(_ expr: String) -> [Token]? {
    var tokens: [Token] = []
    let chars = Array(expr)
    var idx = 0
    while idx < chars.count {
      let ch = chars[idx]
      if ch.isWhitespace {
        idx += 1
        continue
      }
      if let parsed = parseNumber(chars, at: idx) {
        if case .number = tokens.last { return nil }
        if case .rparen = tokens.last { return nil }
        tokens.append(.number(parsed.value))
        idx = parsed.next
        continue
      }
      if let symbol = symbolToken(ch) {
        if case .lparen = symbol {
          if case .number = tokens.last { return nil }
          if case .rparen = tokens.last { return nil }
        }
        tokens.append(symbol)
        idx += 1
        continue
      }
      return nil
    }
    return tokens.isEmpty ? nil : tokens
  }

  private static func symbolToken(_ ch: Character) -> Token? {
    if operators.contains(ch) { return .op(ch) }
    if ch == "(" { return .lparen }
    if ch == ")" { return .rparen }
    return nil
  }

  private static func parseNumber(_ chars: [Character], at start: Int) -> (value: Double, next: Int)? {
    if let parsed = parsePrefixedInt(chars, at: start) { return parsed }
    return parseDecimal(chars, at: start)
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

  // MARK: Shunting yard

  private static func precedence(_ op: Character) -> Int {
    switch op {
    case "+", "-": return 1
    case "*", "/", "%": return 2
    case "^": return 3
    default: return 0
    }
  }

  private static func isRightAssociative(_ op: Character) -> Bool { op == "^" }

  static func shuntingYard(_ tokens: [Token]) -> [Token]? {
    var output: [Token] = []
    var stack: [Token] = []
    for token in tokens where !applyToken(token, output: &output, stack: &stack) {
      return nil
    }
    while let top = stack.popLast() {
      if case .lparen = top { return nil }
      output.append(top)
    }
    return output
  }

  private static func applyToken(_ token: Token, output: inout [Token], stack: inout [Token]) -> Bool {
    switch token {
    case .number:
      output.append(token)
    case .op(let op):
      drainOperators(higherThan: op, output: &output, stack: &stack)
      stack.append(token)
    case .lparen:
      stack.append(token)
    case .rparen:
      return drainToLParen(output: &output, stack: &stack)
    }
    return true
  }

  private static func drainOperators(
    higherThan op: Character,
    output: inout [Token],
    stack: inout [Token]
  ) {
    while let top = stack.last, case .op(let topOp) = top {
      let topPrec = precedence(topOp)
      let curPrec = precedence(op)
      guard topPrec > curPrec || (topPrec == curPrec && !isRightAssociative(op)) else { return }
      output.append(stack.removeLast())
    }
  }

  private static func drainToLParen(output: inout [Token], stack: inout [Token]) -> Bool {
    while let top = stack.last {
      if case .lparen = top {
        stack.removeLast()
        return true
      }
      output.append(stack.removeLast())
    }
    return false
  }

  // MARK: RPN evaluation

  private static func evaluateRPN(_ rpn: [Token]) -> Double? {
    var stack: [Double] = []
    for token in rpn {
      switch token {
      case .number(let value):
        stack.append(value)
      case .op(let op):
        guard let rhs = stack.popLast(), let lhs = stack.popLast() else { return nil }
        guard let value = applyBinary(op, lhs, rhs) else { return nil }
        stack.append(value)
      default:
        return nil
      }
    }
    return stack.count == 1 ? stack[0] : nil
  }

  private static func applyBinary(_ op: Character, _ lhs: Double, _ rhs: Double) -> Double? {
    switch op {
    case "+": return lhs + rhs
    case "-": return lhs - rhs
    case "*": return lhs * rhs
    case "/":
      guard rhs != 0 else { return nil }
      return lhs / rhs
    case "%":
      guard rhs != 0 else { return nil }
      return lhs.truncatingRemainder(dividingBy: rhs)
    case "^": return pow(lhs, rhs)
    default: return nil
    }
  }
}
