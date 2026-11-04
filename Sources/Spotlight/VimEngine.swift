import Foundation

enum VimMode: Equatable, Sendable {
  case normal
  case insert
  case visualLine
}

enum Motion: Equatable, Sendable {
  case left(Int)
  case right(Int)
  case up(Int)
  case down(Int)
  case wordForward(Int)
  case wordBackward(Int)
  case wordEnd(Int)
  case lineStart
  case lineEnd
  case firstNonBlank
  case documentStart
  case documentEnd
}

/// Vim text objects (`iw` / `aw`) usable after an operator (`c`, `d`, `y`).
enum TextObject: Equatable, Sendable {
  case innerWord
  case aroundWord
}

enum VimAction: Equatable, Sendable {
  case none
  case switchToInsert
  case switchToNormal
  case moveCursor(Motion)
  case delete(Motion)
  case deleteLine(count: Int)
  case deleteLineInsert(count: Int)
  case deleteToEndOfLine
  case deleteChar(count: Int)
  case openLineBelow
  case openLineAbove
  case undo(count: Int)
  case insertAtEndOfLine
  case insertAtFirstNonBlank
  case composite([VimAction])
  case enterCommand
  case enterSearch
  case findNext
  case findPrevious
  case gotoLine(Int)
  case enterVisualLine
  case extendVisualLine(Motion)
  case yankVisualLine
  case deleteVisualLineSelection
  case changeVisualLineSelection
  case changeMotion(Motion)
  case deleteTextObject(TextObject)
  case changeTextObject(TextObject)
  case yankTextObject(TextObject)
  case yankLine(count: Int)
  /// `p` (after: true) / `P` (after: false).
  case paste(after: Bool, count: Int)
}

final class VimEngine {
  private(set) var mode: VimMode = .normal
  private var pendingBuffer: String = ""
  private var countAccumulator: Int = 0

  func handle(key: String, hasModifiers: Bool) -> VimAction {
    if hasModifiers { return .none }

    switch mode {
    case .insert:
      return handleInsert(key: key)
    case .normal:
      return handleNormal(key: key)
    case .visualLine:
      return handleVisualLine(key: key)
    }
  }

  func reset() {
    mode = .normal
    pendingBuffer = ""
    countAccumulator = 0
  }

  private func handleInsert(key: String) -> VimAction {
    guard key == "\u{1B}" || key == "escape" else { return .none }
    mode = .normal
    pendingBuffer = ""
    countAccumulator = 0
    return .switchToNormal
  }

