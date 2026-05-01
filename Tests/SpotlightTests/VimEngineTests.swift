// swiftlint:disable type_body_length
import Testing

@testable import Spotlight

@Suite("VimEngine")
struct VimEngineTests {

  // MARK: - Mode transitions

  @Test("starts in normal mode")
  func startsNormal() {
    let engine = VimEngine()
    #expect(engine.mode == .normal)
  }

  @Test("i switches to insert mode")
  func iSwitchesToInsert() {
    let engine = VimEngine()
    let action = engine.handle(key: "i", hasModifiers: false)
    #expect(action == .switchToInsert)
    #expect(engine.mode == .insert)
  }

  @Test("Escape in insert mode switches to normal")
  func escapeSwitchesToNormal() {
    let engine = VimEngine()
    _ = engine.handle(key: "i", hasModifiers: false)
    let action = engine.handle(key: "\u{1B}", hasModifiers: false)
    #expect(action == .switchToNormal)
    #expect(engine.mode == .normal)
  }

  @Test("insert mode passes through non-escape keys")
  func insertPassthrough() {
    let engine = VimEngine()
    _ = engine.handle(key: "i", hasModifiers: false)
    #expect(engine.handle(key: "a", hasModifiers: false) == .none)
    #expect(engine.handle(key: "x", hasModifiers: false) == .none)
    #expect(engine.handle(key: "j", hasModifiers: false) == .none)
  }

  @Test(
    "a enters insert after moving right",
    arguments: ["a"]
  )
  func aEntersInsert(key: String) {
    let engine = VimEngine()
    let action = engine.handle(key: key, hasModifiers: false)
    #expect(action == .composite([.moveCursor(.right(1)), .switchToInsert]))
    #expect(engine.mode == .insert)
  }

  @Test("I enters insert at first non-blank")
  func shiftIEntersInsert() {
    let engine = VimEngine()
    let action = engine.handle(key: "I", hasModifiers: false)
    #expect(action == .composite([.moveCursor(.firstNonBlank), .switchToInsert]))
    #expect(engine.mode == .insert)
  }

  @Test("A enters insert at end of line")
  func shiftAEntersInsert() {
    let engine = VimEngine()
    let action = engine.handle(key: "A", hasModifiers: false)
    #expect(action == .insertAtEndOfLine)
    #expect(engine.mode == .insert)
  }

  @Test("o opens line below and enters insert")
  func oOpensLineBelow() {
    let engine = VimEngine()
    let action = engine.handle(key: "o", hasModifiers: false)
    #expect(action == .openLineBelow)
    #expect(engine.mode == .insert)
  }

  @Test("O opens line above and enters insert")
  func shiftOOpensLineAbove() {
    let engine = VimEngine()
    let action = engine.handle(key: "O", hasModifiers: false)
    #expect(action == .openLineAbove)
    #expect(engine.mode == .insert)
  }

  // MARK: - Simple motions

  @Test(
    "h/j/k/l produce correct motions",
    arguments: [
      ("h", Motion.left(1)),
      ("j", Motion.down(1)),
      ("k", Motion.up(1)),
      ("l", Motion.right(1))
    ]
  )
  func basicMotions(key: String, expected: Motion) {
    let engine = VimEngine()
    #expect(engine.handle(key: key, hasModifiers: false) == .moveCursor(expected))
  }

  @Test(
    "w/b/e produce word motions",
    arguments: [
      ("w", Motion.wordForward(1)),
      ("b", Motion.wordBackward(1)),
      ("e", Motion.wordEnd(1))
    ]
  )
  func wordMotions(key: String, expected: Motion) {
    let engine = VimEngine()
    #expect(engine.handle(key: key, hasModifiers: false) == .moveCursor(expected))
  }

  @Test("0 moves to line start")
  func zeroLineStart() {
    let engine = VimEngine()
    #expect(engine.handle(key: "0", hasModifiers: false) == .moveCursor(.lineStart))
  }

  @Test("$ moves to line end")
  func dollarLineEnd() {
    let engine = VimEngine()
    #expect(engine.handle(key: "$", hasModifiers: false) == .moveCursor(.lineEnd))
  }

  @Test("^ moves to first non-blank")
  func caretFirstNonBlank() {
    let engine = VimEngine()
    #expect(engine.handle(key: "^", hasModifiers: false) == .moveCursor(.firstNonBlank))
  }

  @Test("G moves to document end")
  func shiftGDocumentEnd() {
    let engine = VimEngine()
    #expect(engine.handle(key: "G", hasModifiers: false) == .moveCursor(.documentEnd))
  }

  @Test("gg moves to document start")
  func ggDocumentStart() {
    let engine = VimEngine()
    let first = engine.handle(key: "g", hasModifiers: false)
    #expect(first == .none)
    let second = engine.handle(key: "g", hasModifiers: false)
    #expect(second == .moveCursor(.documentStart))
  }

