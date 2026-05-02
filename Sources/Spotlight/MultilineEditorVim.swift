import AppKit

extension PlaceholderTextView {
  /// Wires this text view to the supplied controller (or detaches when
  /// `nil`), installing the line-jump and substitute closures that need
  /// direct access to `NSTextView` APIs the controller can't reach.
  func attachVimController(_ controller: VimController?) {
    if vimController === controller { return }
    vimController = controller
    guard let controller else { return }
    controller.lineJumpHandler = { [weak self] line in
      self?.jumpToLine(line) ?? false
    }
    controller.substituteHandler = { [weak self] req in
      self?.performSubstitute(req) ?? 0
    }
  }

  /// Per-keystroke vim dispatch. Extracted from `keyDown` so the main
  /// switchboard stays under SwiftLint's complexity cap. Returns
  /// `false` when the caller should fall through to `super.keyDown`.
  func handleVimKey(
    event: NSEvent,
    engine: VimEngine,
    mods: NSEvent.ModifierFlags,
    chars: String
  ) -> Bool {
    let isInsert = engine.mode == .insert
    let suggestionToAccept: String? =
      isInsert && mods.isEmpty && shouldAcceptSuggestion(event: event)
      ? pendingSuggestion : nil
    if let suggestion = suggestionToAccept {
      acceptSuggestion(suggestion)
      return true
    }
    if mods == .control, chars == "c", engine.mode != .normal {
      _ = engine.handle(key: "\u{1B}", hasModifiers: false)
      executeVimAction(.switchToNormal)
      return true
    }
    if event.keyCode == 53, engine.mode == .normal {
      onEscape?()
      return true
    }
    let key = vimKey(for: event, mods: mods, chars: chars)
    let hasModifiers = !mods.subtracting(.shift).isEmpty
    let action = engine.handle(key: key, hasModifiers: hasModifiers)
    if isInsert, action == .none { return false }
    executeVimAction(action)
    return true
  }

  private func vimKey(for event: NSEvent, mods: NSEvent.ModifierFlags, chars: String) -> String {
    if event.keyCode == 53 { return "\u{1B}" }
    if !mods.subtracting(.shift).isEmpty { return chars }
    return event.characters ?? chars
  }

  /// Routes one keystroke into the active `:` / `/` prompt. Returns
  /// `true` when the event was consumed.
  func handlePromptKey(
    event: NSEvent,
    controller: VimController,
    mods: NSEvent.ModifierFlags
  ) -> Bool {
    if event.keyCode == 53 {
      controller.cancelPrompt()
      needsDisplay = true
      return true
    }
    if event.keyCode == 36 || event.keyCode == 76 {
      controller.submitPrompt()
      needsDisplay = true
      return true
    }
    if event.keyCode == 51 {
      controller.backspacePrompt()
      return true
    }
    let nonShift = mods.subtracting(.shift)
    guard nonShift.isEmpty else { return false }
    guard let typed = event.characters, !typed.isEmpty else { return true }
    let filtered = Self.filterPromptInput(typed)
    guard !filtered.isEmpty else { return true }
    controller.appendToPrompt(filtered)
    return true
  }

  private static func filterPromptInput(_ raw: String) -> String {
    raw.filter { ch in
      ch.unicodeScalars.allSatisfy { scalar in
        !scalar.properties.isDefaultIgnorableCodePoint && scalar.value >= 0x20
      }
    }
  }

  /// `<n>G` / `:<n>` -- moves the caret to the start of the n-th line
  /// (1-based). Returns `false` when the line doesn't exist.
  @discardableResult
  func jumpToLine(_ line: Int) -> Bool {
    guard line > 0 else { return false }
    let nsString = string as NSString
    var currentLine = 1
    var location = 0
    while currentLine < line, location < nsString.length {
      let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
      let next = lineRange.location + lineRange.length
      if next == location { break }
      location = next
      currentLine += 1
    }
    guard currentLine == line else { return false }
    setSelectedRange(NSRange(location: location, length: 0))
    scrollRangeToVisible(NSRange(location: location, length: 0))
    return true
  }

  /// `:s/pattern/replacement/[g]` and `:%s/...`. Returns the number of
  /// substitutions performed so the controller can flash a count.
  @discardableResult
  func performSubstitute(_ req: SubstituteRequest) -> Int {
    let nsString = string as NSString
    let range: NSRange =
      req.global
      ? NSRange(location: 0, length: nsString.length)
      : nsString.lineRange(for: NSRange(location: selectedRange.location, length: 0))
    let slice = nsString.substring(with: range)
    let (replaced, count) = VimSubstitution.apply(
      to: slice,
      pattern: req.pattern,
      replacement: req.replacement,
      replaceAll: req.replaceAll
    )
    guard count > 0, replaced != slice else { return 0 }
    if shouldChangeText(in: range, replacementString: replaced) {
      replaceCharacters(in: range, with: replaced)
      didChangeText()
    }
    return count
  }

