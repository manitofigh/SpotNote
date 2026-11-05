import AppKit

/// Per-text-view live-preview state, stored on `PlaceholderTextView`.
struct MarkdownPreviewState {
  struct LinkTarget {
    let label: NSRange
    let url: String
  }

  /// `true` once the preview has styled the view; cleared on tear-down.
  var isActive = false
  /// Characters of the paragraphs touched by the selection. Markers here
  /// are shown raw so the line under the caret is fully editable.
  var revealed = IndexSet()
  var links: [LinkTarget] = []

  /// URL of the `[label](url)` whose label covers `index`, if any.
  func linkURL(at index: Int) -> URL? {
    guard let target = links.first(where: { NSLocationInRange(index, $0.label) }) else { return nil }
    return Self.resolvedURL(target.url)
  }

  /// Scheme-less targets (`example.com/x`) are treated as `https`.
  static func resolvedURL(_ raw: String) -> URL? {
    guard let url = URL(string: raw) else { return nil }
    if url.scheme != nil { return url }
    return URL(string: "https://" + raw)
  }
}

/// Applies the optional Markdown live preview to the editor.
///
/// - Fonts (bold / italic / heading weight) are real storage attributes,
///   because temporary attributes cannot change fonts. They are diffed
///   against what's already there so an unchanged document triggers no
///   storage edit, and storage attribute edits never register undo or
///   post `textDidChange`, so they cannot dirty the note.
/// - Colours, underline and strikethrough are layout-manager temporary
///   attributes, like `CodeStyler`.
/// - Marker hiding is glyph-level (see `MarkdownGlyphVisibility`).
///
/// Headings `#`–`###` use larger bold fonts; everything else keeps the
/// editor's point size. `FixedLineHeightLayoutManager` still lays every
/// line out at exactly `EditorMetrics.lineHeight`, and heading fonts do
/// not depend on whether the line is revealed, so moving the caret never
/// changes a line's size.
@MainActor
enum MarkdownPreviewStyler {
  private struct Fonts {
    let base: NSFont
    let bold: NSFont
    let italic: NSFont
    let boldItalic: NSFont
    /// Bold, scaled per heading level (index 0 = `#`). Capped so caps and
    /// descenders still fit `EditorMetrics.lineHeight`: the layout manager
    /// pins every glyph run to the base font's baseline, so a larger font
    /// only grows upward into the fragment's spare room and never changes
    /// line height (see `FixedLineHeightLayoutManager.setLocation`).
    let headings: [NSFont]

    /// Size multipliers for `#`, `##`, `###`; deeper levels stay bold at
    /// the base size.
    private static let headingScales: [CGFloat] = [1.3, 1.18, 1.08]

    init(base: NSFont) {
      let manager = NSFontManager.shared
      var bold = manager.convert(base, toHaveTrait: .boldFontMask)
      if bold == base {
        bold = .systemFont(ofSize: base.pointSize, weight: .semibold)
      }
      self.base = base
      self.bold = bold
      self.italic = manager.convert(base, toHaveTrait: .italicFontMask)
      self.boldItalic = manager.convert(bold, toHaveTrait: .italicFontMask)
      self.headings = Self.headingScales.map { manager.convert(bold, toSize: (base.pointSize * $0).rounded()) }
    }

    func heading(level: Int) -> NSFont {
      level <= headings.count ? headings[max(0, level - 1)] : bold
    }

    func isManaged(_ font: NSFont) -> Bool {
      font == base || font == bold || font == italic || font == boldItalic || headings.contains(font)
    }
  }

  private static let temporaryKeys: [NSAttributedString.Key] = [.underlineStyle, .strikethroughStyle]

  /// Styles the whole document. Call after `CodeStyler.apply`, which
  /// clears the temporary colours this re-adds.
  /// - Returns: `true` when fonts or marker visibility changed, i.e. the
  ///   soft-wrap row count may differ.
  static func apply(to textView: PlaceholderTextView, theme: Theme, baseFont: NSFont) -> Bool {
    guard let layoutManager = textView.layoutManager as? FixedLineHeightLayoutManager,
      let storage = textView.textStorage
    else { return false }
    let text = storage.string as NSString
    let spans = MarkdownSpanParser.spans(in: text)
    let fontsChanged = applyFonts(spans: spans, to: storage, fonts: Fonts(base: baseFont))
    applyTemporaryStyles(spans: spans, layoutManager: layoutManager, theme: theme, length: text.length)
    var markers = IndexSet()
    for span in spans {
      for marker in span.markers {
        markers.insert(integersIn: Range(marker) ?? 0..<0)
      }
    }
    layoutManager.markdownGlyphs.markers = markers
    let revealed = revealedParagraphs(in: textView)
    textView.markdownPreview.isActive = true
    textView.markdownPreview.revealed = revealed
    textView.markdownPreview.links = spans.compactMap { span in
      guard case .link(let url) = span.kind else { return nil }
      return MarkdownPreviewState.LinkTarget(label: span.content, url: url)
    }
    let visibilityChanged = layoutManager.updateMarkdownVisibility(in: 0..<text.length, revealed: revealed)
    return fontsChanged || visibilityChanged
  }