  // MARK: - Count prefix

  @Test("3j moves down 3 lines")
  func countMotion() {
    let engine = VimEngine()
    #expect(engine.handle(key: "3", hasModifiers: false) == .none)
    #expect(engine.handle(key: "j", hasModifiers: false) == .moveCursor(.down(3)))
  }

  @Test("12l moves right 12")
  func multiDigitCount() {
    let engine = VimEngine()
    _ = engine.handle(key: "1", hasModifiers: false)
    _ = engine.handle(key: "2", hasModifiers: false)
    #expect(engine.handle(key: "l", hasModifiers: false) == .moveCursor(.right(12)))
  }

  @Test("0 without prior count is line start, not count digit")
  func zeroWithoutCount() {
    let engine = VimEngine()
    #expect(engine.handle(key: "0", hasModifiers: false) == .moveCursor(.lineStart))
  }

  @Test("10 then 0 accumulates to 100 not line-start")
  func zeroAfterDigits() {
    let engine = VimEngine()
    _ = engine.handle(key: "1", hasModifiers: false)
    _ = engine.handle(key: "0", hasModifiers: false)
    _ = engine.handle(key: "0", hasModifiers: false)
    #expect(engine.handle(key: "j", hasModifiers: false) == .moveCursor(.down(100)))
  }

  // MARK: - Delete variants

  @Test("x deletes one char")
  func xDeleteChar() {
    let engine = VimEngine()
    #expect(engine.handle(key: "x", hasModifiers: false) == .deleteChar(count: 1))
  }

  @Test("5x deletes five chars")
  func countX() {
    let engine = VimEngine()
    _ = engine.handle(key: "5", hasModifiers: false)
    #expect(engine.handle(key: "x", hasModifiers: false) == .deleteChar(count: 5))
  }

  @Test("D deletes to end of line")
  func shiftDDeleteToEnd() {
    let engine = VimEngine()
    #expect(engine.handle(key: "D", hasModifiers: false) == .deleteToEndOfLine)
  }

  @Test("dd deletes current line")
  func ddDeleteLine() {
    let engine = VimEngine()
    _ = engine.handle(key: "d", hasModifiers: false)
    #expect(engine.handle(key: "d", hasModifiers: false) == .deleteLine(count: 1))
  }

  @Test("3dd deletes 3 lines")
  func countDD() {
    let engine = VimEngine()
    _ = engine.handle(key: "3", hasModifiers: false)
    _ = engine.handle(key: "d", hasModifiers: false)
    #expect(engine.handle(key: "d", hasModifiers: false) == .deleteLine(count: 3))
  }

  @Test("dw deletes a word forward")
  func dw() {
    let engine = VimEngine()
    _ = engine.handle(key: "d", hasModifiers: false)
    #expect(engine.handle(key: "w", hasModifiers: false) == .delete(.wordForward(1)))
  }

  @Test("d$ deletes to line end")
  func dDollar() {
    let engine = VimEngine()
    _ = engine.handle(key: "d", hasModifiers: false)
    #expect(engine.handle(key: "$", hasModifiers: false) == .delete(.lineEnd))
  }

  @Test("d0 deletes to line start")
  func dZero() {
    let engine = VimEngine()
    _ = engine.handle(key: "d", hasModifiers: false)
    #expect(engine.handle(key: "0", hasModifiers: false) == .delete(.lineStart))
  }

  @Test("db deletes a word backward")
  func db() {
    let engine = VimEngine()
    _ = engine.handle(key: "d", hasModifiers: false)
    #expect(engine.handle(key: "b", hasModifiers: false) == .delete(.wordBackward(1)))
  }

  // MARK: - Undo

  @Test("u undoes once")
  func undoOnce() {
    let engine = VimEngine()
    #expect(engine.handle(key: "u", hasModifiers: false) == .undo(count: 1))
  }

  @Test("3u undoes three times")
  func countUndo() {
    let engine = VimEngine()
    _ = engine.handle(key: "3", hasModifiers: false)
    #expect(engine.handle(key: "u", hasModifiers: false) == .undo(count: 3))
  }

  // MARK: - Invalid sequences

  @Test("invalid pending clears buffer without side effects")
  func invalidPendingClears() {
    let engine = VimEngine()
    _ = engine.handle(key: "d", hasModifiers: false)
    let action = engine.handle(key: "z", hasModifiers: false)
    #expect(action == .none)
    #expect(engine.handle(key: "j", hasModifiers: false) == .moveCursor(.down(1)))
  }

  @Test("modifier keys are ignored in normal mode")
  func modifierKeysIgnored() {
    let engine = VimEngine()
    #expect(engine.handle(key: "c", hasModifiers: true) == .none)
    #expect(engine.mode == .normal)
  }

