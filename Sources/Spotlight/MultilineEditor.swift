// swiftlint:disable file_length type_body_length function_body_length
import AppKit
import SwiftUI

/// The HUD's text surface -- `NSTextView` in an `NSScrollView` with a
/// custom `NSRulerView` line-number gutter.
///
/// Baselines are computed using `NSLayoutManager.location(forGlyphAt:)`
/// rather than ascender-only heuristics, so the number's glyph baseline
/// lands on the exact same y as the text's glyph baseline even when the
/// paragraph line height differs from the font's natural line height.
/// A separate text-container inset puts a deliberate gap between the
/// gutter and where the caret sits.
struct MultilineEditor: NSViewRepresentable {
  @Binding var text: String
  let theme: Theme
  let placeholder: String
  let showLineNumbers: Bool
  let font: NSFont
  let focusRequest: Int
  /// Counter from `FocusTrigger.caretEndTick`; when it changes, the
  /// editor moves the caret to the very end of `text`. Used by the
  /// append-to-last-note global hotkey.
  var caretEndRequest: Int = 0
  /// Upper bound (in display rows) that the panel grows to before
  /// scrolling. Surfaced from user preferences so the setting can be
  /// tuned between 1 and `ThemePreferences.maxVisibleLinesCap` at
  /// runtime.
  let maxVisibleLines: Int
  /// Extra vertical space owned by chrome outside the editor card
  /// (currently: the optional tutorial bar). Added on top of the
  /// editor's own computed height so the panel can host both without
  /// the editor having to know what's above it.
  let extraChromeHeight: CGFloat
  /// Range to select and scroll into view -- driven by the find bar's
  /// current match. `nil` leaves the user's selection / cursor alone.
  var findHighlight: NSRange?
  var vimModeEnabled: Bool = false
  /// Owning controller used to mirror normal/insert mode into SwiftUI
  /// state, drive the `:` / `/` prompt buffer, and dispatch parsed
  /// commands. `nil` while vim mode is off (the editor short-circuits
  /// every vim-related branch in that case).
  var vimController: VimController?
  /// Invoked when Esc should dismiss the HUD. Fires only when vim mode
  /// is off, or when vim mode is on and the engine is already in normal
  /// mode (insert-mode Esc still falls through to the engine to switch
  /// modes first, matching real vim).
  var onEscape: (() -> Void)?
  /// Called from the AppKit delegate synchronously, so the panel resizes in
  /// the same runloop tick as the text change. A SwiftUI `@State` round-trip
  /// would defer the resize by one runloop, causing a visible flash.
  let onHeightChange: (CGFloat) -> Void

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = makeScrollView()
    let textView = makeTextView(coordinator: context.coordinator)
    replaceLayoutManager(on: textView)
    scroll.documentView = textView
    applyStyle(textView: textView)
    textView.string = text
    textView.placeholderString = placeholder
    refreshAttributes(on: textView)
    configureRuler(scroll: scroll, textView: textView, visible: showLineNumbers)
    installSuggestionField(on: textView)
    textView.vimModeEnabled = vimModeEnabled
    textView.attachVimController(vimController)
    textView.onEscape = onEscape
    return scroll
  }

  private func makeScrollView() -> NSScrollView {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.borderType = .noBorder
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.hasHorizontalScroller = false
    scroll.wantsLayer = true
    scroll.layer?.masksToBounds = true
    return scroll
  }

  private func makeTextView(coordinator: Coordinator) -> PlaceholderTextView {
    let textView = PlaceholderTextView(frame: .zero)
    textView.delegate = coordinator
    textView.drawsBackground = false
    textView.backgroundColor = .clear
    textView.isRichText = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.allowsUndo = true
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.textContainerInset = NSSize(width: EditorMetrics.textLeadingGap, height: 0)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.copyButtonClearance = EditorMetrics.textTrailingGap
    textView.autoresizingMask = [.width]
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.smartInsertDeleteEnabled = false
    return textView
  }

  private func installSuggestionField(on textView: PlaceholderTextView) {
    let view = SuggestionView()
    view.isHidden = true
    view.font = font
    view.textColor = NSColor(theme.placeholder).withAlphaComponent(0.75)
    textView.addSubview(view)
    textView.suggestionField = view
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let textView = scroll.documentView as? PlaceholderTextView else { return }
    context.coordinator.parent = self
    if textView.string != text {
      textView.string = text
      refreshAttributes(on: textView)
      textView.vimController?.clearSearchStatus()
    }
    if textView.vimModeEnabled != vimModeEnabled {
      textView.vimModeEnabled = vimModeEnabled
    }
    textView.attachVimController(vimController)
    textView.onEscape = onEscape
    applyStyle(textView: textView)
    textView.placeholderString = placeholder
    configureRuler(scroll: scroll, textView: textView, visible: showLineNumbers)

    if context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      DispatchQueue.main.async { [weak textView] in
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
      }
    }
    if context.coordinator.lastCaretEndRequest != caretEndRequest {
      context.coordinator.lastCaretEndRequest = caretEndRequest
      let length = (textView.string as NSString).length
      textView.setSelectedRange(NSRange(location: length, length: 0))
      textView.scrollRangeToVisible(NSRange(location: length, length: 0))
    }

    // Reflect the find bar's current match by selecting + scrolling to
    // it. We only act on a transition so a stable highlight doesn't
    // continually steal the user's caret.
    applyFindHighlight(textView: textView, coordinator: context.coordinator)

    // Re-evaluate the panel height: text (via bindings), `maxVisibleLines`,
    // and `extraChromeHeight` can all change here, and the editor delegate
    // only fires on user-driven text edits.
    let rows = LineNumberRuler.displayRowCount(in: textView)
    let editorHeight = EditorMetrics.panelHeight(forLines: rows, maxLines: maxVisibleLines)
    onHeightChange(editorHeight + extraChromeHeight)

    refreshSuggestion(on: textView)
    scroll.verticalRulerView?.needsDisplay = true
    textView.needsDisplay = true
  }

  /// Recomputes the inline math suggestion and repositions the ghost
  /// field next to the cursor. No-ops when the cursor isn't at an
  /// end-of-line position -- the suggestion would otherwise overlap
  /// existing text.
  func refreshSuggestion(on textView: PlaceholderTextView) {
    guard let field = textView.suggestionField else { return }
    let selection = textView.selectedRange
    guard selection.length == 0 else {
      hideSuggestion(field: field, textView: textView)
      return
    }
    let nsString = textView.string as NSString
    let cursor = selection.location
    let nextChar: unichar? = cursor < nsString.length ? nsString.character(at: cursor) : nil
    let atEndOfLine = nextChar == nil || nextChar == 0x0A  // \n
    guard atEndOfLine else {
      hideSuggestion(field: field, textView: textView)
      return
    }
    guard
      let suggestion = MathSuggester.suggestion(
        text: textView.string,
        cursorOffset: cursor
      )
    else {
      hideSuggestion(field: field, textView: textView)
      return
    }
    showSuggestion(suggestion.answer, at: cursor, field: field, textView: textView)
  }

  private func hideSuggestion(field: SuggestionView, textView: PlaceholderTextView) {
    field.isHidden = true
    textView.pendingSuggestion = nil
  }

  private func showSuggestion(
    _ answer: String,
    at cursor: Int,
    field: SuggestionView,
    textView: PlaceholderTextView
  ) {
    let display = " = \(answer)"
    field.text = display
    field.font = font
    field.textColor = NSColor(theme.placeholder).withAlphaComponent(0.75)
    guard let caret = caretFrame(in: textView, cursor: cursor) else {
      hideSuggestion(field: field, textView: textView)
      return
    }
    let textWidth = field.intrinsicTextWidth()
    field.frame = NSRect(
      x: caret.maxX,
      y: caret.origin.y,
      width: textWidth,
      height: caret.height
    )
    field.isHidden = false
    textView.pendingSuggestion = answer
  }

  /// Returns the textView-local rect of the caret at `cursor`. Uses
  /// `NSLayoutManager` directly rather than `firstRect(forCharacterRange:)`,
  /// which returns `.zero` for zero-length ranges at end-of-text and was
  /// the reason the inline math suggestion never appeared while typing.
  private func caretFrame(in textView: NSTextView, cursor: Int) -> NSRect? {
    guard
      let layoutManager = textView.layoutManager,
      let textContainer = textView.textContainer
    else { return nil }
    layoutManager.ensureLayout(for: textContainer)
    let origin = textView.textContainerOrigin
    let nsString = textView.string as NSString
    let length = nsString.length
    if length == 0 {
      return NSRect(
        x: origin.x,
        y: origin.y,
        width: 0,
        height: EditorMetrics.lineHeight
      )
    }
    if cursor <= 0 {
      let frag = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
      return NSRect(
        x: origin.x + frag.minX,
        y: origin.y + frag.minY,
        width: 0,
        height: frag.height
      )
    }
    let priorChar = cursor - 1
    if nsString.character(at: priorChar) == 0x0A {
      let lastGlyph = max(0, layoutManager.numberOfGlyphs - 1)
      let frag = layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
      return NSRect(
        x: origin.x + frag.minX,
        y: origin.y + frag.maxY,
        width: 0,
        height: frag.height
      )
    }
    let priorGlyph = layoutManager.glyphIndexForCharacter(at: priorChar)
    let frag = layoutManager.lineFragmentRect(forGlyphAt: priorGlyph, effectiveRange: nil)
    let priorRect = layoutManager.boundingRect(
      forGlyphRange: NSRange(location: priorGlyph, length: 1),
      in: textContainer
    )
    return NSRect(
      x: origin.x + priorRect.maxX,
      y: origin.y + frag.minY,
      width: 0,
      height: frag.height
    )
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MultilineEditor
    var lastFocusRequest: Int = -1
    var lastCaretEndRequest: Int = 0
    var lastFindHighlight: NSRange?

    init(_ parent: MultilineEditor) { self.parent = parent }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? PlaceholderTextView else { return }
      parent.refreshSuggestion(on: textView)
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? PlaceholderTextView else { return }
      // Resize first -- synchronous and ahead of the SwiftUI @Binding
      // update that happens on the next runloop. Without this ordering,
      // NSTextView had the new line laid out before the panel had grown,
      // which produced the flash when adding lines 2 or 3.
      //
      // Row count = layout fragments, not `\n`-separated logical lines:
      // soft-wrapping should grow the panel the same way pressing Return
      // does, capped at `maxVisibleLines`.
      let rows = LineNumberRuler.displayRowCount(in: textView)
      let editorHeight = EditorMetrics.panelHeight(
        forLines: rows,
        maxLines: parent.maxVisibleLines
      )
      parent.onHeightChange(editorHeight + parent.extraChromeHeight)
      parent.ensureParagraphStyle(on: textView)
      parent.text = textView.string
      // Stop showing "2/5" once the user starts editing -- match indices
      // are about to be wrong anyway.
      textView.vimController?.clearSearchStatus()
      if let ruler = textView.enclosingScrollView?.verticalRulerView as? LineNumberRuler {
        ruler.updateRequiredThickness()
        ruler.needsDisplay = true
      }
      parent.applyCodeStyling(on: textView)
      parent.refreshSuggestion(on: textView)
      textView.needsDisplay = true
    }
  }

  private func applyFindHighlight(textView: NSTextView, coordinator: Coordinator) {
    guard let range = findHighlight else {
      coordinator.lastFindHighlight = nil
      return
    }
    let length = (textView.string as NSString).length
    let valid =
      range.location != NSNotFound
      && range.location + range.length <= length
      && coordinator.lastFindHighlight != range
    guard valid else { return }
    coordinator.lastFindHighlight = range
    textView.setSelectedRange(range)
    textView.scrollRangeToVisible(range)
  }

  private var fixedParagraphStyle: NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = EditorMetrics.lineHeight
    style.maximumLineHeight = EditorMetrics.lineHeight
    return style
  }

  private var textAttributes: [NSAttributedString.Key: Any] {
    [
      .font: font,
      .foregroundColor: NSColor(theme.text),
      .paragraphStyle: fixedParagraphStyle
    ]
  }

  private func applyStyle(textView: PlaceholderTextView) {
    let newTextColor = NSColor(theme.text)
    let newPlaceholderColor = NSColor(theme.placeholder)
    if textView.font != font { textView.font = font }
    if textView.textColor != newTextColor { textView.textColor = newTextColor }
    textView.insertionPointColor = newTextColor
    textView.placeholderColor = newPlaceholderColor
    textView.defaultParagraphStyle = fixedParagraphStyle
    textView.typingAttributes = textAttributes
    if let ruler = textView.enclosingScrollView?.verticalRulerView as? LineNumberRuler {
      ruler.textColor = newPlaceholderColor.withAlphaComponent(0.8)
      ruler.editorFont = font
    }
  }

  private func refreshAttributes(on textView: NSTextView) {
    guard let storage = textView.textStorage else { return }
    let range = NSRange(location: 0, length: storage.length)
    storage.setAttributes(textAttributes, range: range)
    applyCodeStyling(on: textView)
  }

  private func replaceLayoutManager(on textView: NSTextView) {
    guard let storage = textView.textStorage,
      let container = textView.textContainer
    else { return }
    let fixed = FixedLineHeightLayoutManager()
    fixed.fixedLineHeight = EditorMetrics.lineHeight
    if let existing = storage.layoutManagers.first {
      storage.removeLayoutManager(existing)
    }
    storage.addLayoutManager(fixed)
    fixed.addTextContainer(container)
  }

  func ensureParagraphStyle(on textView: NSTextView) {
    guard let storage = textView.textStorage else { return }
    let length = storage.length
    guard length > 0 else { return }
    storage.addAttribute(
      .paragraphStyle,
      value: fixedParagraphStyle,
      range: NSRange(location: 0, length: length)
    )
  }

  func applyCodeStyling(on textView: NSTextView) {
    CodeStyler.apply(to: textView, theme: theme)
  }

  private func configureRuler(scroll: NSScrollView, textView: NSTextView, visible: Bool) {
    if visible {
      if !(scroll.verticalRulerView is LineNumberRuler) {
        scroll.verticalRulerView = LineNumberRuler(textView: textView, editorFont: font)
      }
      scroll.hasVerticalRuler = true
      scroll.rulersVisible = true
    } else {
      scroll.rulersVisible = false
      scroll.hasVerticalRuler = false
    }
  }
}

