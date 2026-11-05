import AppKit

// MARK: - MultilineEditor + tag highlighting preference

extension MultilineEditor {
  /// Paints `#tags` when the preference is on. When off, `CodeStyler`
  /// has already cleared the tag colours this pass, so only the hover
  /// affordance needs dropping.
  func applyTagHighlighting(on textView: NSTextView) {
    if highlightTagsEnabled {
      TagStyler.apply(to: textView, theme: theme)
    } else {
      TagHoverController.existing(on: textView)?.update(matches: [], theme: theme, store: .shared)
    }
    (textView as? PlaceholderTextView)?.tagsHighlighted = highlightTagsEnabled
  }

  /// Picks up a preference flip without a text change.
  func syncTagHighlighting(on textView: PlaceholderTextView) {
    guard textView.tagsHighlighted != highlightTagsEnabled else { return }
    applyCodeStyling(on: textView)
  }
}
