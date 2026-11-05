import Foundation

/// Answer formatting shared by arithmetic and unit conversion.
///
/// Rules: integers print plainly with no grouping separators (so an
/// accepted answer can be fed straight back into another expression),
/// non-integers keep up to 6 fraction digits with trailing zeros trimmed,
/// and the decimal separator is always `.`. Magnitude suffixes in the
/// input never change the output style: `1.5m * 2` answers `3000000`.
enum MathFormat {
  static func number(_ value: Double, base: MathSuggester.Base) -> String {
    let isInt = isIntegral(value)
    if base == .decimal {
      return isInt ? String(Int(value)) : decimal(value, significantDigits: nil)
    }
    guard isInt else { return decimal(value, significantDigits: nil) }
    let intValue = Int(value)
    let absStr = String(abs(intValue), radix: radix(for: base))
    return (intValue < 0 ? "-" : "") + base.prefix + absStr
  }

  /// A percent-tagged result (`50% + 10%`) renders as a percentage.
  static func percent(_ value: Double) -> String {
    number(value * 100, base: .decimal) + "%"
  }

  /// Converted quantities can be legitimately tiny (`1 mm in mi`), so
  /// values below 1 keep 6 significant digits instead of 6 fraction
  /// digits, which would round them to zero.
  static func measurement(_ value: Double) -> String {
    guard value != 0, abs(value) < 1 else { return number(value, base: .decimal) }
    return decimal(value, significantDigits: 6)
  }

  private static func isIntegral(_ value: Double) -> Bool {
    value.rounded() == value && abs(value) < 1e15 && !value.isInfinite && !value.isNaN
  }

  private static func radix(for base: MathSuggester.Base) -> Int {
    switch base {
    case .hex: return 16
    case .binary: return 2
    case .octal: return 8
    case .decimal: return 10
    }
  }

  private static func decimal(_ value: Double, significantDigits: Int?) -> String {
    let formatter = NumberFormatter()
    if let significantDigits {
      formatter.usesSignificantDigits = true
      formatter.maximumSignificantDigits = significantDigits
    } else {
      formatter.maximumFractionDigits = 6
      formatter.minimumFractionDigits = 0
    }
    formatter.usesGroupingSeparator = false
    // The input grammar only accepts "." as the decimal separator, so the
    // answer must use it too regardless of the user's locale.
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }
}