// MARK: - PlaceholderTextView

final class PlaceholderTextView: NSTextView {
  var placeholderString: String = ""
  var placeholderColor: NSColor = .secondaryLabelColor
  weak var suggestionField: SuggestionView?
  var pendingSuggestion: String?

  var copyButtonClearance: CGFloat = 0
  /// Caret position captured when entering visual line mode. The
  /// rendered selection always spans full lines from this anchor to
  /// wherever the caret currently sits, so motions just move the
  /// "tail" of the selection.
  var visualLineAnchor: Int?
  /// Live caret tracked separately from the selection -- `extendVisualLine`
  /// uses it as the moving end (above OR below the anchor) so motions
  /// extend symmetrically instead of always re-collapsing to a fixed
  /// edge of the snapped line range.
  var visualLineCaret: Int?
  var vimEngine: VimEngine?
  weak var vimController: VimController?
  var onEscape: (() -> Void)?

  var vimModeEnabled: Bool = false {
    didSet {
      if vimModeEnabled {
        if vimEngine == nil { vimEngine = VimEngine() }
      } else {
        vimEngine = nil
      }
      notifyVimModeChanged()
      needsDisplay = true
    }
  }

  override func layout() {
    super.layout()
    guard copyButtonClearance > 0, let container = textContainer else { return }
    let containerWidth = container.size.width
    let rect = NSRect(
      x: containerWidth - copyButtonClearance,
      y: 0,
      width: copyButtonClearance,
      height: EditorMetrics.lineHeight
    )
    container.exclusionPaths = [NSBezierPath(rect: rect)]
  }

