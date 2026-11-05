import AppKit

/// Paints `#tags` as tinted pills using `NSLayoutManager` temporary
/// attributes (foreground + background colour only), so glyph widths and
/// the fixed line height are never touched. Runs after `CodeStyler`,
/// which clears the same temporary attributes over the full range first.
@MainActor
enum TagStyler {
  struct Colors {
    let foreground: NSColor
    let background: NSColor
  }

  /// Styles every tag in `textView` and refreshes the hover affordance
  /// (installed lazily on first use) with the new tag ranges.
  /// - Complexity: O(n) in the text length.
  static func apply(to textView: NSTextView, theme: Theme, store: TagColorStore = .shared) {
    guard let layoutManager = textView.layoutManager else { return }
    let matches = TagParser.matches(in: textView.string)
    for match in matches {
      let colors = colors(for: store.color(for: match.name), mode: theme.mode)
      layoutManager.addTemporaryAttribute(
        .foregroundColor,
        value: colors.foreground,
        forCharacterRange: match.range
      )
      layoutManager.addTemporaryAttribute(
        .backgroundColor,
        value: colors.background,
        forCharacterRange: match.range
      )
    }
    TagHoverController.attached(to: textView).update(matches: matches, theme: theme, store: store)
  }

  static func colors(for color: TagColor?, mode: Theme.Mode) -> Colors {
    let foreground = color?.foreground(for: mode) ?? defaultForeground(for: mode)
    let alpha: CGFloat = mode == .dark ? 0.18 : 0.12
    return Colors(foreground: foreground, background: foreground.withAlphaComponent(alpha))
  }

  private static func defaultForeground(for mode: Theme.Mode) -> NSColor {
    switch mode {
    case .dark: return NSColor(srgbRed: 0.62, green: 0.72, blue: 0.90, alpha: 1)
    case .light: return NSColor(srgbRed: 0.24, green: 0.38, blue: 0.62, alpha: 1)
    }
  }
}
