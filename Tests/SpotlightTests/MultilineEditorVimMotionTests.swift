import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor vim logical line motions")
struct MultilineEditorVimLogicalLineMotionTests {
  @Test("j steps one logical line at a time over checklist markers")
  func downOverChecklistMarkers() {
    let textView = makeVimMotionTextView(text: "plain\n☐ one\n☐ two\n☑ three\nafter")
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.executeMotion(.down(1))
    #expect(textView.selectedRange.location == ("plain\n" as NSString).length)

    textView.executeMotion(.down(1))
    #expect(textView.selectedRange.location == ("plain\n☐ one\n" as NSString).length)
  }

  @Test("j and k step through fenced code block lines")
  func verticalMotionsOverFencedCodeBlock() {
    let textView = makeVimMotionTextView(text: "before\n```swift\nlet x = 1\nlet y = 2\n```\nafter")
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.executeMotion(.down(3))
    #expect(textView.selectedRange.location == ("before\n```swift\nlet x = 1\n" as NSString).length)

    textView.executeMotion(.up(1))
    #expect(textView.selectedRange.location == ("before\n```swift\n" as NSString).length)
  }

  @Test("normal mode caret at code block line start uses that line fragment")
  func lineStartCaretRectInsideCodeBlock() {
    let textView = makeVimMotionTextView(text: "before\n```cpp\nint x;\nint y;\n```\nafter")
    let lineStart = ("before\n```cpp\n" as NSString).length
    textView.setSelectedRange(NSRange(location: lineStart, length: 0))

    let rect = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )

    #expect(rect.origin.y == EditorMetrics.lineHeight * 2)
  }

  @Test("insert caret at closing fence end keeps the fence column")
  func closingFenceEndCaretRectKeepsXPosition() {
    let textView = makeVimMotionTextView(text: "before\n```cpp\nint x;\n```\nafter")
    let fenceEnd = ("before\n```cpp\nint x;\n```" as NSString).length
    textView.setSelectedRange(NSRange(location: fenceEnd, length: 0))

    let rect = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )

    #expect(rect.origin.y == EditorMetrics.lineHeight * 3)
    #expect(rect.origin.x > 1)
  }

  @Test("trailing newline caret still uses the extra line fragment")
  func trailingNewlineCaretRectUsesExtraLineFragment() {
    let textView = makeVimMotionTextView(text: "before\n")
    textView.setSelectedRange(NSRange(location: ("before\n" as NSString).length, length: 0))

    let rect = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )

    #expect(rect.origin.y == EditorMetrics.lineHeight)
  }

  private func makeVimMotionTextView(text: String) -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 240))
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    textView.string = text
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    guard let storage = textView.textStorage,
      let container = textView.textContainer
    else { return textView }
    let fixed = FixedLineHeightLayoutManager()
    fixed.fixedLineHeight = EditorMetrics.lineHeight
    fixed.editorFont = textView.font ?? .systemFont(ofSize: EditorMetrics.fontSize)
    if let existing = storage.layoutManagers.first {
      storage.removeLayoutManager(existing)
    }
    storage.addLayoutManager(fixed)
    fixed.addTextContainer(container)
    CodeStyler.apply(to: textView, theme: ThemeCatalog.obsidian)
    return textView
  }
}