  override func keyDown(with event: NSEvent) {
    let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
    let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
    if let controller = vimController, controller.prompt != nil {
      if handlePromptKey(event: event, controller: controller, mods: mods) { return }
    }
    if mods == .control, chars == "w" {
      deleteWordBackward(self)
      return
    }
    if mods == .control, chars == "u" {
      deleteToBeginningOfLine(self)
      return
    }
    if let engine = vimEngine {
      if !handleVimKey(event: event, engine: engine, mods: mods, chars: chars) {
        super.keyDown(with: event)
      }
      return
    }
    if event.keyCode == 53 {
      onEscape?()
      return
    }
    if mods.isEmpty, let suggestion = pendingSuggestion, shouldAcceptSuggestion(event: event) {
      acceptSuggestion(suggestion)
      return
    }
    super.keyDown(with: event)
  }

  func shouldAcceptSuggestion(event: NSEvent) -> Bool {
    let isTab = event.keyCode == 48
    let isRight = event.keyCode == 124
    guard isTab || isRight else { return false }
    if isTab { return true }
    // Right arrow only accepts when the caret is at the visual end of
    // its line -- anywhere else the user is just navigating.
    let cursor = selectedRange.location
    let nsString = string as NSString
    if cursor >= nsString.length { return true }
    return nsString.character(at: cursor) == 0x0A
  }