  /// Restores the plain editor look after the preference is switched off.
  /// - Returns: `true` when anything layout-affecting was undone.
  static func tearDown(_ textView: PlaceholderTextView, baseFont: NSFont) -> Bool {
    guard let layoutManager = textView.layoutManager as? FixedLineHeightLayoutManager,
      let storage = textView.textStorage
    else { return false }
    let fontsChanged = applyFonts(spans: [], to: storage, fonts: Fonts(base: baseFont))
    let full = NSRange(location: 0, length: storage.length)
    for key in temporaryKeys {
      layoutManager.removeTemporaryAttribute(key, forCharacterRange: full)
    }
    let hadHidden = !layoutManager.markdownGlyphs.hidden.isEmpty
    layoutManager.clearMarkdownVisibility()
    textView.markdownPreview = MarkdownPreviewState()
    return fontsChanged || hadHidden
  }

  /// Re-reveals for a selection change. Touches only the paragraphs that
  /// left or joined the selection, so a caret move within a line is a
  /// no-op and a move between lines costs O(those two lines).
  /// - Returns: `true` when the affected paragraphs' row count changed.
  static func revealSelection(in textView: PlaceholderTextView) -> Bool {
    guard textView.markdownPreview.isActive,
      let layoutManager = textView.layoutManager as? FixedLineHeightLayoutManager
    else { return false }
    let revealed = revealedParagraphs(in: textView)
    let previous = textView.markdownPreview.revealed
    guard revealed != previous else { return false }
    textView.markdownPreview.revealed = revealed
    let length = textView.textStorage?.length ?? 0
    var rowDelta = 0
    var visibilityChanged = false
    for run in previous.union(revealed).rangeView {
      let clamped = run.clamped(to: 0..<length)
      let range = NSRange(clamped)
      let before = layoutManager.lineFragmentCount(forCharacterRange: range)
      guard layoutManager.updateMarkdownVisibility(in: clamped, revealed: revealed) else { continue }
      visibilityChanged = true
      rowDelta += layoutManager.lineFragmentCount(forCharacterRange: range) - before
    }
    if visibilityChanged {
      textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }
    return rowDelta != 0
  }

  private static func revealedParagraphs(in textView: NSTextView) -> IndexSet {
    let text = textView.string as NSString
    guard text.length > 0 else { return IndexSet() }
    let selection = textView.selectedRange
    let location = min(selection.location, text.length)
    let length = min(selection.length, text.length - location)
    let paragraph = text.paragraphRange(for: NSRange(location: location, length: length))
    return IndexSet(integersIn: Range(paragraph) ?? 0..<0)
  }

  // MARK: - Fonts

  private static func applyFonts(spans: [MarkdownSpan], to storage: NSTextStorage, fonts: Fonts) -> Bool {
    var bold = IndexSet()
    var italic = IndexSet()
    var headings: [Int: IndexSet] = [:]
    for span in spans {
      let range = Range(span.content) ?? 0..<0
      switch span.kind {
      case .heading(let level): headings[level, default: IndexSet()].insert(integersIn: range)
      case .bold: bold.insert(integersIn: range)
      case .italic, .blockquote: italic.insert(integersIn: range)
      case .strikethrough, .link, .blockMarker: break
      }
    }
    // A heading's size wins over any emphasis inside it.
    let headed = headings.values.reduce(into: IndexSet()) { $0.formUnion($1) }
    bold.subtract(headed)
    italic.subtract(headed)
    let plain = IndexSet(integersIn: 0..<storage.length).subtracting(bold).subtracting(italic).subtracting(headed)
    let plan: [(IndexSet, NSFont)] =
      headings.map { ($0.value, fonts.heading(level: $0.key)) } + [
        (plain, fonts.base),
        (bold.subtracting(italic), fonts.bold),
        (italic.subtracting(bold), fonts.italic),
        (bold.intersection(italic), fonts.boldItalic)
      ]
    var fixes: [(NSRange, NSFont)] = []
    for (set, font) in plan {
      for run in set.rangeView {
        storage.enumerateAttribute(.font, in: NSRange(run)) { value, range, _ in
          // Leave fonts we didn't set alone (e.g. emoji fallback fonts
          // chosen by attribute fixing), or every pass would fight them.
          guard let current = value as? NSFont, current != font, fonts.isManaged(current) else { return }
          fixes.append((range, font))
        }
      }
    }
    guard !fixes.isEmpty else { return false }
    storage.beginEditing()
    for (range, font) in fixes {
      storage.addAttribute(.font, value: font, range: range)
    }
    storage.endEditing()
    return true
  }

  // MARK: - Temporary attributes

  private static func applyTemporaryStyles(
    spans: [MarkdownSpan],
    layoutManager: NSLayoutManager,
    theme: Theme,
    length: Int
  ) {
    let full = NSRange(location: 0, length: length)
    for key in temporaryKeys {
      layoutManager.removeTemporaryAttribute(key, forCharacterRange: full)
    }
    let muted = NSColor(theme.placeholder)
    let markerColor = muted.withAlphaComponent(0.7)
    for span in spans {
      for marker in span.markers {
        layoutManager.addTemporaryAttribute(.foregroundColor, value: markerColor, forCharacterRange: marker)
      }
      let attributes = temporaryAttributes(for: span.kind, muted: muted)
      if !attributes.isEmpty {
        layoutManager.addTemporaryAttributes(attributes, forCharacterRange: span.content)
      }
    }
  }

  private static func temporaryAttributes(
    for kind: MarkdownSpan.Kind,
    muted: NSColor
  ) -> [NSAttributedString.Key: Any] {
    switch kind {
    case .heading, .bold, .italic:
      return [:]
    case .strikethrough:
      return [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: muted]
    case .link:
      return [.underlineStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.linkColor]
    case .blockquote, .blockMarker:
      return [.foregroundColor: muted]
    }
  }
}
