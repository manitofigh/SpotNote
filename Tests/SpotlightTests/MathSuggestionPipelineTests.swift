import AppKit
import SwiftUI
import Testing

@testable import Spotlight

/// Integration tests for the inline-math suggestion pipeline. The unit
/// tests in `MathSuggesterTests` cover the parser in isolation; these
/// exercise `MultilineEditor.refreshSuggestion(on:)` end-to-end, which
/// is where an earlier regression hid: the parser returned the right
/// answer but the ghost field's positioning logic rejected every
/// zero-length caret range and hid the suggestion.
@Suite("Math suggestion pipeline")
@MainActor
struct MathSuggestionPipelineTests {
  private func makeHarness(text: String, cursor: Int) -> (MultilineEditor, PlaceholderTextView) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    textView.font = .systemFont(ofSize: 14)
    textView.string = text
    textView.setSelectedRange(NSRange(location: cursor, length: 0))
    let field = SuggestionView()
    textView.addSubview(field)
    textView.suggestionField = field
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    window.contentView?.addSubview(textView)
    let editor = MultilineEditor(
      text: .constant(text),
      theme: ThemeCatalog.obsidian,
      placeholder: "",
      showLineNumbers: false,
      font: .systemFont(ofSize: 14),
      focusRequest: 0,
      maxVisibleLines: 10,
      extraChromeHeight: 0,
      onHeightChange: { _ in }
    )
    return (editor, textView)
  }

  @Test("pendingSuggestion is set when the caret sits at end of a complete expression")
  func suggestionShowsAtEndOfExpression() {
    let (editor, textView) = makeHarness(text: "5+3", cursor: 3)
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == "8")
    #expect(textView.suggestionField?.isHidden == false)
  }

  @Test("suggestion field is positioned to the right of the caret, not at the origin")
  func suggestionFieldPositionedPastCaret() {
    let (editor, textView) = makeHarness(text: "12 + 4", cursor: 6)
    editor.refreshSuggestion(on: textView)
    let frame = try? #require(textView.suggestionField?.frame)
    // The regression surfaced as a frame pinned to (0, 0) because
    // `firstRect(forCharacterRange:)` returned `.zero` for the empty
    // range at end-of-text. Any caret past column 0 must produce a
    // positive X.
    #expect((frame?.origin.x ?? 0) > 0)
    #expect((frame?.size.width ?? 0) > 0)
  }

  @Test("typing a fresh expression from empty state produces a suggestion")
  func suggestionAppearsFromEmptyStart() {
    let (editor, textView) = makeHarness(text: "1+2", cursor: 3)
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == "3")
  }

  @Test("suggestion hides when the cursor is not at end-of-line")
  func suggestionHidesMidLine() {
    let (editor, textView) = makeHarness(text: "5+3 tail", cursor: 3)
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == nil)
    #expect(textView.suggestionField?.isHidden == true)
  }

  @Test("suggestion hides when the trailing expression is incomplete")
  func suggestionHidesForIncompleteExpression() {
    let (editor, textView) = makeHarness(text: "5 + ", cursor: 4)
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == nil)
  }

  @Test("hex expression at end-of-text exposes a hex-formatted pendingSuggestion")
  func hexPipeline() {
    let (editor, textView) = makeHarness(text: "0x10 + 1", cursor: 8)
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == "0x11")
  }

  // MARK: - Regression guards

  @Test("suggestion survives a redundant refreshSuggestion call")
  func doubleRefreshKeepsSuggestion() {
    let (editor, textView) = makeHarness(text: "10 + 5", cursor: 6)
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == "15")
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == "15")
    #expect(textView.suggestionField?.isHidden == false)
  }

  @Test("suggestion appears after cursor moves to end of expression")
  func cursorMoveToEnd() {
    let text = "2 * 3"
    let (editor, textView) = makeHarness(text: text, cursor: 0)
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == nil)
    textView.setSelectedRange(NSRange(location: 5, length: 0))
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == "6")
  }

  @Test("suggestion clears when a selection is active")
  func selectionClearsSuggestion() {
    let (editor, textView) = makeHarness(text: "3 + 3", cursor: 5)
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == "6")
    textView.setSelectedRange(NSRange(location: 0, length: 5))
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == nil)
    #expect(textView.suggestionField?.isHidden == true)
  }

  @Test("multiline: suggestion on second line with cursor at its end")
  func multilineSecondLine() {
    let text = "hello\n7 + 8"
    let cursor = (text as NSString).length
    let (editor, textView) = makeHarness(text: text, cursor: cursor)
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == "15")
  }

  @Test("suggestion field x position advances with longer expressions")
  func fieldXGrowsWithExpression() {
    let (editorShort, tvShort) = makeHarness(text: "1+2", cursor: 3)
    editorShort.refreshSuggestion(on: tvShort)
    let xShort = tvShort.suggestionField?.frame.origin.x ?? 0

    let (editorLong, tvLong) = makeHarness(text: "100000 + 200000", cursor: 15)
    editorLong.refreshSuggestion(on: tvLong)
    let xLong = tvLong.suggestionField?.frame.origin.x ?? 0

    #expect(xLong > xShort)
  }

  @Test("suggestion updates when text changes from one expression to another")
  func textChangeUpdatesSuggestion() {
    let (editor, textView) = makeHarness(text: "2 + 2", cursor: 5)
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == "4")
    textView.string = "3 * 3"
    textView.setSelectedRange(NSRange(location: 5, length: 0))
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == "9")
  }

  @Test("suggestion hides on empty text")
  func emptyTextHidesSuggestion() {
    let (editor, textView) = makeHarness(text: "", cursor: 0)
    editor.refreshSuggestion(on: textView)
    #expect(textView.pendingSuggestion == nil)
    #expect(textView.suggestionField?.isHidden == true)
  }
}