  func acceptSuggestion(_ suggestion: String) {
    let insertion = " = \(suggestion)"
    insertText(insertion, replacementRange: NSRange(location: NSNotFound, length: 0))
    pendingSuggestion = nil
    suggestionField?.isHidden = true
  }

  func executeMotion(_ motion: Motion) {
    if let (selector, count) = repeatedMotion(motion) {
      for _ in 0..<count { selector(self) }
      return
    }
    switch motion {
    case .lineStart: moveToBeginningOfLine(self)
    case .lineEnd: moveToEndOfLine(self)
    case .firstNonBlank: moveToFirstNonBlank()
    case .documentStart:
      setSelectedRange(NSRange(location: 0, length: 0))
    case .documentEnd:
      setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
    default:
      break
    }
  }

  private func repeatedMotion(_ motion: Motion) -> ((Any?) -> Void, Int)? {
    switch motion {
    case .left(let count): return (moveBackward(_:), count)
    case .right(let count): return (moveForward(_:), count)
    case .up(let count): return (moveUp(_:), count)
    case .down(let count): return (moveDown(_:), count)
    case .wordForward(let count), .wordEnd(let count):
      return (moveWordForward(_:), count)
    case .wordBackward(let count): return (moveWordBackward(_:), count)
    default: return nil
    }
  }

