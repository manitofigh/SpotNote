import CoreGraphics

/// Shared vertical metrics for the multiline editor and the panel sizing code.
enum EditorMetrics {
  /// Line height used by both the panel-sizing code and the editor's
  /// paragraph style, so rendered text and the panel cap agree exactly.
  static let lineHeight: CGFloat = 22
  /// Vertical padding between the content area and the rounded-card edge.
  static let verticalInset: CGFloat = 10
  /// Padding between the rounded card and the panel edge (shadow gutter).
  static let outerPadding: CGFloat = 3
  /// Leading padding inside the rounded card -- small so the line-number
  /// gutter hugs the card's left edge.
  static let leadingInset: CGFloat = 6
  /// Trailing padding inside the rounded card.
  static let trailingInset: CGFloat = 12
  /// Gap applied to the text view's leading text-container inset so the
  /// caret doesn't abut the line-number gutter.
  static let textLeadingGap: CGFloat = 8
  /// Extra right-side padding so text wraps before reaching the copy
  /// button overlaid at the top-right of the editor card.
  static let textTrailingGap: CGFloat = 26
  /// Font size used for the editor text.
  static let fontSize: CGFloat = 16
  /// Panel width.
  static let panelWidth: CGFloat = 580
  /// Fixed height of the optional tutorial bar drawn above the editor
  /// card. Sized for two rows of compact `KeyCap`-styled chord hints.
  static let tutorialBarHeight: CGFloat = 44
  /// Fixed height of the find-in-note bar (⌘F).
  static let findBarHeight: CGFloat = 30

  /// Panel height for `lines` display rows, clamped to `[1, maxLines]`.
  /// `maxLines` is the user-configurable upper bound (see
  /// `ThemePreferences.maxVisibleLines`); the clamp floor is always 1 so
  /// the HUD never renders shorter than a single row.
  static func panelHeight(forLines lines: Int, maxLines: Int) -> CGFloat {
    let clampedMax = max(1, maxLines)
    let clamped = min(max(1, lines), clampedMax)
    return CGFloat(clamped) * lineHeight + verticalInset * 2 + outerPadding * 2
  }

  static func lineCount(in text: String) -> Int {
    max(1, text.components(separatedBy: "\n").count)
  }
}
