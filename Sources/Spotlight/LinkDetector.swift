import Foundation

/// Kind of actionable span found in note text. The raw value is stored
/// as a layout-manager temporary attribute so hover / ⌘-click can read
/// the span back without re-running detection.
enum LinkKind: String, Sendable {
  case web
  case email
  case filePath
  case date
}

struct LinkSpan: Equatable, Sendable {
  let range: NSRange
  let kind: LinkKind
}

/// What a ⌘-click on a span resolves to.
enum LinkTarget: Equatable, Sendable {
  case url(URL)
  case file(URL)
  case date(Date)
}

/// Per-line memo of detection results. Keys are line contents (without
/// the terminator), values are spans relative to the line start. Each
/// pass rebuilds the dictionary from the current document's lines, so
/// the cache never outgrows the note and an edit only re-detects the
/// lines whose text actually changed.
struct LinkLineCache {
  var entries: [String: [LinkSpan]] = [:]
}

/// Finds URLs, email addresses, absolute / `~` file paths, and dates in
/// note text, skipping anything inside inline code or fenced blocks.
/// Detection is line-local: a match never spans a line break.
@MainActor
enum LinkDetector {
  // `NSDataDetector` is expensive to build; construct it once. The
  // initializer only throws for an invalid type mask, which is a
  // compile-time constant here, so a nil result is unreachable.
  private static let dataDetector = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.link.rawValue
      | NSTextCheckingResult.CheckingType.date.rawValue
  )
  // Absolute or home-relative path at a word boundary. The first char
  // after the slash can't be another slash (rules out `//comment`).
  private static let pathRegex = try? NSRegularExpression(
    pattern: #"(?:^|(?<=[\s(\[{"'<]))~?/[^\s/"'<>`()\[\]{}][^\s"'<>`()\[\]{}]*"#
  )
  private static let fenceRegex = try? NSRegularExpression(pattern: "```([\\s\\S]*?)```")
  private static let inlineCodeRegex = try? NSRegularExpression(pattern: "`([^`\\n]+)`")
  private static let webSchemes: Set<String> = ["http", "https"]
  private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?")

  /// Uncached convenience over `spans(in:cache:)`.
  static func spans(in text: NSString) -> [LinkSpan] {
    var cache = LinkLineCache()
    return spans(in: text, cache: &cache)
  }

  /// Every actionable span in `text`, in document order, excluding
  /// spans that touch inline code or fenced code blocks.
  ///
  /// - Complexity: O(n) over the document for line splitting and the
  ///   code-span scan; data detection only runs on lines missing from
  ///   `cache`.
  static func spans(in text: NSString, cache: inout LinkLineCache) -> [LinkSpan] {
    let previous = cache.entries
    var fresh: [String: [LinkSpan]] = [:]
    var result: [LinkSpan] = []
    let full = NSRange(location: 0, length: text.length)
    text.enumerateSubstrings(in: full, options: [.byLines]) { line, lineRange, _, _ in
      guard let line, !line.isEmpty else { return }
      let local = fresh[line] ?? previous[line] ?? lineSpans(in: line)
      fresh[line] = local
      for span in local {
        let shifted = NSRange(location: lineRange.location + span.range.location, length: span.range.length)
        result.append(LinkSpan(range: shifted, kind: span.kind))
      }
    }
    cache.entries = fresh
    guard !result.isEmpty else { return result }
    let code = codeRanges(in: text)
    guard !code.isEmpty else { return result }
    return result.filter { span in
      !code.contains { NSIntersectionRange($0, span.range).length > 0 }
    }
  }

  /// Spans within a single line, relative to the line start.
  static func lineSpans(in line: String) -> [LinkSpan] {
    let nsLine = line as NSString
    let full = NSRange(location: 0, length: nsLine.length)
    var spans: [LinkSpan] = []
    dataDetector?.enumerateMatches(in: line, range: full) { match, _, _ in
      guard let match, let kind = kind(of: match) else { return }
      spans.append(LinkSpan(range: match.range, kind: kind))
    }
    pathRegex?.enumerateMatches(in: line, range: full) { match, _, _ in
      guard let match else { return }
      let range = trimmedTrailingPunctuation(match.range, in: nsLine)
      guard range.length > 1 else { return }
      if spans.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) { return }
      spans.append(LinkSpan(range: range, kind: .filePath))
    }
    return spans.sorted { $0.range.location < $1.range.location }
  }

  /// Ranges covered by triple-fenced blocks and inline `` `code` ``
  /// spans, using the same patterns `CodeStyler` styles.
  static func codeRanges(in text: NSString) -> [NSRange] {
    let full = NSRange(location: 0, length: text.length)
    let string = text as String
    var ranges: [NSRange] = []
    fenceRegex?.enumerateMatches(in: string, range: full) { match, _, _ in
      if let match { ranges.append(match.range) }
    }
    let fences = ranges
    inlineCodeRegex?.enumerateMatches(in: string, range: full) { match, _, _ in
      guard let match else { return }
      if fences.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { return }
      ranges.append(match.range)
    }
    return ranges
  }

  /// Resolves the literal text of a span to something openable. Done
  /// at click time (not cached) so relative dates like "tomorrow" are
  /// evaluated against the current day.
  static func target(for literal: String, kind: LinkKind) -> LinkTarget? {
    switch kind {
    case .filePath:
      let expanded = (literal as NSString).expandingTildeInPath
      return .file(URL(fileURLWithPath: expanded))
    case .web, .email:
      return firstMatch(in: literal)?.url.map(LinkTarget.url)
    case .date:
      return firstMatch(in: literal)?.date.map(LinkTarget.date)
    }
  }

  private static func firstMatch(in literal: String) -> NSTextCheckingResult? {
    let range = NSRange(location: 0, length: (literal as NSString).length)
    return dataDetector?.firstMatch(in: literal, range: range)
  }

  private static func kind(of match: NSTextCheckingResult) -> LinkKind? {
    if match.resultType == .date { return .date }
    guard match.resultType == .link, let scheme = match.url?.scheme?.lowercased() else { return nil }
    if scheme == "mailto" { return .email }
    return webSchemes.contains(scheme) ? .web : nil
  }

  private static func trimmedTrailingPunctuation(_ range: NSRange, in text: NSString) -> NSRange {
    var length = range.length
    while length > 0 {
      guard let scalar = UnicodeScalar(text.character(at: range.location + length - 1)),
        trailingPunctuation.contains(scalar)
      else { break }
      length -= 1
    }
    return NSRange(location: range.location, length: length)
  }
}
