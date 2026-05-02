import AppKit
import SwiftUI
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor token replacement")
struct MultilineEditorTokenTests {
  @Test("return after @today normalization updates binding and grows to two rows")
  func returnAfterTodayNormalizationUpdatesHeight() {
    var boundText = ""
    var heights: [CGFloat] = []
    let parent = MultilineEditor(
      text: Binding(
        get: { boundText },
        set: { boundText = $0 }
      ),
      theme: ThemeCatalog.obsidian,
      placeholder: "",
      showLineNumbers: false,
      font: .systemFont(ofSize: EditorMetrics.fontSize),
      focusRequest: 0,
      maxVisibleLines: 4,
      extraChromeHeight: 0,
      onHeightChange: { heights.append($0) }
    )
    let coordinator = MultilineEditor.Coordinator(parent)
    let textView = makeTextView()

    insert("@today", into: textView)
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    #expect(boundText.matchesDateLine)

    let date = boundText
    insert("\n", into: textView)
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

    #expect(boundText == "\(date)\n")
    #expect(heights.last == EditorMetrics.panelHeight(forLines: 2, maxLines: 4))
  }

  @Test("return after @cl normalization updates binding and grows to two rows")
  func returnAfterChecklistNormalizationUpdatesHeight() {
    var boundText = ""
    var heights: [CGFloat] = []
    let parent = MultilineEditor(
      text: Binding(
        get: { boundText },
        set: { boundText = $0 }
      ),
      theme: ThemeCatalog.obsidian,
      placeholder: "",
      showLineNumbers: false,
      font: .systemFont(ofSize: EditorMetrics.fontSize),
      focusRequest: 0,
      maxVisibleLines: 4,
      extraChromeHeight: 0,
      onHeightChange: { heights.append($0) }
    )
    let coordinator = MultilineEditor.Coordinator(parent)
    let textView = makeTextView()

    insert("@cl", into: textView)
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    #expect(boundText == "☐")

    insert("\n", into: textView)
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

    #expect(boundText == "☐\n")
    #expect(heights.last == EditorMetrics.panelHeight(forLines: 2, maxLines: 4))
  }

  @Test("@today renders at the token location instead of moving to the first line")
  func todayRendersInPlace() {
    let context = makeEditorContext(initialText: "first line\n")

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    let parts = context.boundText().components(separatedBy: "\n")
    #expect(parts.count == 2)
    #expect(parts.first == "first line")
    #expect(parts.last?.matchesDateLine == true)
  }

  @Test("cmd+z after @today rendering restores literal and suppresses immediate re-render")
  func commandZAfterTodayRenderingRestoresLiteral() throws {
    let context = makeEditorContext()

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    pressCommandZ(in: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "@today")

    insert("!", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "@today!")
  }

