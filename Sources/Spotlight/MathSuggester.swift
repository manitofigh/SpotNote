import Foundation

/// Detects a calculation at the tail of a line and computes its result.
///
/// Supported, in order of precedence:
/// - Unit conversion: `5 km in mi`, `2.5 GB to MB` (see `MathConversion`).
/// - Arithmetic over `+ - * / % ^` and parentheses with decimal, `0x`,
///   `0b`, `0o`, and magnitude-suffixed (`1.5k`, `2M`) literals, percent
///   (`20% of 150`, `150 + 10%`), and variables assigned on earlier lines
///   of the same note (`rate = 42`; see `MathVariables`).
///
/// Integer answers use the most "interesting" base among the literals --
/// hex if any operand uses `0x`, then binary, then octal, else decimal.
/// See `MathFormat` for the formatting rules.
///
/// Implementation: a small shunting-yard parser (`MathTokenizer` +
/// `MathExpression`). We avoid `NSExpression` because it can't parse
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
    /// Formatted answer string, e.g. `"16"`, `"0x11"`, `"3.106856 mi"`.
    let answer: String
    /// Length in characters of the trailing substring of the input that
    /// was consumed as the expression -- useful if the caller wants to
    /// highlight or replace it.
    let consumed: Int
  }

  /// Longest line tail considered as an expression; bounds the retry
  /// loop on long prose lines.
  private static let maxExpressionLength = 200

  /// Returns a suggestion when the line ending at `cursorOffset` (a
  /// UTF-16 code unit offset into `text`) ends with a complete
  /// calculation. Arithmetic must contain at least one binary operator --
  /// bare numbers don't trigger. Variables come from assignment lines
  /// above the cursor's line.
  static func suggestion(text: String, cursorOffset: Int) -> Result? {
    let nsText = text as NSString
    let safeOffset = max(0, min(cursorOffset, nsText.length))
    let newline = nsText.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: safeOffset))
    let lineStart = newline.location == NSNotFound ? 0 : newline.location + 1
    let line = nsText.substring(with: NSRange(location: lineStart, length: safeOffset - lineStart))
    // Only pay for the scan when the line could reference a variable.
    let mayUseVariables = mayContainOperation(line) && line.contains(where: MathTokenizer.isIdentifierStart)
    let variables = mayUseVariables ? MathVariables.collect(in: nsText, before: lineStart) : [:]
    return suggestionForLine(line, variables: variables)
  }

  static func suggestionForLine(_ line: String, variables: [String: MathValue] = [:]) -> Result? {
    if let conversion = MathConversion.suggestion(for: line) { return conversion }
    let candidate = trailingExpression(in: line)
    let trimmed = candidate.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, mayContainOperation(trimmed) else { return nil }
    if let result = tryEvaluate(trimmed, variables: variables) { return result }
    return retryWithShorterPrefixes(trimmed, variables: variables)
  }

  private static func tryEvaluate(_ expr: String, variables: [String: MathValue]) -> Result? {
    guard mayContainOperation(expr) else { return nil }
    // A lone negative literal ("-5") or percentage ("10%") has no binary
    // operator and is not worth suggesting; require a real operation.
    guard let tokens = MathTokenizer.tokenize(expr, variables: variables),
      tokens.contains(where: { $0.isBinaryOperator })
    else { return nil }
    // Overflow (`2^10000`) or domain errors (`(-8)^0.5`) would otherwise
    // render as "∞" / "NaN".
    guard let value = MathExpression.evaluate(tokens), value.value.isFinite else { return nil }
    let answer =
      value.isPercent
      ? MathFormat.percent(value.value)
      : MathFormat.number(value.value, base: detectBase(in: expr))
    return Result(answer: answer, consumed: expr.count)
  }

  /// Cheap pre-filter run before tokenizing: an operation needs an
  /// operator character or the word `of` (`tip of price`).
  private static func mayContainOperation(_ text: String) -> Bool {
    text.contains(where: { MathExpression.operators.contains($0) }) || text.contains("of")
  }

  /// When the greedy extraction includes stray leading tokens (e.g.
  /// "9 6+12", "price 100 * 1.08"), skip forward past each whitespace
  /// boundary and retry until a valid expression is found.
  private static func retryWithShorterPrefixes(_ expr: String, variables: [String: MathValue]) -> Result? {
    var rest = expr[...]
    while let spaceIdx = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) {
      let afterSpace = rest[spaceIdx...].drop(while: { $0 == " " || $0 == "\t" })
      guard !afterSpace.isEmpty else { break }
      rest = afterSpace
      let sub = String(rest).trimmingCharacters(in: .whitespaces)
      if let result = tryEvaluate(sub, variables: variables) { return result }
    }
    return nil
  }

  // MARK: - Trailing expression extraction

  /// Walks back from the end of `line` collecting every character that
  /// could plausibly belong to an expression (identifiers included, for
  /// variables, suffixes, and `of`). The returned substring is greedy and
  /// may still fail to tokenize -- that's the downstream evaluator's job
  /// to reject.
  private static func trailingExpression(in line: String) -> String {
    let symbols: Set<Character> = Set("+-*/%^()._ \t")
    var collected: [Character] = []
    for ch in line.reversed() {
      guard ch.isASCII, ch.isLetter || ch.isNumber || symbols.contains(ch) else { break }
      guard collected.count < maxExpressionLength else {
        // Truncated mid-line: drop the possibly partial leading word.
        let partial = collected.lastIndex(where: { $0 == " " || $0 == "\t" }) ?? 0
        collected.removeSubrange(partial...)
        break
      }
      collected.append(ch)
    }
    return String(collected.reversed())
  }

  // MARK: - Base detection

  /// The most interesting base among `0x` / `0b` / `0o` literals. Only
  /// prefixes that start a number count, so `10b + 1` (ten billion) stays
  /// decimal.
  private static func detectBase(in expr: String) -> Base {
    let chars = Array(expr.lowercased())
    var found: Set<Character> = []
    for idx in chars.indices where chars[idx] == "0" && idx + 2 < chars.count {
      let startsNumber = idx == 0 || !(MathTokenizer.isIdentifierBody(chars[idx - 1]) || chars[idx - 1] == ".")
      if startsNumber, chars[idx + 2].isHexDigit { found.insert(chars[idx + 1]) }
    }
    if found.contains("x") { return .hex }
    if found.contains("b") { return .binary }
    if found.contains("o") { return .octal }
    return .decimal
  }
}