  private func handleNormal(key: String) -> VimAction {
    if key.count == 1, let ch = key.first, ch.isNumber {
      let digit = ch.wholeNumberValue ?? 0
      if digit > 0 || countAccumulator > 0 {
        countAccumulator = countAccumulator * 10 + digit
        return .none
      }
    }

    if !pendingBuffer.isEmpty {
      return handlePending(key: key)
    }

    return handleSingle(key: key)
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func handlePending(key: String) -> VimAction {
    let count = resolvedCount
    defer { clearAccumulator() }

    let buffered = pendingBuffer
    pendingBuffer = ""
    switch buffered {
    case "d":
      if key == "d" { return .deleteLine(count: count) }
      if key == "i" || key == "a" { return awaitTextObject(operator: "d", scope: key) }
      if let motion = motionForKey(key, count: count) { return .delete(motion) }
      return .none
    case "c":
      if key == "c" {
        mode = .insert
        return .deleteLineInsert(count: count)
      }
      if key == "i" || key == "a" { return awaitTextObject(operator: "c", scope: key) }
      if let motion = motionForKey(key, count: count) {
        mode = .insert
        return .changeMotion(motion)
      }
      return .none
    case "y":
      if key == "y" { return .yankLine(count: count) }
      if key == "i" || key == "a" { return awaitTextObject(operator: "y", scope: key) }
      return .none
    case "g":
      if key == "g" { return .moveCursor(.documentStart) }
      return .none
    default:
      if buffered.count == 2 { return resolveTextObject(buffered, key: key) }
      return .none
    }
  }

  /// Keeps `c`/`d`/`y` + `i`/`a` pending until the object key arrives.
  private func awaitTextObject(operator op: String, scope: String) -> VimAction {
    pendingBuffer = op + scope
    return .none
  }

  private func resolveTextObject(_ buffered: String, key: String) -> VimAction {
    guard key == "w" || key == "W" else { return .none }
    let object: TextObject = buffered.hasSuffix("i") ? .innerWord : .aroundWord
    switch buffered.first {
    case "c":
      mode = .insert
      return .changeTextObject(object)
    case "d": return .deleteTextObject(object)
    case "y": return .yankTextObject(object)
    default: return .none
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func handleSingle(key: String) -> VimAction {
    if key == "d" || key == "g" || key == "c" || key == "y" {
      pendingBuffer = key
      return .none
    }

    // `<count>G` jumps to a specific line; bare `G` falls through to the
    // documentEnd motion below.
    if key == "G", countAccumulator > 0 {
      let target = countAccumulator
      clearAccumulator()
      return .gotoLine(target)
    }

    let count = resolvedCount
    defer { clearAccumulator() }

    if let motion = motionForKey(key, count: count) {
      return .moveCursor(motion)
    }

    if let action = enterInsertAction(for: key) { return action }
    switch key {
    case "x": return .deleteChar(count: count)
    case "D": return .deleteToEndOfLine
    case "C":
      mode = .insert
      return .composite([.deleteToEndOfLine, .switchToInsert])
    case "u": return .undo(count: count)
    case "p": return .paste(after: true, count: count)
    case "P": return .paste(after: false, count: count)
    case "V":
      mode = .visualLine
      return .enterVisualLine
    default: return promptOrSearchAction(for: key)
    }
  }

  // MARK: - Visual line mode

  private func handleVisualLine(key: String) -> VimAction {
    if !pendingBuffer.isEmpty {
      return handleVisualLinePending(key: key)
    }
    if key.count == 1, let ch = key.first, ch.isNumber {
      let digit = ch.wholeNumberValue ?? 0
      if digit > 0 || countAccumulator > 0 {
        countAccumulator = countAccumulator * 10 + digit
        return .none
      }
    }
    if key == "g" {
      pendingBuffer = "g"
      return .none
    }

    // `<count>G` jumps to a specific line and snaps the visual range
    // to it; bare `G` falls through to the documentEnd motion.
    if key == "G", countAccumulator > 0 {
      let target = countAccumulator
      clearAccumulator()
      return .extendVisualLine(.down(max(0, target - 1)))
    }

    let count = resolvedCount
    defer { clearAccumulator() }

    if let motion = motionForKey(key, count: count) {
      return .extendVisualLine(motion)
    }
    return visualLineCommand(for: key)
  }

  private func handleVisualLinePending(key: String) -> VimAction {
    let buffered = pendingBuffer
    pendingBuffer = ""
    if buffered == "g", key == "g" {
      clearAccumulator()
      return .extendVisualLine(.documentStart)
    }
    return .none
  }

  private func visualLineCommand(for key: String) -> VimAction {
    switch key {
    case "V", "\u{1B}", "escape":
      mode = .normal
      return .switchToNormal
    case "y":
      mode = .normal
      return .yankVisualLine
    case "d", "x":
      mode = .normal
      return .deleteVisualLineSelection
    case "c", "s":
      mode = .insert
      return .changeVisualLineSelection
    default:
      return .none
    }
  }

  private func enterInsertAction(for key: String) -> VimAction? {
    switch key {
    case "i":
      mode = .insert
      return .switchToInsert
    case "a":
      mode = .insert
      return .composite([.moveCursor(.right(1)), .switchToInsert])
    case "I":
      mode = .insert
      return .composite([.moveCursor(.firstNonBlank), .switchToInsert])
    case "A":
      mode = .insert
      return .insertAtEndOfLine
    case "o":
      mode = .insert
      return .openLineBelow
    case "O":
      mode = .insert
      return .openLineAbove
    default:
      return nil
    }
  }

  private func promptOrSearchAction(for key: String) -> VimAction {
    switch key {
    case ":": return .enterCommand
    case "/": return .enterSearch
    case "n": return .findNext
    case "N": return .findPrevious
    default: return .none
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func motionForKey(_ key: String, count: Int) -> Motion? {
    // #lizard forgives
    switch key {
    case "h", "leftarrow": return .left(count)
    case "l", "rightarrow": return .right(count)
    case "j", "downarrow": return .down(count)
    case "k", "uparrow": return .up(count)
    case "w": return .wordForward(count)
    case "b": return .wordBackward(count)
    case "e": return .wordEnd(count)
    case "0": return .lineStart
    case "$": return .lineEnd
    case "^": return .firstNonBlank
    case "G": return .documentEnd
    default: return nil
    }
  }

  private var resolvedCount: Int { max(1, countAccumulator) }

  private func clearAccumulator() {
    countAccumulator = 0
  }
}

/// Pure range math for vim text objects, kept free of AppKit so it can be
/// unit tested. Works in UTF-16 offsets to match `NSTextView`.
enum VimTextObjects {
  private enum CharClass: Equatable {
    case newline
    case blank
    case keyword
    case punctuation
  }

  private static func charClass(_ unit: unichar) -> CharClass {
    if unit == 0x0A || unit == 0x0D { return .newline }
    if unit == 0x20 || unit == 0x09 { return .blank }
    if unit == 0x5F { return .keyword }  // underscore
    guard let scalar = UnicodeScalar(unit) else { return .keyword }  // surrogate halves
    if CharacterSet.alphanumerics.contains(scalar) { return .keyword }
    if CharacterSet.whitespaces.contains(scalar) { return .blank }
    return .punctuation
  }

  // swiftlint:disable cyclomatic_complexity
  /// Range of the text object under `cursor`, or `nil` when the cursor sits
  /// on a newline / empty line (vim treats `ciw` there as a no-op change).
  static func range(of object: TextObject, in text: NSString, at cursor: Int) -> NSRange? {
    let length = text.length
    guard length > 0 else { return nil }
    var position = min(max(0, cursor), length - 1)
    // The normal-mode caret can rest on a line's newline (after `$` or
    // Esc); act on the word just before it, like vim's last column.
    // swiftlint:disable opening_brace
    if charClass(text.character(at: position)) == .newline, position > 0,
      charClass(text.character(at: position - 1)) != .newline
    {
      // swiftlint:enable opening_brace
      position -= 1
    }
    let cls = charClass(text.character(at: position))
    guard cls != .newline else { return nil }
    var start = position
    while start > 0, charClass(text.character(at: start - 1)) == cls { start -= 1 }
    var end = position + 1
    while end < length, charClass(text.character(at: end)) == cls { end += 1 }
    guard object == .aroundWord else {
      return NSRange(location: start, length: end - start)
    }
    if cls == .blank {
      // `aw` on whitespace: the blanks plus the following word.
      if end < length {
        let next = charClass(text.character(at: end))
        if next == .keyword || next == .punctuation {
          while end < length, charClass(text.character(at: end)) == next { end += 1 }
        }
      }
      return NSRange(location: start, length: end - start)
    }
    let wordEnd = end
    while end < length, charClass(text.character(at: end)) == .blank { end += 1 }
    if end == wordEnd {
      // No trailing blanks -- take the leading ones instead.
      while start > 0, charClass(text.character(at: start - 1)) == .blank { start -= 1 }
    }
    return NSRange(location: start, length: end - start)
  }
  // swiftlint:enable cyclomatic_complexity
}
