import AppKit

/// Character-index bookkeeping for the Markdown live preview's hidden
/// syntax markers, owned by `FixedLineHeightLayoutManager`.
///
/// Hiding works at glyph-generation time: the layout manager's
/// `shouldGenerateGlyphs` delegate marks every glyph whose character is in
/// `hidden` with `.null`, which TextKit skips for both layout and drawing.
/// The text storage -- and therefore the caret, undo, vim, find and the
/// checklist code -- keeps seeing the raw Markdown string.
struct MarkdownGlyphVisibility: Equatable {
  /// Every syntax-marker character in the document (rendered or not).
  var markers = IndexSet()
  /// Subset of `markers` currently collapsed to `.null` glyphs.
  var hidden = IndexSet()

  /// Whether any glyph in the batch maps to a hidden character.
  /// - Complexity: O(log m) in the number of hidden runs.
  func hidesAny(charIndexes: UnsafePointer<Int>, count: Int) -> Bool {
    guard count > 0, !hidden.isEmpty else { return false }
    let first = charIndexes[0]
    let last = charIndexes[count - 1]
    guard first <= last else { return true }
    return hidden.intersects(integersIn: first...last)
  }

  func hide(properties: inout [NSLayoutManager.GlyphProperty], charIndexes: UnsafePointer<Int>) {
    for index in properties.indices where hidden.contains(charIndexes[index]) {
      properties[index] = .null
    }
  }

  /// Keeps indices aligned with the storage across an edit so glyphs
  /// regenerated before the next restyle never hide the wrong characters.
  /// `editedRange` is the post-edit range, `delta` the change in length.
  mutating func shift(editedRange: NSRange, delta: Int) {
    let oldLength = max(0, editedRange.length - delta)
    let replaced = editedRange.location..<(editedRange.location + oldLength)
    markers.remove(integersIn: replaced)
    hidden.remove(integersIn: replaced)
    markers.shift(startingAt: replaced.upperBound, by: delta)
    hidden.shift(startingAt: replaced.upperBound, by: delta)
  }
}

extension FixedLineHeightLayoutManager {
  override func processEditing(
    for textStorage: NSTextStorage,
    edited editMask: NSTextStorageEditActions,
    range newCharRange: NSRange,
    changeInLength delta: Int,
    invalidatedRange invalidatedCharRange: NSRange
  ) {
    if editMask.contains(.editedCharacters), !markdownGlyphs.markers.isEmpty {
      markdownGlyphs.shift(editedRange: newCharRange, delta: delta)
    }
    super.processEditing(
      for: textStorage,
      edited: editMask,
      range: newCharRange,
      changeInLength: delta,
      invalidatedRange: invalidatedCharRange
    )
  }

  /// Re-derives which markers inside `region` are hidden (every marker not
  /// on a `revealed` line) and invalidates glyphs only where that changed.
  /// - Returns: `true` when any glyph's visibility flipped.
  @discardableResult
  func updateMarkdownVisibility(in region: Range<Int>, revealed: IndexSet) -> Bool {
    let length = textStorage?.length ?? 0
    let clamped = region.clamped(to: 0..<length)
    let regionSet = IndexSet(integersIn: clamped)
    var desired = markdownGlyphs.markers.intersection(regionSet)
    desired.subtract(revealed)
    let current = markdownGlyphs.hidden.intersection(regionSet)
    let changed = desired.symmetricDifference(current)
    guard !changed.isEmpty else { return false }
    markdownGlyphs.hidden.remove(integersIn: clamped)
    markdownGlyphs.hidden.formUnion(desired)
    for run in changed.rangeView {
      let range = NSRange(run)
      invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
      invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
      invalidateDisplay(forCharacterRange: range)
    }
    return true
  }

  /// Drops all preview state, re-showing every previously hidden glyph.
  func clearMarkdownVisibility() {
    let previouslyHidden = markdownGlyphs.hidden
    markdownGlyphs = MarkdownGlyphVisibility()
    for run in previouslyHidden.rangeView {
      let range = NSRange(run)
      invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
      invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
      invalidateDisplay(forCharacterRange: range)
    }
  }

  /// Line fragments spanning the characters in `range`, laid out on demand.
  func lineFragmentCount(forCharacterRange range: NSRange) -> Int {
    let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    guard glyphs.length > 0 else { return 0 }
    ensureLayout(forGlyphRange: glyphs)
    var count = 0
    enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in count += 1 }
    return count
  }
}