  func executeDeleteMotion(_ motion: Motion) {
    let before = selectedRange.location
    executeMotion(motion)
    let after = selectedRange.location
    let start = min(before, after)
    let length = abs(after - before)
    guard length > 0 else { return }
    setSelectedRange(NSRange(location: start, length: 0))
    insertText("", replacementRange: NSRange(location: start, length: length))
  }

  func executeDeleteLines(_ count: Int) {
    let nsString = string as NSString
    guard nsString.length > 0 else { return }
    var range = nsString.lineRange(for: NSRange(location: selectedRange.location, length: 0))
    for _ in 1..<count {
      let nextStart = range.location + range.length
      guard nextStart < nsString.length else { break }
      let nextLine = nsString.lineRange(for: NSRange(location: nextStart, length: 0))
      range.length += nextLine.length
    }
    if range.location > 0, range.location + range.length >= nsString.length {
      range.location -= 1
      range.length += 1
    }
    let cursorAfter = min(range.location, max(0, nsString.length - range.length))
    insertText("", replacementRange: range)
    setSelectedRange(NSRange(location: cursorAfter, length: 0))
  }

  private func moveToFirstNonBlank() {
    moveToBeginningOfLine(self)
    let nsString = string as NSString
    var cursor = selectedRange.location
    while cursor < nsString.length {
      guard let scalar = UnicodeScalar(nsString.character(at: cursor)) else { break }
      let ch = Character(scalar)
      guard ch == " " || ch == "\t" else { break }
      cursor += 1
    }
    setSelectedRange(NSRange(location: cursor, length: 0))
  }

