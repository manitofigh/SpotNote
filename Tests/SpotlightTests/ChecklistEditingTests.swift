import AppKit
import Testing

@testable import Spotlight

@Suite("Checklist text helpers")
struct ChecklistTextTests {
  @Test("parses indented items and their content offset")
  func parsesItems() throws {
    let item = try #require(ChecklistText.item(in: "\t☑ done"))
    #expect(item.indentLength == 1)
    #expect(item.depth == ChecklistText.tabWidth)
    #expect(item.isChecked)
    #expect(item.contentOffset == 3)
    #expect(!item.isEmpty)
    #expect(ChecklistText.item(in: "☐ ")?.isEmpty == true)
    #expect(ChecklistText.item(in: "text ☐") == nil)
  }

  @Test("parent checks when all direct children are checked, and unchecks again")
  func parentPropagation() {
    var lines = ["☐ parent", "\t☑ a", "\t☑ b", "☐ sibling"]
    #expect(ChecklistText.parentUpdates(lines: lines, changedLine: 2) == [0: true])
    lines = ["☑ parent", "\t☑ a", "\t☐ b"]
    #expect(ChecklistText.parentUpdates(lines: lines, changedLine: 2) == [0: false])
    lines = ["☐ parent", "\t☑ a", "\t☐ b"]
    #expect(ChecklistText.parentUpdates(lines: lines, changedLine: 1).isEmpty)
  }

  @Test("propagation walks up several levels and ignores grandchildren for the parent")
  func multiLevelPropagation() {
    let lines = ["☐ root", "\t☐ mid", "\t\t☑ leaf", "\t☑ other"]
    #expect(ChecklistText.parentUpdates(lines: lines, changedLine: 2) == [1: true, 0: true])
  }

  @Test("pasteboard export/import round-trips nested checklists")
  func pasteboardRoundTrip() {
    let raw = "☐ parent\n\t☑ child\n\t☐ other\nplain [x] text"
    let exported = ChecklistText.exportForPasteboard(raw)
    #expect(exported == "[ ] parent\n\t[x] child\n\t[ ] other\nplain [x] text")
    #expect(ChecklistText.importFromPasteboard(exported) == raw)
    #expect(ChecklistText.importFromPasteboard("- [ ] md\n[x]") == "☐ md\n☑")
  }
}

@Suite("Vim text objects")
struct VimTextObjectTests {
  @Test("iw covers the word, punctuation run or blank run under the cursor")
  func innerWord() {
    let text = "foo bar_baz, qux" as NSString
    #expect(VimTextObjects.range(of: .innerWord, in: text, at: 5) == NSRange(location: 4, length: 7))
    #expect(VimTextObjects.range(of: .innerWord, in: text, at: 11) == NSRange(location: 11, length: 1))
    #expect(VimTextObjects.range(of: .innerWord, in: text, at: 3) == NSRange(location: 3, length: 1))
    #expect(VimTextObjects.range(of: .innerWord, in: "a\n\nb" as NSString, at: 2) == nil)
  }

  @Test("aw includes trailing blanks, or leading ones at line end")
  func aroundWord() {
    let text = "foo bar baz" as NSString
    #expect(VimTextObjects.range(of: .aroundWord, in: text, at: 5) == NSRange(location: 4, length: 4))
    #expect(VimTextObjects.range(of: .aroundWord, in: text, at: 9) == NSRange(location: 7, length: 4))
  }

  @Test("engine parses ciw / diw / yiw / yy / p / P and cw enters insert")
  func engineParsing() {
    let engine = VimEngine()
    _ = engine.handle(key: "c", hasModifiers: false)
    _ = engine.handle(key: "i", hasModifiers: false)
    #expect(engine.handle(key: "w", hasModifiers: false) == .changeTextObject(.innerWord))
    #expect(engine.mode == .insert)
    engine.reset()
    _ = engine.handle(key: "d", hasModifiers: false)
    _ = engine.handle(key: "a", hasModifiers: false)
    #expect(engine.handle(key: "w", hasModifiers: false) == .deleteTextObject(.aroundWord))
    _ = engine.handle(key: "y", hasModifiers: false)
    #expect(engine.handle(key: "y", hasModifiers: false) == .yankLine(count: 1))
    #expect(engine.handle(key: "p", hasModifiers: false) == .paste(after: true, count: 1))
    #expect(engine.handle(key: "P", hasModifiers: false) == .paste(after: false, count: 1))
    _ = engine.handle(key: "c", hasModifiers: false)
    #expect(engine.handle(key: "w", hasModifiers: false) == .changeMotion(.wordForward(1)))
    #expect(engine.mode == .insert)
  }
}

@MainActor
@Suite("Checklist editing in the text view", .serialized)
struct ChecklistTextViewTests {
  /// Tests that copy/yank use the real general pasteboard; put back what
  /// the developer had on it.
  private func preservingPasteboard(_ body: () -> Void) {
    let pasteboard = NSPasteboard.general
    let saved = pasteboard.string(forType: .string)
    body()
    pasteboard.clearContents()
    if let saved { pasteboard.setString(saved, forType: .string) }
  }

  @Test("o on an empty checklist item opens a line instead of deleting the item")
  func openLineBelowOnEmptyItem() {
    let view = makeTextView("☐ a\n☐ ")
    view.vimModeEnabled = true
    view.setSelectedRange(NSRange(location: 4, length: 0))
    view.executeVimAction(.openLineBelow)
    #expect(view.string == "☐ a\n☐ \n")
  }

