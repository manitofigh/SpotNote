import AppKit
import SwiftUI
import Testing

@testable import Spotlight

/// The vertical ruler sits over the clip view as a left content inset, so
/// the document must start right of the gutter and have no horizontal
/// slack -- otherwise the clip view can scroll the text, and the caret on
/// an empty line, under the line numbers until a keystroke scrolls back.
@Suite("Editor gutter layout")
@MainActor
struct EditorGutterLayoutTests {
  @Test(
    "caret stays right of the gutter after toggling wrap, before and after a keystroke",
    arguments: [
      "first line\n\nlast line",
      "first line\n"
    ]
  )
  func caretStaysRightOfGutterAfterWrapToggle(text: String) throws {
    let harness = EditorHarness(text: text)
    harness.render(wrapLines: false)
    harness.render(wrapLines: true)
    let textView = try #require(harness.textView)
    let scroll = try #require(textView.enclosingScrollView)
    let ruler = try #require(scroll.verticalRulerView)
    let emptyLine = (text as NSString).range(of: "\n\n").location
    textView.setSelectedRange(
      NSRange(location: emptyLine == NSNotFound ? (text as NSString).length : emptyLine + 1, length: 0)
    )

    let caretBefore = harness.caretMinX(in: scroll)
    let leadingEdgeBefore = textView.convert(NSPoint.zero, to: scroll).x
    #expect(leadingEdgeBefore == ruler.frame.maxX)
    #expect(caretBefore > ruler.frame.maxX)

    textView.insertText("x", replacementRange: textView.selectedRange())
    textView.setSelectedRange(NSRange(location: textView.selectedRange().location - 1, length: 0))

    #expect(textView.convert(NSPoint.zero, to: scroll).x == leadingEdgeBefore)
    #expect(harness.caretMinX(in: scroll) == caretBefore)
  }
}

@MainActor
private final class EditorHarness {
  private var text: String
  private let host: NSHostingView<MultilineEditor>
  private let window: NSWindow

  init(text: String) {
    self.text = text
    host = NSHostingView(rootView: Self.editor(text: .constant(text), wrapLines: true))
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    render(wrapLines: true)
  }

  var textView: PlaceholderTextView? { Self.find(in: host) }

  func render(wrapLines: Bool) {
    let binding = Binding(get: { self.text }, set: { self.text = $0 })
    host.rootView = Self.editor(text: binding, wrapLines: wrapLines)
    host.layoutSubtreeIfNeeded()
  }

  func caretMinX(in view: NSView) -> CGFloat {
    guard let textView else { return .nan }
    let caret = textView.insertionPointDisplayRect(for: .zero, turnedOn: true)
    return textView.convert(caret, to: view).minX
  }

  private static func editor(text: Binding<String>, wrapLines: Bool) -> MultilineEditor {
    MultilineEditor(
      text: text,
      theme: ThemeCatalog.obsidian,
      placeholder: "",
      showLineNumbers: true,
      font: .systemFont(ofSize: EditorMetrics.fontSize),
      focusRequest: 0,
      maxVisibleLines: 6,
      extraChromeHeight: 0,
      wrapLines: wrapLines,
      onHeightChange: { _ in }
    )
  }

  private static func find(in view: NSView) -> PlaceholderTextView? {
    if let textView = view as? PlaceholderTextView { return textView }
    return view.subviews.lazy.compactMap { find(in: $0) }.first
  }
}
