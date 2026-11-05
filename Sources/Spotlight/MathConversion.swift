import Foundation

/// Unit conversion at the tail of a line: `<quantity> in|to <unit>`,
/// e.g. `5 km in mi`, `2.5 GB to MB`, `100 F in C`, `3h 20m in min`.
///
/// The quantity is one or more `<number><unit>` terms of the same
/// dimension, summed (compound terms are not allowed for temperatures).
/// Unit names win over magnitude suffixes here, so `5m in ft` is metres.
/// When a name is ambiguous (`m` = metre or minute) the target unit's
/// dimension decides. The answer carries the target unit as typed.
enum MathConversion {
  /// - Complexity: O(n) in the length of `line`.
  static func suggestion(for line: String) -> MathSuggester.Result? {
    let chars = Array(line)
    var end = chars.count
    while end > 0, chars[end - 1].isWhitespace { end -= 1 }
    guard let target = trailingWord(chars, before: end, where: isUnitCharacter),
      let keyword = trailingWord(chars, before: skipWhitespace(chars, before: target.start), where: \.isLetter),
      ["in", "to"].contains(keyword.text.lowercased())
    else { return nil }
    let quantityEnd = skipWhitespace(chars, before: keyword.start)
    for unit in MathUnit.units(named: target.text) {
      guard let quantity = parseQuantity(chars, before: quantityEnd, dimension: unit.dimension) else { continue }
      let value = unit.fromBase(quantity.base)
      guard value.isFinite else { return nil }
      let answer = MathFormat.measurement(value) + " " + target.text
      return MathSuggester.Result(answer: answer, consumed: end - quantity.start)
    }
    return nil
  }

  private static func isUnitCharacter(_ ch: Character) -> Bool {
    ch.isLetter || ch == "°"
  }

  private static func skipWhitespace(_ chars: [Character], before end: Int) -> Int {
    var idx = end
    while idx > 0, chars[idx - 1].isWhitespace { idx -= 1 }
    return idx
  }

  /// The run of `matching` characters ending at `end`, if non-empty.
  private static func trailingWord(
    _ chars: [Character],
    before end: Int,
    where matching: (Character) -> Bool
  ) -> (text: String, start: Int)? {
    var start = end
    while start > 0, matching(chars[start - 1]) { start -= 1 }
    guard start < end else { return nil }
    return (String(chars[start..<end]), start)
  }

  /// Sums `<number><unit>` terms walking backwards from `end`.
  private static func parseQuantity(
    _ chars: [Character],
    before end: Int,
    dimension: MathUnit.Dimension
  ) -> (base: Double, start: Int)? {
    var total = 0.0
    var start: Int?
    var cursor = end
    while let term = parseTerm(chars, before: cursor, dimension: dimension) {
      total += term.base
      start = term.start
      cursor = skipWhitespace(chars, before: term.start)
      if dimension == .temperature { break }
    }
    guard let start else { return nil }
    // The quantity must start a word: "abc5 km" is not a quantity.
    if start > 0, !chars[start - 1].isWhitespace, chars[start - 1] != "(" { return nil }
    return (total, start)
  }

  private static func parseTerm(
    _ chars: [Character],
    before end: Int,
    dimension: MathUnit.Dimension
  ) -> (base: Double, start: Int)? {
    guard let unitWord = trailingWord(chars, before: end, where: isUnitCharacter),
      let unit = MathUnit.units(named: unitWord.text).first(where: { $0.dimension == dimension })
    else { return nil }
    let numberEnd = skipWhitespace(chars, before: unitWord.start)
    guard let digits = trailingWord(chars, before: numberEnd, where: { $0.isNumber || $0 == "." }),
      var value = Double(digits.text)
    else { return nil }
    var start = digits.start
    if start > 0, chars[start - 1] == "-", start == 1 || chars[start - 2].isWhitespace {
      value = -value
      start -= 1
    }
    return (unit.toBase(value), start)
  }
}
