import AppKit

// MARK: - MultilineEditor + Markdown live preview hooks

extension MultilineEditor {
  /// Runs after `CodeStyler.apply` on every restyle. A no-op while the
  /// preference is off and the preview was never active, so the editor
  /// behaves exactly as without the feature.
  func applyMarkdownPreview(on textView: NSTextView) {
    guard let textView = textView as? PlaceholderTextView,
      markdownPreviewEnabled || textView.markdownPreview.isActive
    else { return }
    let layoutChanged =
      markdownPreviewEnabled
      ? MarkdownPreviewStyler.apply(to: textView, theme: theme, baseFont: font)
      : MarkdownPreviewStyler.tearDown(textView, baseFont: font)
    if layoutChanged { reportMarkdownHeight(for: textView) }
  }

  /// Picks up a preference flip without a text change.
  func syncMarkdownPreview(on textView: PlaceholderTextView) {
    guard textView.markdownPreview.isActive != markdownPreviewEnabled else { return }
    applyCodeStyling(on: textView)
  }

  /// Shows raw Markdown on the selection's lines and re-renders the lines
  /// it left. Resizes only if that changed the soft-wrap row count, which
  /// is computed after the visibility update, so there is no feedback loop.
  func revealMarkdownForSelection(on textView: PlaceholderTextView) {
    guard MarkdownPreviewStyler.revealSelection(in: textView) else { return }
    reportMarkdownHeight(for: textView)
  }

  private func reportMarkdownHeight(for textView: NSTextView) {
    // Not yet in a window (initial `makeNSView`): `updateNSView` sizes it.
    guard textView.window != nil else { return }
    let rows = LineNumberRuler.displayRowCount(in: textView)
    let editorHeight = EditorMetrics.panelHeight(forLines: rows, maxLines: maxVisibleLines)
    onHeightChange(editorHeight + extraChromeHeight)
  }
}

// MARK: - PlaceholderTextView + Markdown links

extension PlaceholderTextView {
  /// ⌘-click on a rendered `[label](url)` opens the URL.
  func openMarkdownLinkIfNeeded(at containerPoint: NSPoint, event: NSEvent) -> Bool {
    guard markdownPreview.isActive,
      event.modifierFlags.contains(.command),
      let index = markdownCharacterIndex(at: containerPoint),
      let url = markdownPreview.linkURL(at: index)
    else { return false }
    NSWorkspace.shared.open(url)
    return true
  }

  /// Character whose glyph is actually under `containerPoint` (not merely
  /// the nearest insertion point), so clicks past a line's end don't hit.
  private func markdownCharacterIndex(at containerPoint: NSPoint) -> Int? {
    guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else { return nil }
    let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
    let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
    guard rect.contains(containerPoint) else { return nil }
    return layoutManager.characterIndexForGlyph(at: glyph)
  }
}