  /// Maps a parsed `VimAction` to text-view side effects. Lives in this
  /// file so the giant per-case switch doesn't bloat
  /// `MultilineEditor.swift`.
  func executeVimAction(_ action: VimAction) {
    if VimActionDispatcher.handleSimple(action, on: self) { return }
    executeMutatingVimAction(action)
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func executeMutatingVimAction(_ action: VimAction) {
    switch action {
    case .moveCursor(let motion): executeMotion(motion)
    case .delete(let motion): executeDeleteMotion(motion)
    case .deleteLine(let count): executeDeleteLines(count)
    case .deleteLineInsert(let count): executeDeleteLinesInsert(count)
    case .deleteChar(let count): executeDeleteChar(count)
    case .undo(let count):
      for _ in 0..<count { undoManager?.undo() }
    case .composite(let actions):
      for sub in actions { executeVimAction(sub) }
    case .gotoLine(let line):
      _ = jumpToLine(line)
    case .enterVisualLine:
      enterVisualLineMode()
    case .extendVisualLine(let motion):
      extendVisualLine(by: motion)
    case .yankVisualLine:
      yankVisualLineSelection()
    case .deleteVisualLineSelection:
      deleteVisualLineSelection(switchingToInsert: false)
    case .changeVisualLineSelection:
      deleteVisualLineSelection(switchingToInsert: true)
    default:
      break
    }
  }

  // MARK: - Visual line

  /// Captures the anchor at the current caret line and immediately
  /// selects the whole line so the user sees the mode is active.
  private func enterVisualLineMode() {
    let anchor = selectedRange.location
    visualLineAnchor = anchor
    visualLineCaret = anchor
    setSelectedRange(linewiseRange(from: anchor, to: anchor))
    notifyVimModeChanged()
    needsDisplay = true
  }

  /// Re-runs `motion` against the live visual-line caret (which is
  /// tracked separately from `selectedRange` so it can sit above or
  /// below the anchor independently). After the motion we re-snap the
  /// selection to full-line boundaries between anchor and new caret.
  private func extendVisualLine(by motion: Motion) {
    guard let anchor = visualLineAnchor else { return }
    let nsString = string as NSString
    let length = nsString.length
    let caretBefore = min(visualLineCaret ?? anchor, length)

    setSelectedRange(NSRange(location: caretBefore, length: 0))
    executeMotion(motion)
    let caretAfter = min(selectedRange.location, length)
    visualLineCaret = caretAfter
    setSelectedRange(linewiseRange(from: anchor, to: caretAfter))
    scrollRangeToVisible(NSRange(location: caretAfter, length: 0))
    needsDisplay = true
  }

  private func linewiseRange(from anchor: Int, to caret: Int) -> NSRange {
    let nsString = string as NSString
    let lo = min(anchor, caret)
    let hi = max(anchor, caret)
    let lower = nsString.lineRange(for: NSRange(location: lo, length: 0))
    let upper = nsString.lineRange(for: NSRange(location: hi, length: 0))
    let start = lower.location
    let end = upper.location + upper.length
    return NSRange(location: start, length: max(0, end - start))
  }

  /// `y` in visual line mode -- copies the selection (with the trailing
  /// newline preserved, matching real vim) and exits to normal.
  private func yankVisualLineSelection() {
    let nsString = string as NSString
    let range = selectedRange
    if range.length > 0, range.length <= nsString.length {
      let text = nsString.substring(with: range)
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)
    }
    exitVisualLineSelection(restoreCaretTo: range.location)
  }

  /// `d` / `c` in visual line mode -- deletes the selection and either
  /// returns to normal (delete) or switches to insert (change).
  private func deleteVisualLineSelection(switchingToInsert: Bool) {
    let range = selectedRange
    let restorePoint = range.location
    if range.length > 0, shouldChangeText(in: range, replacementString: "") {
      replaceCharacters(in: range, with: "")
      didChangeText()
    }
    visualLineAnchor = nil
    visualLineCaret = nil
    setSelectedRange(NSRange(location: min(restorePoint, (string as NSString).length), length: 0))
    notifyVimModeChanged()
    _ = switchingToInsert  // mode is already updated by the engine
    needsDisplay = true
  }

