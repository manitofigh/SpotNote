import AppKit
import Testing

@testable import Spotlight

@MainActor
@Suite("Multiline editor undo")
struct MultilineEditorUndoTests {
  @Test("text undo keeps unlimited history and Vim uses the same stack")
  func textUndoIsSharedWithVim() {
    let textView = PlaceholderTextView(
      frame: NSRect(x: 0, y: 0, width: EditorMetrics.panelWidth, height: 200)
    )
    textView.allowsUndo = true
    textView.undoManager?.levelsOfUndo = 0
    textView.undoManager?.groupsByEvent = true

    textView.insertText("a", replacementRange: NSRange(location: 0, length: 0))
    #expect(textView.string == "a")
    pressCommandZForUndo(in: textView)
    #expect(textView.string.isEmpty)

    textView.insertText("b", replacementRange: NSRange(location: 0, length: 0))
    textView.vimModeEnabled = true
    pressVimUndoForUndo(in: textView)
    #expect(textView.string.isEmpty)
  }
}

@MainActor
private func pressCommandZForUndo(in textView: PlaceholderTextView) {
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
private func pressVimUndoForUndo(in textView: PlaceholderTextView) {
  guard
    let event = NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "u",
      charactersIgnoringModifiers: "u",
      isARepeat: false,
      keyCode: 32
    )
  else { return }
  textView.keyDown(with: event)
}
