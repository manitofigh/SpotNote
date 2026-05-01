import AppKit

/// Markdown-style code styling applied as `NSLayoutManager` temporary
/// attributes -- visual only, never touches the `NSTextStorage`. Key
/// properties:
///
/// - Backticks stay as literal characters in the document.
/// - Inline `` `code` `` spans get a subtle background + dimmed fences.
/// - Triple-fenced blocks are NOT background-tinted; instead the inner
///   code is tokenized via `SyntaxHighlighter` and colored per category.
///   Unrecognized languages fall back to a pan-language keyword set.
///
/// Because temporary attributes bypass `NSTextStorage.processEditing`,
/// re-applying on every keystroke doesn't invalidate the edited-range
/// layout cache -- which is what used to make the backticks flash.
enum CodeStyler {
  struct Palette {
    let codeBackground: NSColor
    let codeForeground: NSColor
    let backtickColor: NSColor
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
  }

  @MainActor
  static func apply(to textView: NSTextView, theme: Theme) {
    guard let layoutManager = textView.layoutManager else { return }
    let nsText = textView.string as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
    guard fullRange.length > 0 else { return }
    let palette = palette(for: theme)
    styleChecklist(in: nsText, fullRange: fullRange, layoutManager: layoutManager)
    let processed = styleTriples(
      in: nsText,
      fullRange: fullRange,
      layoutManager: layoutManager,
      palette: palette
    )
    styleInline(
      in: nsText,
      fullRange: fullRange,
      layoutManager: layoutManager,
      palette: palette,
      processed: processed
    )
  }

  // MARK: - Triple fences

  private static func styleTriples(
    in nsText: NSString,
    fullRange: NSRange,
    layoutManager: NSLayoutManager,
    palette: Palette
  ) -> [NSRange] {
    guard let regex = try? NSRegularExpression(pattern: "```([\\s\\S]*?)```") else { return [] }
    var processed: [NSRange] = []
    regex.enumerateMatches(in: nsText as String, range: fullRange) { match, _, _ in
      guard let match else { return }
      let outer = match.range
      let inner = match.range(at: 1)
      dimFences(outer: outer, fenceLength: 3, layoutManager: layoutManager, palette: palette)
      applySyntax(
        innerRange: inner,
        nsText: nsText,
        layoutManager: layoutManager,
        palette: palette
      )
      processed.append(outer)
    }
    return processed
  }

  private static func applySyntax(
    innerRange: NSRange,
    nsText: NSString,
    layoutManager: NSLayoutManager,
    palette: Palette
  ) {
    guard innerRange.length > 0 else { return }
    let body = nsText.substring(with: innerRange)
    let split = SyntaxHighlighter.splitLanguage(from: body)
    let codeStart = innerRange.location + (innerRange.length - (split.code as NSString).length)
    let tokens = SyntaxHighlighter.tokens(in: split.code, language: split.language)
    for token in tokens {
      let absolute = NSRange(location: codeStart + token.range.location, length: token.range.length)
      layoutManager.addTemporaryAttribute(
        .foregroundColor,
        value: color(for: token.category, palette: palette),
        forCharacterRange: absolute
      )
    }
  }

  // MARK: - Inline spans

  private static func styleInline(
    in nsText: NSString,
    fullRange: NSRange,
    layoutManager: NSLayoutManager,
    palette: Palette,
    processed: [NSRange]
  ) {
    guard let regex = try? NSRegularExpression(pattern: "`([^`\\n]+)`") else { return }
    regex.enumerateMatches(in: nsText as String, range: fullRange) { match, _, _ in
      guard let match else { return }
      let outer = match.range
      if processed.contains(where: { NSIntersectionRange($0, outer).length > 0 }) { return }
      let inner = match.range(at: 1)
      layoutManager.addTemporaryAttribute(
        .foregroundColor,
        value: palette.codeForeground,
        forCharacterRange: inner
      )
      layoutManager.addTemporaryAttribute(
        .backgroundColor,
        value: palette.codeBackground,
        forCharacterRange: inner
      )
      dimFences(outer: outer, fenceLength: 1, layoutManager: layoutManager, palette: palette)
    }
  }

  // MARK: - Helpers

  private static func dimFences(
    outer: NSRange,
    fenceLength: Int,
    layoutManager: NSLayoutManager,
    palette: Palette
  ) {
    let left = NSRange(location: outer.location, length: fenceLength)
    let right = NSRange(
      location: outer.location + outer.length - fenceLength,
      length: fenceLength
    )
    layoutManager.addTemporaryAttribute(
      .foregroundColor,
      value: palette.backtickColor,
      forCharacterRange: left
    )
    layoutManager.addTemporaryAttribute(
      .foregroundColor,
      value: palette.backtickColor,
      forCharacterRange: right
    )
  }

  private static func color(for category: SyntaxCategory, palette: Palette) -> NSColor {
    switch category {
    case .keyword: return palette.keyword
    case .string: return palette.string
    case .number: return palette.number
    case .comment: return palette.comment
    }
  }

  private static func styleChecklist(
    in nsText: NSString,
    fullRange: NSRange,
    layoutManager: NSLayoutManager
  ) {
    guard let regex = try? NSRegularExpression(pattern: #"(☐|☑)"#) else { return }
    regex.enumerateMatches(in: nsText as String, range: fullRange) { match, _, _ in
      guard let marker = match?.range(at: 1) else { return }
      // Suppress the raw Unicode glyph; PlaceholderTextView draws the
      // polished SF Symbol at the same position via its draw(_:) override.
      layoutManager.addTemporaryAttribute(
        .foregroundColor, value: NSColor.clear, forCharacterRange: marker
      )
    }
  }

  private static func palette(for theme: Theme) -> Palette {
    let base = NSColor(theme.text)
    let accent = NSColor(theme.placeholder)
    if theme.mode == .dark {
      return Palette(
        codeBackground: base.withAlphaComponent(0.08),
        codeForeground: base.withAlphaComponent(0.92),
        backtickColor: accent.withAlphaComponent(0.55),
        keyword: NSColor(red: 0.78, green: 0.52, blue: 0.86, alpha: 1.0),
        string: NSColor(red: 0.82, green: 0.63, blue: 0.56, alpha: 1.0),
        number: NSColor(red: 0.71, green: 0.81, blue: 0.63, alpha: 1.0),
        comment: NSColor(white: 0.55, alpha: 1.0)
      )
    }
    return Palette(
      codeBackground: base.withAlphaComponent(0.06),
      codeForeground: base.withAlphaComponent(0.90),
      backtickColor: accent.withAlphaComponent(0.75),
      keyword: NSColor(red: 0.49, green: 0.11, blue: 0.69, alpha: 1.0),
      string: NSColor(red: 0.64, green: 0.08, blue: 0.08, alpha: 1.0),
      number: NSColor(red: 0.04, green: 0.52, blue: 0.35, alpha: 1.0),
      comment: NSColor(white: 0.45, alpha: 1.0)
    )
  }
}
