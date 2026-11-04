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

  @Test("normal mode j and k follow soft-wrapped visual rows")
  func verticalMotionsFollowSoftWraps() {
    let textView = makeVimMotionTextView(
      text: "abcdefghijklmnop qrstuvwxyz",
      width: 58
    )
    textView.vimModeEnabled = true
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    let firstRow = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )

    textView.executeMotion(.down(1))
    let secondRow = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )
    #expect(secondRow.origin.y > firstRow.origin.y)

    textView.executeMotion(.up(1))
    let returnedRow = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )
    #expect(returnedRow.origin.y == firstRow.origin.y)
  }

  @Test("insertion caret width stays stable across layout-provided widths")
  func insertionCaretWidthIsStable() {
    let textView = makeVimMotionTextView(text: "caret width")
    let narrow = textView.insertionPointDisplayRect(
      for: NSRect(x: 0, y: 0, width: 0.5, height: EditorMetrics.lineHeight),
      turnedOn: true
    )
    let wide = textView.insertionPointDisplayRect(
      for: NSRect(x: 0, y: 0, width: 2, height: EditorMetrics.lineHeight),
      turnedOn: true
    )

    #expect(narrow.width == wide.width)
    #expect(narrow.width == 1)
  }

  @Test("caret stays visible when a move lands during the hidden blink phase")
  func caretMovementForcesVisibleInsertionPoint() {
    let textView = makeVimMotionTextView(text: "old caret\nnew caret")
    textView.setSelectedRange(NSRange(location: 3, length: 0))

    let painted = textView.insertionPointDisplayRect(
      for: NSRect(x: 30, y: 0, width: 1, height: EditorMetrics.lineHeight),
      turnedOn: true
    )
    let image = NSImage(size: NSSize(width: 240, height: 80))
    image.lockFocus()
    defer { image.unlockFocus() }
    textView.drawInsertionPoint(in: painted, color: .labelColor, turnedOn: true)

    textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    let moved = NSRect(
      x: 160,
      y: EditorMetrics.lineHeight,
      width: 1,
      height: EditorMetrics.lineHeight
    )
    textView.drawInsertionPoint(in: moved, color: .labelColor, turnedOn: false)

    let visible = textView.insertionPointDisplayRect(for: moved, turnedOn: false)
    let expected = textView.insertionPointDisplayRect(for: moved, turnedOn: true)
    #expect(visible == expected)
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

  @Test("j and G reveal caret positions below the visible viewport")
  func motionsRevealCaret() {
    let lines = (1...30).map { "line \($0)" }
    let textView = makeVimMotionTextView(text: lines.joined(separator: "\n"))
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: EditorMetrics.lineHeight * 3))
    scrollView.hasVerticalScroller = true
    scrollView.documentView = textView
    textView.frame = NSRect(
      x: 0,
      y: 0,
      width: 320,
      height: EditorMetrics.lineHeight * CGFloat(lines.count)
    )
    textView.setSelectedRange(NSRange(location: 0, length: 0))

    textView.executeMotion(.down(10))
    let afterDown = scrollView.contentView.bounds.origin.y
    textView.executeMotion(.documentEnd)

    #expect(afterDown > 0)
    #expect(scrollView.contentView.bounds.origin.y > afterDown)
    #expect(textView.selectedRange.location == (textView.string as NSString).length)
  }

  @Test("caret at a soft-wrap boundary uses the new visual fragment")
  func caretAtSoftWrapBoundary() throws {
    let textView = makeVimMotionTextView(
      text: "abcdefghijklmnop qrstuvwxyz",
      width: 58
    )
    guard let layoutManager = textView.layoutManager,
      let textContainer = textView.textContainer
    else { return }
    layoutManager.ensureLayout(for: textContainer)

    let nsText = textView.string as NSString
    var wrapCursor: Int?
    for cursor in 1..<nsText.length {
      let previous = layoutManager.glyphIndexForCharacter(at: cursor - 1)
      let next = layoutManager.glyphIndexForCharacter(at: cursor)
      let previousFragment = layoutManager.lineFragmentRect(
        forGlyphAt: previous,
        effectiveRange: nil
      )
      let nextFragment = layoutManager.lineFragmentRect(forGlyphAt: next, effectiveRange: nil)
      if nextFragment.origin.y > previousFragment.origin.y + 0.5 {
        wrapCursor = cursor
        break
      }
    }
    let cursor = try #require(wrapCursor)
    let nextGlyph = layoutManager.glyphIndexForCharacter(at: cursor)
    let nextFragment = layoutManager.lineFragmentRect(forGlyphAt: nextGlyph, effectiveRange: nil)
    textView.setSelectedRange(NSRange(location: cursor, length: 0))

    let rect = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )
    #expect(abs(rect.origin.x - (textView.textContainerOrigin.x + nextFragment.minX)) < 0.01)
    #expect(abs(rect.origin.y - (textView.textContainerOrigin.y + nextFragment.minY)) < 0.01)
  }

  @Test("caret after trailing spaces uses the newline insertion advance")
  func caretAfterTrailingSpaces() {
    let textView = makeVimMotionTextView(text: "abc   \nnext", width: 320)
    let cursor = ("abc   " as NSString).length
    textView.setSelectedRange(NSRange(location: cursor, length: 0))
    guard let layoutManager = textView.layoutManager,
      let textContainer = textView.textContainer
    else { return }
    layoutManager.ensureLayout(for: textContainer)

    let newlineGlyph = layoutManager.glyphIndexForCharacter(at: cursor)
    let fragment = layoutManager.lineFragmentRect(forGlyphAt: newlineGlyph, effectiveRange: nil)
    let expectedX =
      textView.textContainerOrigin.x
      + fragment.minX
      + layoutManager.location(forGlyphAt: newlineGlyph).x
    let rect = textView.normalizedInsertionPointRect(
      NSRect(x: 0, y: 0, width: 1, height: EditorMetrics.lineHeight)
    )

    #expect(abs(rect.origin.x - expectedX) < 0.01)
    #expect(abs(rect.origin.y - (textView.textContainerOrigin.y + fragment.minY)) < 0.01)
  }

  @Test("Command-Right reaches the end from a line start in Vim insert mode")
  func commandRightFromLineStartInVimInsertMode() {
    let textView = makeVimMotionTextView(text: "first line\nsecond line\nthird line")
    textView.vimModeEnabled = true
    _ = textView.vimEngine?.handle(key: "i", hasModifiers: false)
    let lineStart = ("first line\n" as NSString).length
    textView.setSelectedRange(NSRange(location: lineStart, length: 0))

    pressCommandRight(in: textView)

    #expect(textView.selectedRange.location == ("first line\nsecond line" as NSString).length)
  }

  @Test("Command-Right reaches the end from a line start without Vim")
  func commandRightFromLineStartWithoutVim() {
    let textView = makeVimMotionTextView(text: "first line\nsecond line\nthird line")
    let lineStart = ("first line\n" as NSString).length
    textView.setSelectedRange(NSRange(location: lineStart, length: 0))

    pressCommandRight(in: textView)

    #expect(textView.selectedRange.location == ("first line\nsecond line" as NSString).length)
  }

  private func makeVimMotionTextView(
    text: String,
    width: CGFloat = EditorMetrics.panelWidth
  ) -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: width, height: 240))
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

@MainActor
private func pressCommandRight(in textView: PlaceholderTextView) {
  guard
    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: .command,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "→",
      charactersIgnoringModifiers: "→",
      isARepeat: false,
      keyCode: 124
    )
  else { return }
  textView.keyDown(with: event)
}
