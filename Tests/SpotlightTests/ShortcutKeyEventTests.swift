import AppKit
import Testing

@testable import Spotlight

/// Regression tests for `Shortcut.key(from:)` and the recorder's
/// validity rules. Key-code based cases assume an ANSI/US layout.
@MainActor
@Suite("Shortcut key events")
struct ShortcutKeyEventTests {
  private func keyDown(
    _ chars: String,
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags
  ) -> NSEvent {
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: chars,
        charactersIgnoringModifiers: chars,
        isARepeat: false,
        keyCode: keyCode
      )
    else { preconditionFailure("could not synthesize key event") }
    return event
  }

  @Test("⌘⇧. records '.' (not the shifted '>') so it matches the default and the Carbon table")
  func shiftedPunctuationUsesBaseKey() {
    let event = keyDown(">", keyCode: 47, modifiers: [.command, .shift])
    #expect(Shortcut.key(from: event) == ".")
    let recorded = Shortcut(key: Shortcut.key(from: event), modifiers: [.command, .shift])
    #expect(recorded == ShortcutAction.appendToLastNote.defaultShortcut)
  }

  @Test("⌘⇧ + letter still folds to the lowercase letter")
  func shiftedLetterLowercases() {
    let event = keyDown("T", keyCode: 17, modifiers: [.command, .shift])
    #expect(Shortcut.key(from: event) == "t")
  }

  @Test("⌘⇧Space still resolves to 'space'")
  func shiftedSpace() {
    let event = keyDown(" ", keyCode: 49, modifiers: [.command, .shift])
    #expect(Shortcut.key(from: event) == "space")
  }

  @Test("Return / Tab / Escape map to their display names instead of control characters")
  func controlKeysHaveNames() {
    #expect(Shortcut.key(from: keyDown("\r", keyCode: 36, modifiers: [.command])) == "return")
    #expect(Shortcut.key(from: keyDown("\t", keyCode: 48, modifiers: [.option])) == "tab")
    #expect(Shortcut.key(from: keyDown("\u{1b}", keyCode: 53, modifiers: [.option])) == "escape")
    #expect(Shortcut(key: "return", modifiers: [.command]).displayString == "⌘Return")
  }

  @Test("flagsChanged events yield an empty key instead of raising")
  func flagsChangedIsSafe() throws {
    let cg = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true))
    cg.type = .flagsChanged
    cg.flags = .maskShift
    let event = try #require(NSEvent(cgEvent: cg))
    #expect(event.type == .flagsChanged)
    // Reading `charactersIgnoringModifiers` here would throw
    // NSInternalInconsistencyException and abort the test process.
    #expect(Shortcut.key(from: event).isEmpty)
  }

  @Test("shift-only chords are rejected -- they would shadow typing capitals")
  func rejectsShiftOnly() {
    // swiftlint:disable:next force_unwrapping
    let defaults = UserDefaults(suiteName: "spotnote.test.shiftOnly.\(UUID().uuidString)")!
    let store = ShortcutStore(defaults: defaults)
    #expect(store.setBinding(Shortcut(key: "a", modifiers: [.shift]), for: .newChat) == .missingModifier)
    #expect(store.binding(for: .newChat) == ShortcutAction.newChat.defaultShortcut)
    #expect(store.setBinding(Shortcut(key: "a", modifiers: [.shift, .control]), for: .newChat) == .ok)
  }
}