  @Test("count resets after completed action")
  func countResetsAfterAction() {
    let engine = VimEngine()
    _ = engine.handle(key: "3", hasModifiers: false)
    _ = engine.handle(key: "j", hasModifiers: false)
    #expect(engine.handle(key: "j", hasModifiers: false) == .moveCursor(.down(1)))
  }

  @Test("reset restores initial state")
  func resetRestoresState() {
    let engine = VimEngine()
    _ = engine.handle(key: "i", hasModifiers: false)
    engine.reset()
    #expect(engine.mode == .normal)
    #expect(engine.handle(key: "j", hasModifiers: false) == .moveCursor(.down(1)))
  }

  // MARK: - Visual line mode

  @Test("V from normal enters visual line mode")
  func enterVisualLine() {
    let engine = VimEngine()
    let action = engine.handle(key: "V", hasModifiers: false)
    #expect(action == .enterVisualLine)
    #expect(engine.mode == .visualLine)
  }

  @Test(
    "motions in visual line mode produce extendVisualLine actions",
    arguments: [
      ("j", Motion.down(1)),
      ("k", Motion.up(1)),
      ("h", Motion.left(1)),
      ("l", Motion.right(1)),
      ("G", Motion.documentEnd)
    ]
  )
  func visualLineMotions(key: String, expected: Motion) {
    let engine = VimEngine()
    _ = engine.handle(key: "V", hasModifiers: false)
    #expect(
      engine.handle(key: key, hasModifiers: false) == .extendVisualLine(expected)
    )
    #expect(engine.mode == .visualLine)
  }

  @Test("count + j in visual line mode extends multiple lines")
  func visualLineCountedMotion() {
    let engine = VimEngine()
    _ = engine.handle(key: "V", hasModifiers: false)
    _ = engine.handle(key: "5", hasModifiers: false)
    #expect(
      engine.handle(key: "j", hasModifiers: false) == .extendVisualLine(.down(5))
    )
  }

  @Test("gg in visual line mode extends to document start")
  func visualLineGG() {
    let engine = VimEngine()
    _ = engine.handle(key: "V", hasModifiers: false)
    #expect(engine.handle(key: "g", hasModifiers: false) == .none)
    #expect(
      engine.handle(key: "g", hasModifiers: false) == .extendVisualLine(.documentStart)
    )
  }

  @Test("<count>G in visual line mode extends down to that line")
  func visualLineCountedG() {
    let engine = VimEngine()
    _ = engine.handle(key: "V", hasModifiers: false)
    _ = engine.handle(key: "1", hasModifiers: false)
    _ = engine.handle(key: "0", hasModifiers: false)
    #expect(
      engine.handle(key: "G", hasModifiers: false) == .extendVisualLine(.down(9))
    )
  }

  @Test("y in visual line mode yanks and returns to normal")
  func visualLineYank() {
    let engine = VimEngine()
    _ = engine.handle(key: "V", hasModifiers: false)
    let action = engine.handle(key: "y", hasModifiers: false)
    #expect(action == .yankVisualLine)
    #expect(engine.mode == .normal)
  }

  @Test("d in visual line mode deletes selection and returns to normal")
  func visualLineDelete() {
    let engine = VimEngine()
    _ = engine.handle(key: "V", hasModifiers: false)
    let action = engine.handle(key: "d", hasModifiers: false)
    #expect(action == .deleteVisualLineSelection)
    #expect(engine.mode == .normal)
  }

  @Test("c in visual line mode deletes selection and switches to insert")
  func visualLineChange() {
    let engine = VimEngine()
    _ = engine.handle(key: "V", hasModifiers: false)
    let action = engine.handle(key: "c", hasModifiers: false)
    #expect(action == .changeVisualLineSelection)
    #expect(engine.mode == .insert)
  }

  @Test("Escape in visual line mode returns to normal")
  func visualLineEscape() {
    let engine = VimEngine()
    _ = engine.handle(key: "V", hasModifiers: false)
    let action = engine.handle(key: "\u{1B}", hasModifiers: false)
    #expect(action == .switchToNormal)
    #expect(engine.mode == .normal)
  }

  @Test("V in visual line mode toggles back to normal")
  func visualLineToggleOff() {
    let engine = VimEngine()
    _ = engine.handle(key: "V", hasModifiers: false)
    let action = engine.handle(key: "V", hasModifiers: false)
    #expect(action == .switchToNormal)
    #expect(engine.mode == .normal)
  }

  @Test("unrecognized keys in visual line mode are ignored, mode stays")
  func visualLineUnknownKey() {
    let engine = VimEngine()
    _ = engine.handle(key: "V", hasModifiers: false)
    #expect(engine.handle(key: "z", hasModifiers: false) == .none)
    #expect(engine.mode == .visualLine)
  }
}
