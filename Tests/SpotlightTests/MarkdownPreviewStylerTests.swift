import AppKit
import Testing

@testable import Spotlight

@Suite("MarkdownPreviewStyler")
@MainActor
struct MarkdownPreviewStylerTests {
  private let font = NSFont.systemFont(ofSize: EditorMetrics.fontSize)

  private func makeTextView(_ text: String) -> (PlaceholderTextView, FixedLineHeightLayoutManager) {
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    let layoutManager = FixedLineHeightLayoutManager()
    layoutManager.delegate = layoutManager
    if let storage = textView.textStorage, let container = textView.textContainer {
      storage.layoutManagers.forEach(storage.removeLayoutManager)
      storage.addLayoutManager(layoutManager)
      layoutManager.addTextContainer(container)
    }
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = EditorMetrics.lineHeight
    style.maximumLineHeight = EditorMetrics.lineHeight
    textView.textStorage?.setAttributedString(
      NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
    )
    return (textView, layoutManager)
  }

  private func isHidden(_ layoutManager: NSLayoutManager, character: Int) -> Bool {
    let glyph = layoutManager.glyphIndexForCharacter(at: character)
    return layoutManager.propertyForGlyph(at: glyph).contains(.null)
  }

  @Test("markers are hidden off the caret line and shown on it")
  func revealFollowsCaret() {
    let (textView, layoutManager) = makeTextView("**a**\n**b**")
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    _ = MarkdownPreviewStyler.apply(to: textView, theme: ThemeCatalog.obsidian, baseFont: font)
    #expect(!isHidden(layoutManager, character: 0))
    #expect(isHidden(layoutManager, character: 6))

    textView.setSelectedRange(NSRange(location: 8, length: 0))
    _ = MarkdownPreviewStyler.revealSelection(in: textView)
    #expect(isHidden(layoutManager, character: 0))
    #expect(!isHidden(layoutManager, character: 6))
  }

  @Test("every line fragment keeps the fixed line height with headings and bold")
  func fixedLineHeight() {
    let (textView, layoutManager) = makeTextView("# Heading\n**bold** and *it*\n> quote")
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    _ = MarkdownPreviewStyler.apply(to: textView, theme: ThemeCatalog.obsidian, baseFont: font)
    layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: textView.string.utf16.count))
    var heights: [CGFloat] = []
    layoutManager.enumerateLineFragments(
      forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
    ) { rect, _, _, _, _ in heights.append(rect.height) }
    #expect(!heights.isEmpty)
    #expect(heights.allSatisfy { $0 == EditorMetrics.lineHeight })
  }

  @Test("styling registers no undo and leaves the text untouched")
  func noUndoNoTextChange() {
    let original = "**a** [l](u)"
    let (textView, _) = makeTextView(original)
    textView.undoManager?.removeAllActions()
    _ = MarkdownPreviewStyler.apply(to: textView, theme: ThemeCatalog.obsidian, baseFont: font)
    #expect(textView.string == original)
    #expect(textView.undoManager?.canUndo == false)
  }

  @Test("re-applying to an unchanged document changes nothing")
  func idempotent() {
    let (textView, _) = makeTextView("**a**\nplain")
    _ = MarkdownPreviewStyler.apply(to: textView, theme: ThemeCatalog.obsidian, baseFont: font)
    #expect(!MarkdownPreviewStyler.apply(to: textView, theme: ThemeCatalog.obsidian, baseFont: font))
  }

  @Test("a caret move within the same line does no work")
  func sameLineMoveIsNoOp() {
    let (textView, _) = makeTextView("**a** b\nc")
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    _ = MarkdownPreviewStyler.apply(to: textView, theme: ThemeCatalog.obsidian, baseFont: font)
    let before = textView.markdownPreview.revealed
    textView.setSelectedRange(NSRange(location: 3, length: 0))
    #expect(!MarkdownPreviewStyler.revealSelection(in: textView))
    #expect(textView.markdownPreview.revealed == before)
  }

  @Test("tear-down restores the base font and shows every marker")
  func tearDown() {
    let (textView, layoutManager) = makeTextView("x\n**bold**")
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    _ = MarkdownPreviewStyler.apply(to: textView, theme: ThemeCatalog.obsidian, baseFont: font)
    #expect(isHidden(layoutManager, character: 2))
    _ = MarkdownPreviewStyler.tearDown(textView, baseFont: font)
    #expect(!isHidden(layoutManager, character: 2))
    #expect(textView.textStorage?.attribute(.font, at: 4, effectiveRange: nil) as? NSFont == font)
    #expect(!textView.markdownPreview.isActive)
  }
}
