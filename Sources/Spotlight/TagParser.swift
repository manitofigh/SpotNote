import Foundation

/// One `#tag` occurrence in a note. `range` is a UTF-16 (`NSString`)
/// range covering the leading `#` and the tag body; `name` is the
/// normalized (lowercased, `#`-less) tag identity.
struct TagMatch: Equatable, Sendable {
  let range: NSRange
  let name: String
}

/// Extracts `#tags` from note text.
///
/// Grammar (deliberately conservative so it never fights Markdown):
/// - A tag is `#` immediately followed by one or more tag characters:
///   Unicode letters/marks, decimal digits, `_`, `-` or `/`
///   (`#work`, `#proj/alpha`, `#café`, `#2024-plan`).
/// - The `#` must start the text or follow whitespace or an opening
///   punctuation mark (`(`, `[`, `{`, quotes, `,`, `;`). This rules out
///   URL fragments (`example.com/#top`, `page#top`), `a#b` and the second
///   `#` of `##`.
/// - The body must contain at least one letter, so issue references such
///   as `#123` are not tags.
/// - Trailing `-` / `/` are trimmed (`#work/` -> `work`).
/// - `# heading` (hash + space) and `##tag` are not tags.
/// - Anything inside inline code (`` `#x` ``) or a triple-backtick fenced
///   block is ignored, mirroring `CodeStyler`'s fence detection.
///
/// Tag identity is case-insensitive: names are lowercased.
enum TagParser {
  private static let openingPunctuation: Set<Unicode.Scalar> = [
    "(", "[", "{", "\"", "'", "\u{201C}", "\u{2018}", "\u{00AB}", ",", ";"
  ]
  private static let trailingTrim: Set<Unicode.Scalar> = ["-", "/"]

  /// - Complexity: O(n) in the length of `text`.
  static func matches(in text: String) -> [TagMatch] {
    guard text.unicodeScalars.contains("#") else { return [] }
    let scalars = Array(text.unicodeScalars)
    let offsets = utf16Offsets(of: scalars)
    let excluded = codeRanges(in: text)
    var results: [TagMatch] = []
    var resumeAt = 0
    for index in scalars.indices where index >= resumeAt && scalars[index] == "#" {
      let previous = index > 0 ? scalars[index - 1] : nil
      guard isBoundary(previous), let end = bodyEnd(in: scalars, after: index) else { continue }
      resumeAt = end
      let range = NSRange(location: offsets[index], length: offsets[end] - offsets[index])
      if excluded.contains(where: { NSIntersectionRange($0, range).length > 0 }) { continue }
      var body = String.UnicodeScalarView()
      body.append(contentsOf: scalars[(index + 1)..<end])
      results.append(TagMatch(range: range, name: normalize(String(body))))
    }
    return results
  }

  /// Unique normalized tag names found in `text`.
  static func tags(in text: String) -> Set<String> {
    Set(matches(in: text).map(\.name))
  }

  static func normalize(_ name: String) -> String {
    name.lowercased()
  }

  static func isTagCharacter(_ scalar: Unicode.Scalar) -> Bool {
    if scalar == "_" || scalar == "-" || scalar == "/" { return true }
    if scalar.properties.isAlphabetic { return true }
    switch scalar.properties.generalCategory {
    case .decimalNumber, .nonspacingMark, .spacingMark: return true
    default: return false
    }
  }

  /// `true` when `body` (tag text without `#`) is a valid tag body:
  /// only tag characters, at least one letter, no trailing `-` / `/`.
  static func isValidBody<S: Sequence>(_ body: S) -> Bool where S.Element == Unicode.Scalar {
    var hasLetter = false
    var last: Unicode.Scalar?
    for scalar in body {
      guard isTagCharacter(scalar) else { return false }
      if scalar.properties.isAlphabetic { hasLetter = true }
      last = scalar
    }
    guard let last else { return false }
    return hasLetter && !trailingTrim.contains(last)
  }

  // MARK: - Private

  private static func isBoundary(_ previous: Unicode.Scalar?) -> Bool {
    guard let previous else { return true }
    return previous.properties.isWhitespace || openingPunctuation.contains(previous)
  }

  /// Index one past the last body scalar of a tag whose `#` sits at
  /// `hashIndex`, or `nil` when no valid tag starts there.
  private static func bodyEnd(in scalars: [Unicode.Scalar], after hashIndex: Int) -> Int? {
    var end = hashIndex + 1
    while end < scalars.count, isTagCharacter(scalars[end]) { end += 1 }
    while end > hashIndex + 1, trailingTrim.contains(scalars[end - 1]) { end -= 1 }
    guard end > hashIndex + 1 else { return nil }
    return isValidBody(scalars[(hashIndex + 1)..<end]) ? end : nil
  }

  private static func utf16Offsets(of scalars: [Unicode.Scalar]) -> [Int] {
    var offsets: [Int] = []
    offsets.reserveCapacity(scalars.count + 1)
    var running = 0
    for scalar in scalars {
      offsets.append(running)
      running += scalar.utf16.count
    }
    offsets.append(running)
    return offsets
  }

  private static let fencePattern = try? NSRegularExpression(pattern: "```[\\s\\S]*?```")
  private static let inlinePattern = try? NSRegularExpression(pattern: "`[^`\\n]+`")

  private static func codeRanges(in text: String) -> [NSRange] {
    guard text.unicodeScalars.contains("`") else { return [] }
    let fullRange = NSRange(location: 0, length: (text as NSString).length)
    let fenced = fencePattern?.matches(in: text, range: fullRange).map(\.range) ?? []
    let inline = inlinePattern?.matches(in: text, range: fullRange).map(\.range) ?? []
    return fenced + inline
  }
}
