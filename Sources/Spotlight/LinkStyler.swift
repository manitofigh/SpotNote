import AppKit

extension NSAttributedString.Key {
  /// Temporary attribute marking a detected link; value is a
  /// `LinkKind.rawValue`. Read back by hover / ⌘-click handling.
  static let spotNoteLink = NSAttributedString.Key("SpotNoteLink")
}

/// Styles detected links (see `LinkDetector`) with a theme-tinted color
/// and a single underline, via `NSLayoutManager` temporary attributes.
/// Neither attribute affects glyph advances or line height, so the
/// fixed-line-height layout is untouched and nothing is re-laid out.
@MainActor
enum LinkStyler {
  /// Shared across editors: keys are line contents, so reuse is safe
  /// regardless of which text view produced them.
  private static var cache = LinkLineCache()

  static func apply(to layoutManager: NSLayoutManager, text: NSString, theme: Theme) {
    let full = NSRange(location: 0, length: text.length)
    clearPreviousStyling(layoutManager: layoutManager, fullRange: full)
    guard full.length > 0 else { return }
    let color = linkColor(for: theme)
    let underlineColor = color.withAlphaComponent(0.55)
    for span in LinkDetector.spans(in: text, cache: &cache) where isActionable(span, in: text) {
      layoutManager.addTemporaryAttributes(
        [
          .foregroundColor: color,
          .underlineStyle: NSUnderlineStyle.single.rawValue,
          .underlineColor: underlineColor,
          .spotNoteLink: span.kind.rawValue
        ],
        forCharacterRange: span.range
      )
    }
  }

  /// Removes underline attributes only where this styler put them, so
  /// other stylers' underlines (if any) survive. Foreground color is
  /// already cleared document-wide by `CodeStyler.apply`.
  private static func clearPreviousStyling(layoutManager: NSLayoutManager, fullRange: NSRange) {
    guard fullRange.length > 0 else { return }
    var index = fullRange.location
    while index < NSMaxRange(fullRange) {
      var range = NSRange(location: index, length: 0)
      let value = layoutManager.temporaryAttribute(
        .spotNoteLink,
        atCharacterIndex: index,
        longestEffectiveRange: &range,
        in: fullRange
      )
      if value != nil {
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: range)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: range)
      }
      index = max(NSMaxRange(range), index + 1)
    }
    layoutManager.removeTemporaryAttribute(.spotNoteLink, forCharacterRange: fullRange)
  }

  /// File paths are only styled when they exist on disk; a stat per
  /// path per pass is cheap next to the text scan.
  private static func isActionable(_ span: LinkSpan, in text: NSString) -> Bool {
    guard span.kind == .filePath else { return true }
    let path = (text.substring(with: span.range) as NSString).expandingTildeInPath
    return FileManager.default.fileExists(atPath: path)
  }

  private static func linkColor(for theme: Theme) -> NSColor {
    switch theme.mode {
    case .dark: return NSColor(srgbRed: 0.48, green: 0.70, blue: 1.0, alpha: 1.0)
    case .light: return NSColor(srgbRed: 0.04, green: 0.38, blue: 0.84, alpha: 1.0)
    }
  }
}
