import Foundation

/// One rendered Markdown construct. `content` is the visible text that
/// receives the style; `markers` are the syntax characters (`**`, `# `,
/// `[`, `](url)`, ...) that the live preview hides while the line is not
/// being edited. Ranges are UTF-16 offsets into the parsed `NSString`.
struct MarkdownSpan: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case heading(level: Int)
    case bold
    case italic
    case strikethrough
    case link(url: String)
    case blockquote
    /// List bullet (`-`, `*`, `+`, `1.`) or blockquote `>`. Tinted, never hidden.
    case blockMarker
  }

  let kind: Kind
  let content: NSRange
  let markers: [NSRange]
}

/// Pure, UI-free Markdown span scanner backing the optional live preview.
///
/// Deliberately conservative: emphasis must hug non-space characters and
/// may not sit inside a word (so `2*3*4` and `snake_case_name` stay
/// literal), a heading needs whitespace after its hashes (so `#tag` is a
/// tag), and nothing inside inline code or fenced blocks is touched.
enum MarkdownSpanParser {
  private struct InlineRule {
    let regex: NSRegularExpression?
    let kind: MarkdownSpan.Kind
    let delimiterLength: Int
  }

  private static func regex(_ pattern: String) -> NSRegularExpression? {
    try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
  }

  private static let fenceRegex = regex("```[\\s\\S]*?```")
  private static let inlineCodeRegex = regex("`[^`\\n]+`")
  private static let headingRegex = regex("^(#{1,6})[ \\t]+(?=\\S)(.*)$")
  private static let quoteRegex = regex("^[ \\t]{0,3}(>)[ \\t]?(.*)$")
  private static let listRegex = regex("^[ \\t]*([-*+]|\\d{1,9}[.)])[ \\t]+(?=\\S)")
  private static let linkRegex = regex("(?<!!)\\[([^\\[\\]\\n]+)\\]\\(([^()\\s]+)\\)")
  private static let emphasisRules: [InlineRule] = [
    InlineRule(
      regex: regex("(?<!\\*)\\*\\*(?![\\s*])(.+?)(?<![\\s*])\\*\\*(?!\\*)"),
      kind: .bold,
      delimiterLength: 2
    ),
    InlineRule(
      regex: regex("(?<![\\w_])__(?![\\s_])(.+?)(?<![\\s_])__(?![\\w_])"),
      kind: .bold,
      delimiterLength: 2
    ),
    InlineRule(
      regex: regex("(?<!~)~~(?![\\s~])(.+?)(?<![\\s~])~~(?!~)"),
      kind: .strikethrough,
      delimiterLength: 2
    ),
    InlineRule(
      regex: regex("(?<![\\w*])\\*(?![\\s*])(.+?)(?<![\\s*])\\*(?![\\w*])"),
      kind: .italic,
      delimiterLength: 1
    ),
    InlineRule(
      regex: regex("(?<![\\w_])_(?![\\s_])(.+?)(?<![\\s_])_(?![\\w_])"),
      kind: .italic,
      delimiterLength: 1
    )
  ]

  /// All spans in `text`, sorted by content location.
  /// - Complexity: O(n) regex passes over the document.
  static func spans(in text: NSString) -> [MarkdownSpan] {
    guard text.length > 0 else { return [] }
    let code = codeCharacters(in: text)
    var claimed = code
    var spans = blockSpans(in: text, code: code)
    spans += linkSpans(in: text, claimed: &claimed)
    for rule in emphasisRules {
      spans += emphasisSpans(in: text, rule: rule, claimed: &claimed)
    }
    return spans.sorted { $0.content.location < $1.content.location }
  }

  /// Characters covered by fenced blocks or inline code spans.
  static func codeCharacters(in text: NSString) -> IndexSet {
    var code = IndexSet()
    let full = NSRange(location: 0, length: text.length)
    for match in matches(fenceRegex, in: text, range: full) {
      code.insert(integersIn: Range(match.range) ?? 0..<0)
    }
    for match in matches(inlineCodeRegex, in: text, range: full) where !code.intersects(nsRange: match.range) {
      code.insert(integersIn: Range(match.range) ?? 0..<0)
    }
    return code
  }

  // MARK: - Block-level (line-anchored) constructs

  private static func blockSpans(in text: NSString, code: IndexSet) -> [MarkdownSpan] {
    let full = NSRange(location: 0, length: text.length)
    var spans: [MarkdownSpan] = []
    for match in matches(headingRegex, in: text, range: full) where !code.intersects(nsRange: match.range) {
      let hashes = match.range(at: 1)
      let content = match.range(at: 2)
      let marker = NSRange(location: hashes.location, length: content.location - hashes.location)
      spans.append(MarkdownSpan(kind: .heading(level: hashes.length), content: content, markers: [marker]))
    }
    for match in matches(quoteRegex, in: text, range: full) where !code.intersects(nsRange: match.range) {
      spans.append(MarkdownSpan(kind: .blockMarker, content: match.range(at: 1), markers: []))
      let body = match.range(at: 2)
      if body.length > 0 {
        spans.append(MarkdownSpan(kind: .blockquote, content: body, markers: []))
      }
    }
    for match in matches(listRegex, in: text, range: full) where !code.intersects(nsRange: match.range) {
      spans.append(MarkdownSpan(kind: .blockMarker, content: match.range(at: 1), markers: []))
    }
    return spans
  }

  // MARK: - Inline constructs

  private static func linkSpans(in text: NSString, claimed: inout IndexSet) -> [MarkdownSpan] {
    let full = NSRange(location: 0, length: text.length)
    var spans: [MarkdownSpan] = []
    for match in matches(linkRegex, in: text, range: full) where !claimed.intersects(nsRange: match.range) {
      let label = match.range(at: 1)
      let open = NSRange(location: match.range.location, length: 1)
      let closeStart = label.location + label.length
      let close = NSRange(location: closeStart, length: match.range.location + match.range.length - closeStart)
      let url = text.substring(with: match.range(at: 2))
      spans.append(MarkdownSpan(kind: .link(url: url), content: label, markers: [open, close]))
      claimed.insert(nsRange: open)
      claimed.insert(nsRange: close)
    }
    return spans
  }

  private static func emphasisSpans(
    in text: NSString,
    rule: InlineRule,
    claimed: inout IndexSet
  ) -> [MarkdownSpan] {
    let full = NSRange(location: 0, length: text.length)
    var spans: [MarkdownSpan] = []
    for match in matches(rule.regex, in: text, range: full) {
      let outer = match.range
      let open = NSRange(location: outer.location, length: rule.delimiterLength)
      let close = NSRange(location: outer.location + outer.length - rule.delimiterLength, length: rule.delimiterLength)
      guard !claimed.intersects(nsRange: open), !claimed.intersects(nsRange: close) else { continue }
      spans.append(MarkdownSpan(kind: rule.kind, content: match.range(at: 1), markers: [open, close]))
      claimed.insert(nsRange: open)
      claimed.insert(nsRange: close)
    }
    return spans
  }

  private static func matches(
    _ regex: NSRegularExpression?,
    in text: NSString,
    range: NSRange
  ) -> [NSTextCheckingResult] {
    regex?.matches(in: text as String, range: range) ?? []
  }
}

extension IndexSet {
  func intersects(nsRange range: NSRange) -> Bool {
    guard let swiftRange = Range(range), !swiftRange.isEmpty else { return false }
    return intersects(integersIn: swiftRange)
  }

  mutating func insert(nsRange range: NSRange) {
    guard let swiftRange = Range(range) else { return }
    insert(integersIn: swiftRange)
  }
}