  @Test("Shift-Tab over a whole selection keeps the selection")
  func backtabKeepsSelection() {
    let view = makeTextView("☐ p\n  ☐ a\n      ☐ b")
    view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
    view.insertBacktab(nil)
    #expect(view.string == "☐ p\n☐ a\n  ☐ b")
    #expect(view.selectedRange == NSRange(location: 0, length: 13))
  }

  @Test("diw works with the caret resting on the newline")
  func deleteInnerWordAtLineEnd() {
    let view = makeTextView("hello world\nnext")
    view.vimModeEnabled = true
    view.setSelectedRange(NSRange(location: 11, length: 0))
    view.executeVimAction(.deleteTextObject(.innerWord))
    #expect(view.string == "hello \nnext")
  }

  @Test("j on the last line and k on the first line stay put")
  func verticalMotionClampsAtEdges() {
    let view = makeTextView("abc\ndef")
    view.vimModeEnabled = true
    view.setSelectedRange(NSRange(location: 5, length: 0))
    view.executeMotion(.down(1))
    #expect(view.selectedRange.location == 5)
    view.setSelectedRange(NSRange(location: 2, length: 0))
    view.executeMotion(.up(1))
    #expect(view.selectedRange.location == 2)
  }
  @Test("Return continues a checklist at the same indentation")
  func returnContinues() {
    let view = makeTextView("\t☐ one")
    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    view.insertNewline(nil)
    #expect(view.string == "\t☐ one\n\t☐ ")
    #expect(view.selectedRange.location == (view.string as NSString).length)
  }

  @Test("Return on an empty item ends the list")
  func returnOnEmptyEnds() {
    let view = makeTextView("☐ one\n☐ ")
    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    view.insertNewline(nil)
    #expect(view.string == "☐ one\n")
  }

  @Test("Backspace after a fresh marker removes it entirely")
  func backspaceRemovesMarker() {
    let view = makeTextView("☐ one\n☐ ")
    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    view.deleteBackward(nil)
    #expect(view.string == "☐ one\n")
  }

  @Test("Backspace on the first content character deletes that character")
  func backspaceDeletesFirstCharacter() {
    let view = makeTextView("☐ abc")
    view.setSelectedRange(NSRange(location: 3, length: 0))
    view.deleteBackward(nil)
    #expect(view.string == "☐ bc")
    #expect(view.selectedRange.location == 2)
  }

  @Test("Tab indents and Shift-Tab outdents a checklist line from anywhere on it")
  func tabIndents() {
    let view = makeTextView("☐ one")
    view.setSelectedRange(NSRange(location: 4, length: 0))
    view.insertTab(nil)
    #expect(view.string == "\t☐ one")
    #expect(view.selectedRange.location == 5)
    view.insertBacktab(nil)
    #expect(view.string == "☐ one")
    #expect(view.selectedRange.location == 4)
  }

  @Test("Tab on plain text still inserts a tab")
  func tabOnPlainText() {
    let view = makeTextView("ab")
    view.setSelectedRange(NSRange(location: 1, length: 0))
    view.insertTab(nil)
    #expect(view.string == "a\tb")
  }

  @Test("toggling the last child checks the parent")
  func toggleChecksParent() {
    let view = makeTextView("☐ parent\n\t☑ a\n\t☐ b")
    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    view.toggleChecklistShortcut(nil)
    #expect(view.string == "☑ parent\n\t☑ a\n\t☑ b")
    view.toggleChecklistShortcut(nil)
    #expect(view.string == "☐ parent\n\t☑ a\n\t☐ b")
  }

  @Test("copy then paste keeps every nesting level rendered")
  func copyPasteRoundTrip() {
    preservingPasteboard {
      let source = "☐ parent\n\t☑ child"
      let view = makeTextView(source)
      view.setSelectedRange(NSRange(location: 0, length: (source as NSString).length))
      view.copy(nil)
      view.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
      view.insertText("\n", replacementRange: view.selectedRange)
      view.paste(nil)
      #expect(view.string == source + "\n" + source)
    }
  }

  @Test("visual-line yank then p puts checklist lines below")
  func visualYankAndPut() {
    preservingPasteboard {
      let view = makeTextView("☐ one\n\t☑ two\nend")
      view.vimModeEnabled = true
      view.setSelectedRange(NSRange(location: 0, length: 0))
      view.executeVimAction(.enterVisualLine)
      view.executeVimAction(.extendVisualLine(.down(1)))
      view.executeVimAction(.yankVisualLine)
      view.executeVimAction(.moveCursor(.documentEnd))
      view.executeVimAction(.paste(after: true, count: 1))
      #expect(view.string == "☐ one\n\t☑ two\nend\n☐ one\n\t☑ two")
    }
  }

  @Test("ciw replaces the word under the caret")
  func changeInnerWord() {
    let view = makeTextView("hello brave world")
    view.vimModeEnabled = true
    view.setSelectedRange(NSRange(location: 8, length: 0))
    view.executeVimAction(.changeTextObject(.innerWord))
    #expect(view.string == "hello  world")
    #expect(view.selectedRange.location == 6)
  }

  private func makeTextView(_ text: String) -> PlaceholderTextView {
    let view = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 240))
    view.font = .systemFont(ofSize: EditorMetrics.fontSize)
    view.string = text
    return view
  }
}