  @Test("backspace after @cl rendering restores markdown literal and suppresses immediate re-render")
  func backspaceAfterChecklistRenderingRestoresLiteral() throws {
    let context = makeEditorContext()

    insert("@cl", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    pressBackspace(in: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "[ ]")

    insert(" item", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "[ ] item")
  }

  @Test("cmd+z after @cl rendering restores markdown literal")
  func commandZAfterChecklistRenderingRestoresMarkdownLiteral() throws {
    let context = makeEditorContext()

    insert("@cl", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    pressCommandZ(in: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "[ ]")
  }

  @Test("direct undo after @cl rendering restores markdown literal")
  func directUndoAfterChecklistRenderingRestoresMarkdownLiteral() throws {
    let context = makeEditorContext()

    insert("@cl", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    _ = context.textView.tryToPerform(Selector(("undo:")), with: nil)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "[ ]")
  }

  @Test("backspace after @today rendering reverts even if AppKit leaves caret at original token end")
  func backspaceAfterTodayRenderingWithOriginalCaretPositionRestoresLiteral() throws {
    let context = makeEditorContext()

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    context.textView.setSelectedRange(NSRange(location: ("@today" as NSString).length, length: 0))
    pressBackspace(in: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "@today")
  }

  @Test("direct deleteBackward after @today rendering restores literal")
  func directDeleteBackwardAfterTodayRenderingRestoresLiteral() throws {
    let context = makeEditorContext()

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    context.textView.deleteBackward(nil)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText() == "@today")
  }

  @Test("delegate notification during @today revert does not immediately re-render")
  func delegateNotificationDuringTodayRevertDoesNotRerender() throws {
    let context = makeEditorContext(connectDelegate: true)

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    context.textView.deleteBackward(nil)

    #expect(context.boundText() == "@today")
    #expect(context.textView.selectedRange.location == ("@today" as NSString).length)
  }

  @Test("deleting and retyping a restored token renders it again")
  func deletingAndRetypingRestoredTokenRendersAgain() throws {
    let context = makeEditorContext()

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    pressCommandZ(in: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))
    replace(
      range: NSRange(location: 0, length: (context.boundText() as NSString).length),
      with: "",
      in: context.textView
    )
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    insert("@today", into: context.textView)
    context.coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: context.textView))

    #expect(context.boundText().matchesDateLine)
  }

  private struct EditorContext {
    let coordinator: MultilineEditor.Coordinator
    let textView: PlaceholderTextView
    let boundText: () -> String
  }

  private func makeEditorContext(initialText: String = "", connectDelegate: Bool = false) -> EditorContext {
    var boundText = initialText
    var heights: [CGFloat] = []
    let parent = MultilineEditor(
      text: Binding(
        get: { boundText },
        set: { boundText = $0 }
      ),
      theme: ThemeCatalog.obsidian,
      placeholder: "",
      showLineNumbers: false,
      font: .systemFont(ofSize: EditorMetrics.fontSize),
      focusRequest: 0,
      maxVisibleLines: 4,
      extraChromeHeight: 0,
      onHeightChange: { heights.append($0) }
    )
    let textView = makeTextView()
    textView.string = initialText
    textView.setSelectedRange(NSRange(location: (initialText as NSString).length, length: 0))
    let coordinator = MultilineEditor.Coordinator(parent)
    if connectDelegate {
      textView.delegate = coordinator
    }
    return EditorContext(
      coordinator: coordinator,
      textView: textView,
      boundText: { boundText }
    )
  }

  private func makeTextView() -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 200))
    textView.font = .systemFont(ofSize: EditorMetrics.fontSize)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.minimumLineHeight = EditorMetrics.lineHeight
    paragraphStyle.maximumLineHeight = EditorMetrics.lineHeight
    textView.defaultParagraphStyle = paragraphStyle
    textView.editorTextAttributes = [
      .font: textView.font ?? NSFont.systemFont(ofSize: EditorMetrics.fontSize),
      .paragraphStyle: paragraphStyle
    ]
    textView.typingAttributes = textView.editorTextAttributes
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
    return textView
  }

  private func insert(_ replacement: String, into textView: PlaceholderTextView) {
    let range = textView.selectedRange
    replace(range: range, with: replacement, in: textView)
  }

  private func replace(range: NSRange, with replacement: String, in textView: PlaceholderTextView) {
    _ = textView.shouldChangeText(in: range, replacementString: replacement)
    let nsString = textView.string as NSString
    textView.string = nsString.replacingCharacters(in: range, with: replacement)
    textView.setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
  }

}

@MainActor
private func pressCommandZ(in textView: PlaceholderTextView) {
  guard
    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: .command,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "z",
      charactersIgnoringModifiers: "z",
      isARepeat: false,
      keyCode: 6
    )
  else { return }
  textView.keyDown(with: event)
}

@MainActor
private func pressBackspace(in textView: PlaceholderTextView) {
  guard
    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "\u{7F}",
      charactersIgnoringModifiers: "\u{7F}",
      isARepeat: false,
      keyCode: 51
    )
  else { return }
  textView.keyDown(with: event)
}

@MainActor
@Suite("Multiline editor embedded checklist toggles")
struct MultilineEditorChecklistToggleTests {
  @Test("shortcut toggles checklist marker in the middle of a line")
  func shortcutTogglesEmbeddedChecklistMarker() {
    let textView = makeChecklistTextView(text: "prefix ☐ cursor placement")
    textView.setSelectedRange(NSRange(location: ("prefix ☐" as NSString).length, length: 0))

    textView.toggleChecklistShortcut(nil)

    #expect(textView.string == "prefix ☑ cursor placement")
  }

  @Test("click toggles checklist marker in the middle of a line")
  func clickTogglesEmbeddedChecklistMarker() throws {
    let textView = makeChecklistTextView(text: "prefix ☐ cursor placement")
    let markerLocation = ("prefix " as NSString).length

    try clickCharacter(at: markerLocation, in: textView)

    #expect(textView.string == "prefix ☑ cursor placement")
  }

  private func makeChecklistTextView(text: String) -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 200))
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
    return textView
  }

  private func clickCharacter(at location: Int, in textView: PlaceholderTextView) throws {
    guard let layoutManager = textView.layoutManager,
      let textContainer = textView.textContainer
    else { return }
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 240),
      styleMask: [],
      backing: .buffered,
      defer: false
    )
    window.contentView = textView
    textView.frame = window.contentView?.bounds ?? textView.frame
    layoutManager.ensureLayout(for: textContainer)
    let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
    let glyphRect = layoutManager.boundingRect(
      forGlyphRange: NSRange(location: glyphIndex, length: 1),
      in: textContainer
    )
    let point = NSPoint(
      x: textView.textContainerOrigin.x + glyphRect.midX,
      y: textView.textContainerOrigin.y + glyphRect.midY
    )
    let event = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: textView.convert(point, to: nil),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 1
      )
    )
    textView.mouseDown(with: event)
  }
}