  private func exitVisualLineSelection(restoreCaretTo location: Int) {
    visualLineAnchor = nil
    visualLineCaret = nil
    let clamped = min(location, (string as NSString).length)
    setSelectedRange(NSRange(location: clamped, length: 0))
    notifyVimModeChanged()
    needsDisplay = true
  }

  private func executeDeleteChar(_ count: Int) {
    let nsString = string as NSString
    let cursor = selectedRange.location
    let end = min(cursor + count, nsString.length)
    guard end > cursor else { return }
    insertText("", replacementRange: NSRange(location: cursor, length: end - cursor))
  }
}

/// Pure-Swift core of the substitute command -- split out so it can be
/// unit-tested without an `NSTextView`.
enum VimSubstitution {
  static func apply(
    to input: String,
    pattern: String,
    replacement: String,
    replaceAll: Bool
  ) -> (String, Int) {
    guard !pattern.isEmpty else { return (input, 0) }
    let lines = input.components(separatedBy: "\n")
    var rewritten: [String] = []
    rewritten.reserveCapacity(lines.count)
    var total = 0
    for line in lines {
      let (newLine, count) = applyOnLine(
        line,
        pattern: pattern,
        replacement: replacement,
        replaceAll: replaceAll
      )
      rewritten.append(newLine)
      total += count
    }
    return (rewritten.joined(separator: "\n"), total)
  }

  private static func applyOnLine(
    _ line: String,
    pattern: String,
    replacement: String,
    replaceAll: Bool
  ) -> (String, Int) {
    if replaceAll {
      var working = line
      var count = 0
      while let range = working.range(of: pattern) {
        working.replaceSubrange(range, with: replacement)
        count += 1
      }
      return (working, count)
    }
    guard let range = line.range(of: pattern) else { return (line, 0) }
    var working = line
    working.replaceSubrange(range, with: replacement)
    return (working, 1)
  }
}

/// Side-effect dispatcher for the simple `VimAction` cases (no associated
/// values that change the editor's text). Returning `true` tells
/// `executeVimAction` it has nothing more to do.
enum VimActionDispatcher {
  @MainActor
  static func handleSimple(_ action: VimAction, on view: PlaceholderTextView) -> Bool {
    if handleModeAction(action, on: view) { return true }
    if handlePromptAction(action, on: view) { return true }
    return handleEditingAction(action, on: view)
  }

  @MainActor
  private static func handleModeAction(
    _ action: VimAction,
    on view: PlaceholderTextView
  ) -> Bool {
    switch action {
    case .none:
      return true
    case .switchToInsert, .switchToNormal:
      // Collapse any lingering visual-line selection back to the
      // motion's last caret so Esc/V from VISUAL LINE leaves the user
      // exactly where they were, not on a wide highlight.
      if let caret = view.visualLineCaret {
        let clamped = min(caret, (view.string as NSString).length)
        view.setSelectedRange(NSRange(location: clamped, length: 0))
      }
      view.visualLineAnchor = nil
      view.visualLineCaret = nil
      view.notifyVimModeChanged()
      view.needsDisplay = true
    case .insertAtEndOfLine:
      view.moveToEndOfLine(view)
      view.notifyVimModeChanged()
      view.needsDisplay = true
    case .insertAtFirstNonBlank:
      view.executeMotion(.firstNonBlank)
      view.notifyVimModeChanged()
      view.needsDisplay = true
    default:
      return false
    }
    return true
  }

  @MainActor
  private static func handlePromptAction(
    _ action: VimAction,
    on view: PlaceholderTextView
  ) -> Bool {
    switch action {
    case .enterCommand: view.vimController?.enterPrompt(.command)
    case .enterSearch: view.vimController?.enterPrompt(.search)
    case .findNext: view.vimController?.findStep(1)
    case .findPrevious: view.vimController?.findStep(-1)
    default: return false
    }
    return true
  }

  @MainActor
  private static func handleEditingAction(
    _ action: VimAction,
    on view: PlaceholderTextView
  ) -> Bool {
    switch action {
    case .deleteToEndOfLine:
      view.deleteToEndOfParagraph(view)
    case .openLineBelow:
      view.moveToEndOfLine(view)
      view.insertNewline(view)
      view.notifyVimModeChanged()
      view.needsDisplay = true
    case .openLineAbove:
      view.moveToBeginningOfLine(view)
      view.insertNewline(view)
      view.moveUp(view)
      view.notifyVimModeChanged()
      view.needsDisplay = true
    default:
      return false
    }
    return true
  }
}