  func notifyVimModeChanged() {
    if let engine = vimEngine {
      vimController?.updateMode(engine.mode)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard string.isEmpty, !placeholderString.isEmpty else { return }
    let effectiveFont = font ?? .systemFont(ofSize: 14)
    let attrs: [NSAttributedString.Key: Any] = [
      .font: effectiveFont,
      .foregroundColor: placeholderColor
    ]
    let baselineInFragment = LineNumberRuler.synthesizedBaseline(
      fragmentHeight: EditorMetrics.lineHeight,
      font: effectiveFont
    )
    let drawY = textContainerOrigin.y + baselineInFragment - effectiveFont.ascender
    let origin = NSPoint(
      x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0),
      y: drawY
    )
    (placeholderString as NSString).draw(at: origin, withAttributes: attrs)
  }

  /// Shrink the blinking caret to the font's ascender-to-descender height
  /// rather than the full 22pt forced-line-height fragment. Sits at the
  /// `extra space above baseline` offset so it hugs the glyphs it
  /// annotates.
  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    let caretFont = font ?? .systemFont(ofSize: 14)
    let fontHeight = caretFont.ascender - caretFont.descender
    let extraSpaceAboveBaseline = max(0, rect.height - fontHeight)
    if vimEngine?.mode == .normal {
      let blockWidth = max(rect.width, 8)
      let blockRect = NSRect(
        x: rect.origin.x,
        y: rect.origin.y + extraSpaceAboveBaseline,
        width: blockWidth,
        height: fontHeight
      )
      color.withAlphaComponent(0.4).setFill()
      blockRect.fill()
    } else {
      let shrunk = NSRect(
        x: rect.origin.x,
        y: rect.origin.y + extraSpaceAboveBaseline,
        width: rect.width,
        height: fontHeight
      )
      super.drawInsertionPoint(in: shrunk, color: color, turnedOn: flag)
    }
  }

  override func setNeedsDisplay(_ invalidRect: NSRect) {
    let dx: CGFloat = vimEngine?.mode == .normal ? -10 : 0
    super.setNeedsDisplay(invalidRect.insetBy(dx: dx, dy: -2))
  }
}

// MARK: - SuggestionView

/// Lightweight, layer-free view that draws a single line of text using
/// the editor's font and `LineNumberRuler.synthesizedBaseline`, so the
/// inline math suggestion sits on the exact same baseline as the
/// caret's character row.
final class SuggestionView: NSView {
  var text: String = "" { didSet { needsDisplay = true } }
  var font: NSFont = .systemFont(ofSize: 14) { didSet { needsDisplay = true } }
  var textColor: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func intrinsicTextWidth() -> CGFloat {
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    return ceil((text as NSString).size(withAttributes: attrs).width) + 2
  }

  override func draw(_ dirtyRect: NSRect) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
    let baselineInFragment = LineNumberRuler.synthesizedBaseline(
      fragmentHeight: EditorMetrics.lineHeight,
      font: font
    )
    let drawY = baselineInFragment - font.ascender
    (text as NSString).draw(at: NSPoint(x: 0, y: drawY), withAttributes: attrs)
  }
}

// MARK: - FixedLineHeightLayoutManager

/// Forces every line fragment -- including empty paragraphs -- to have
/// identical height and baseline positioning. Without this, empty lines
/// (`\n`) get a different glyph Y offset from `NSLayoutManager`'s
/// default typesetter, causing visually uneven spacing between lines.
final class FixedLineHeightLayoutManager: NSLayoutManager {
  var fixedLineHeight: CGFloat = EditorMetrics.lineHeight

  override func setLineFragmentRect(
    _ fragmentRect: NSRect,
    forGlyphRange glyphRange: NSRange,
    usedRect: NSRect
  ) {
    var frag = fragmentRect
    frag.size.height = fixedLineHeight
    var used = usedRect
    used.size.height = fixedLineHeight
    super.setLineFragmentRect(frag, forGlyphRange: glyphRange, usedRect: used)
  }

  override func setLocation(
    _ location: NSPoint,
    forStartOfGlyphRange glyphRange: NSRange
  ) {
    let font =
      textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
      ?? .systemFont(ofSize: EditorMetrics.fontSize)
    let naturalHeight = font.ascender - font.descender
    let fixedY = font.ascender + (fixedLineHeight - naturalHeight) / 2
    super.setLocation(
      NSPoint(x: location.x, y: fixedY),
      forStartOfGlyphRange: glyphRange
    )
  }
}
