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
  /// `FindController.revealRequest`; the editor selects `findHighlight`
  /// only when this changes (explicit search / next / previous), never
  /// because an edit re-ran the search and shifted the match.
  var findRevealRequest: Int = 0
  var vimModeEnabled: Bool = false
  /// When `false`, long lines extend past the right edge and the editor
  /// scrolls horizontally (overlay scroller, fades when idle) instead of
  /// soft-wrapping.
  var wrapLines: Bool = true
  /// Optional Markdown live preview (see `MarkdownPreviewStyler`).
  var markdownPreviewEnabled: Bool = false
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
  /// Invoked when Return should accept the currently previewed navigation
  /// note instead of inserting a newline.
  var onCommitNavigationSelection: (() -> Bool)?
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
    applyWrapMode(scroll: scroll, textView: textView)
    installSuggestionField(on: textView)
    textView.vimModeEnabled = vimModeEnabled
    textView.attachVimController(vimController)
    textView.onEscape = onEscape
    textView.onCommitNavigationSelection = onCommitNavigationSelection
    return scroll
  }

  private func makeScrollView() -> NSScrollView {
    let scroll = OverlayScrollView()
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
    textView.undoManager?.levelsOfUndo = 0
    textView.undoManager?.groupsByEvent = true
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
      textView.resetDocumentState()
      textView.string = text
      textView.undoManager?.removeAllActions()
      refreshAttributes(on: textView)
      textView.vimController?.clearSearchStatus()
    }
    if textView.vimModeEnabled != vimModeEnabled {
      textView.vimModeEnabled = vimModeEnabled
    }
    textView.attachVimController(vimController)
    textView.onEscape = onEscape
    textView.onCommitNavigationSelection = onCommitNavigationSelection
    applyStyle(textView: textView)
    textView.placeholderString = placeholder
    configureRuler(scroll: scroll, textView: textView, visible: showLineNumbers)
    applyWrapMode(scroll: scroll, textView: textView)

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
    syncMarkdownPreview(on: textView)

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
    editorCaretRect(
      in: textView,
      cursor: cursor,
      width: 0,
      fallbackHeight: EditorMetrics.lineHeight
    )
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: MultilineEditor
    var lastFocusRequest: Int = -1
    var lastCaretEndRequest: Int = 0
    var lastFindReveal: Int = 0
    var normalizedTextAwaitingNotification: String?

    init(_ parent: MultilineEditor) { self.parent = parent }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? PlaceholderTextView else { return }
      parent.refreshSuggestion(on: textView)
      parent.revealMarkdownForSelection(on: textView)
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? PlaceholderTextView else { return }
      if let normalized = normalizedTextAwaitingNotification {
        normalizedTextAwaitingNotification = nil
        if textView.string == normalized {
          return
        }
      }
      if textView.normalizeSpecialTokens() {
        normalizedTextAwaitingNotification = textView.string
      }
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
    guard coordinator.lastFindReveal != findRevealRequest else { return }
    guard let range = findHighlight else {
      coordinator.lastFindReveal = findRevealRequest
      return
    }
    let length = (textView.string as NSString).length
    // Text may not have caught up yet (e.g. right after a note switch);
    // keep the request pending and retry on the next update.
    guard range.location != NSNotFound, range.location + range.length <= length else { return }
    coordinator.lastFindReveal = findRevealRequest
    textView.setSelectedRange(range)
    textView.scrollRangeToVisible(range)
  }

  private var fixedParagraphStyle: NSParagraphStyle {
    MultilineEditor.sharedFixedParagraphStyle
  }

  private static let sharedFixedParagraphStyle: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = EditorMetrics.lineHeight
    style.maximumLineHeight = EditorMetrics.lineHeight
    return style
  }()

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
    textView.editorTextAttributes = textAttributes
    // systemGreen is ~2:1 on light backgrounds; a deeper green keeps the
    // checked box at >= 3:1 (WCAG non-text contrast) on every light theme.
    textView.checkboxCheckedColor =
      theme.mode == .dark
      ? .systemGreen.withAlphaComponent(0.95)
      : NSColor(srgbRed: 0.10, green: 0.50, blue: 0.22, alpha: 1)
    // Derive the unchecked border from the text colour rather than the placeholder.
    // Dark themes (e.g. Obsidian): text is near-white → 0.50 opacity = visible light border.
    // Light themes: text is near-black → 0.65 opacity = a dark, legible stroke.
    textView.checkboxUncheckedColor =
      newTextColor
      .withAlphaComponent(theme.mode == .dark ? 0.50 : 0.65)
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
    fixed.editorFont = font
    fixed.delegate = fixed  // self-delegate for glyph-advance normalisation
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
    let fullRange = NSRange(location: 0, length: length)
    var rangesNeedingStyle: [NSRange] = []
    storage.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
      guard let style = value as? NSParagraphStyle,
        style.minimumLineHeight == EditorMetrics.lineHeight,
        style.maximumLineHeight == EditorMetrics.lineHeight
      else {
        rangesNeedingStyle.append(range)
        return
      }
    }
    for range in rangesNeedingStyle {
      storage.addAttribute(.paragraphStyle, value: fixedParagraphStyle, range: range)
    }
  }

  func applyCodeStyling(on textView: NSTextView) {
    CodeStyler.apply(to: textView, theme: theme)
    // Order matters: markdown clears underline/strikethrough document-wide,
    // so links and tags paint after it.
    applyMarkdownPreview(on: textView)
    if let layoutManager = textView.layoutManager {
      LinkStyler.apply(to: layoutManager, text: textView.string as NSString, theme: theme)
    }
    TagStyler.apply(to: textView, theme: theme)
  }

  /// Switches between soft-wrapping (container tracks the view width) and
  /// no-wrap (unbounded container + horizontal overlay scroller). The
  /// scroller is overlay-style, so it never changes the HUD's height.
  private func applyWrapMode(scroll: NSScrollView, textView: PlaceholderTextView) {
    guard let container = textView.textContainer else { return }
    let unbounded = CGFloat.greatestFiniteMagnitude
    guard textView.wrapsLines != wrapLines || scroll.hasHorizontalScroller == wrapLines else { return }
    textView.wrapsLines = wrapLines
    if wrapLines {
      scroll.hasHorizontalScroller = false
      textView.isHorizontallyResizable = false
      container.widthTracksTextView = true
      textView.maxSize = NSSize(width: unbounded, height: unbounded)
      let width = Self.documentWidth(in: scroll)
      if width > 0 {
        textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        container.size = NSSize(
          width: max(0, width - textView.textContainerInset.width * 2),
          height: unbounded
        )
      }
      let leadingEdge = -scroll.contentView.contentInsets.left
      scroll.contentView.scroll(to: NSPoint(x: leadingEdge, y: scroll.contentView.bounds.origin.y))
    } else {
      scroll.hasHorizontalScroller = true
      container.widthTracksTextView = false
      container.size = NSSize(width: unbounded, height: unbounded)
      textView.isHorizontallyResizable = true
      textView.maxSize = NSSize(width: unbounded, height: unbounded)
      textView.minSize = NSSize(width: Self.documentWidth(in: scroll), height: textView.minSize.height)
      container.exclusionPaths = []
      textView.sizeToFit()
    }
    if let layoutManager = textView.layoutManager {
      layoutManager.invalidateLayout(
        forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length),
        actualCharacterRange: nil
      )
      layoutManager.ensureLayout(for: container)
    }
    scroll.reflectScrolledClipView(scroll.contentView)
  }

  /// Width of the clip area right of the line-number gutter. `NSScrollView`
  /// lays the vertical ruler over the clip view as a left content inset,
  /// so `contentSize` includes the gutter. Sizing the document to that
  /// leaves horizontal slack the clip view can scroll into, which slides
  /// the text -- and the caret on an empty line -- under the gutter until a
  /// keystroke scrolls the caret back into view.
  private static func documentWidth(in scroll: NSScrollView) -> CGFloat {
    let insets = scroll.contentView.contentInsets
    return scroll.contentSize.width - insets.left - insets.right
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

/// Returns a caret rect in text-view coordinates. The insertion point must
/// be derived from one visual fragment: using the current glyph for Y and
/// the previous glyph's ink bounds for X breaks at soft-wrap boundaries and
/// after whitespace whose ink bounds are zero-width.
@MainActor
private struct EditorCaretContext {
  let layoutManager: NSLayoutManager
  let textView: NSTextView
  let text: NSString
  let length: Int
  let origin: NSPoint
  let width: CGFloat
}

@MainActor
private func editorCaretRect(
  in textView: NSTextView,
  cursor requestedCursor: Int,
  width: CGFloat,
  fallbackHeight: CGFloat
) -> NSRect? {
  guard let layoutManager = textView.layoutManager,
    let textContainer = textView.textContainer
  else { return nil }
  layoutManager.ensureLayout(for: textContainer)

  let origin = textView.textContainerOrigin
  let nsString = textView.string as NSString
  let length = nsString.length
  let cursor = min(max(0, requestedCursor), length)

  guard length > 0, layoutManager.numberOfGlyphs > 0 else {
    return NSRect(
      x: origin.x,
      y: origin.y,
      width: width,
      height: fallbackHeight
    )
  }
  let context = EditorCaretContext(
    layoutManager: layoutManager,
    textView: textView,
    text: nsString,
    length: length,
    origin: origin,
    width: width
  )

  if cursor == length, nsString.character(at: length - 1) == 0x0A {
    return editorCaretAtExtraLine(context)
  }

  if cursor == 0 || nsString.character(at: cursor - 1) == 0x0A {
    return editorCaretAtLineStart(context, cursor: cursor)
  }

  let previousGlyph = layoutManager.glyphIndexForCharacter(at: cursor - 1)
  let previousFragment = layoutManager.lineFragmentRect(
    forGlyphAt: previousGlyph,
    effectiveRange: nil
  )
  if let caret = editorCaretBeforeNextGlyph(
    context,
    cursor: cursor,
    previousFragment: previousFragment
  ) {
    return caret
  }

  return editorCaretAfterLastGlyph(
    context,
    glyph: previousGlyph,
    fragment: previousFragment
  )
}

@MainActor
private func editorCaretAtExtraLine(_ context: EditorCaretContext) -> NSRect {
  let layoutManager = context.layoutManager
  let extra = layoutManager.extraLineFragmentRect
  if !extra.isEmpty {
    return NSRect(
      x: context.origin.x + extra.minX,
      y: context.origin.y + extra.minY,
      width: context.width,
      height: extra.height
    )
  }
  let lastFragment = layoutManager.lineFragmentRect(
    forGlyphAt: layoutManager.numberOfGlyphs - 1,
    effectiveRange: nil
  )
  return NSRect(
    x: context.origin.x + lastFragment.minX,
    y: context.origin.y + lastFragment.maxY,
    width: context.width,
    height: lastFragment.height
  )
}

@MainActor
private func editorCaretAtLineStart(
  _ context: EditorCaretContext,
  cursor: Int
) -> NSRect {
  let layoutManager = context.layoutManager
  let glyph = min(
    layoutManager.glyphIndexForCharacter(at: cursor),
    layoutManager.numberOfGlyphs - 1
  )
  let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
  return NSRect(
    x: context.origin.x + fragment.minX,
    y: context.origin.y + fragment.minY,
    width: context.width,
    height: fragment.height
  )
}

@MainActor
private func editorCaretBeforeNextGlyph(
  _ context: EditorCaretContext,
  cursor: Int,
  previousFragment: NSRect
) -> NSRect? {
  let layoutManager = context.layoutManager
  guard cursor < context.length, context.text.character(at: cursor) != 0x0A else { return nil }
  let nextGlyph = min(
    layoutManager.glyphIndexForCharacter(at: cursor),
    layoutManager.numberOfGlyphs - 1
  )
  let nextFragment = layoutManager.lineFragmentRect(forGlyphAt: nextGlyph, effectiveRange: nil)
  if nextFragment.origin.y > previousFragment.origin.y + 0.5 {
    return NSRect(
      x: context.origin.x + nextFragment.minX,
      y: context.origin.y + nextFragment.minY,
      width: context.width,
      height: nextFragment.height
    )
  }

  // The next glyph's layout location is the exact insertion position,
  // including trailing spaces and tabs that have no visible ink bounds.
  let nextLocation = layoutManager.location(forGlyphAt: nextGlyph)
  return NSRect(
    x: context.origin.x + nextFragment.minX + nextLocation.x,
    y: context.origin.y + nextFragment.minY,
    width: context.width,
    height: nextFragment.height
  )
}

@MainActor
private func editorCaretAfterLastGlyph(
  _ context: EditorCaretContext,
  glyph: Int,
  fragment: NSRect
) -> NSRect {
  let layoutManager = context.layoutManager
  let location = layoutManager.location(forGlyphAt: glyph)
  let character = layoutManager.characterIndexForGlyph(at: glyph)
  let composedRange = context.text.rangeOfComposedCharacterSequence(at: character)
  let font =
    (context.textView.textStorage?.attribute(.font, at: character, effectiveRange: nil) as? NSFont)
    ?? context.textView.font
    ?? .systemFont(ofSize: EditorMetrics.fontSize)
  let advance = context.text.substring(with: composedRange).size(withAttributes: [.font: font]).width
  return NSRect(
    x: context.origin.x + fragment.minX + location.x + advance,
    y: context.origin.y + fragment.minY,
    width: context.width,
    height: fragment.height
  )
}

// MARK: - PlaceholderTextView

final class PlaceholderTextView: NSTextView {
  private let editorUndoManager: UndoManager = {
    let manager = UndoManager()
    manager.levelsOfUndo = 0
    manager.groupsByEvent = true
    return manager
  }()

  override var undoManager: UndoManager? { editorUndoManager }

  private enum RenderedTokenKind {
    case today
    case checklist
  }

  private struct RenderedToken {
    let kind: RenderedTokenKind
    let tokenLiteral: String
    let reversionText: String
    let renderedText: String
    let renderedRange: NSRange
  }
  private struct EditContext {
    let range: NSRange
    let replacement: String?
    let isPaste: Bool
  }
  private struct SuppressedTokenOccurrence {
    let literal: String
    let range: NSRange
  }

  var placeholderString: String = ""
  var placeholderColor: NSColor = .secondaryLabelColor
  weak var suggestionField: SuggestionView?
  var pendingSuggestion: String?
  var editorTextAttributes: [NSAttributedString.Key: Any] = [:]
  var checkboxCheckedColor: NSColor = .systemGreen.withAlphaComponent(0.95)
  var checkboxUncheckedColor: NSColor = .secondaryLabelColor.withAlphaComponent(0.6)

  var copyButtonClearance: CGFloat = 0
  /// Mirrors `MultilineEditor.wrapLines`. The copy-button exclusion only
  /// applies while wrapping; in no-wrap mode the container is unbounded.
  var wrapsLines: Bool = true
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
  var onCommitNavigationSelection: (() -> Bool)?
  private var lastRenderedToken: RenderedToken?
  private var lastEditContext: EditContext?
  private var lastInsertionPointDisplayRect: NSRect?
  private var isPasting = false
  private var suppressedOccurrences: [SuppressedTokenOccurrence] = []
  /// Keep the insertion point visible briefly after navigation so a move
  /// that lands during AppKit's hidden blink phase is still easy to follow.
  private static let caretRevealDuration: TimeInterval = 0.45
  private var caretVisibleUntil: TimeInterval = 0
  private var caretRevealTimer: Timer?
  /// AppKit can provide different insertion-point widths at different
  /// glyphs. Keep the editor caret visually consistent instead of allowing
  /// those layout-dependent widths to leak into the renderer.
  private let insertionPointWidth: CGFloat = 1
  var markdownPreview = MarkdownPreviewState()

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

  func resetDocumentState() {
    undoManager?.removeAllActions()
    lastRenderedToken = nil
    lastEditContext = nil
    suppressedOccurrences.removeAll()
    visualLineAnchor = nil
    visualLineCaret = nil
    vimEngine?.reset()
    notifyVimModeChanged()
  }

  override func layout() {
    super.layout()
    guard copyButtonClearance > 0, wrapsLines, let container = textContainer else { return }
    let containerWidth = container.size.width
    let rect = NSRect(
      x: containerWidth - copyButtonClearance,
      y: 0,
      width: copyButtonClearance,
      height: EditorMetrics.lineHeight
    )
    if container.exclusionPaths.count == 1, container.exclusionPaths[0].bounds == rect { return }
    container.exclusionPaths = [NSBezierPath(rect: rect)]
  }

  override func keyDown(with event: NSEvent) {
    stabilizeTypingAttributes()
    let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
    let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
    if revertRenderedTokenIfNeeded(event: event, mods: mods, chars: chars) {
      return
    }
    if handleTextHistoryShortcut(mods: mods, chars: chars) { return }
    if let controller = vimController, controller.prompt != nil {
      if handlePromptKey(event: event, controller: controller, mods: mods) { return }
    }
    if commitNavigationSelectionIfNeeded(event: event, mods: mods) {
      return
    }
    if handlePreVimNavigation(event: event, mods: mods, chars: chars) { return }
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

  private func handlePreVimNavigation(
    event: NSEvent,
    mods: NSEvent.ModifierFlags,
    chars: String
  ) -> Bool {
    if handleControlDeletion(mods: mods, chars: chars) { return true }
    return handleCommandArrowMovement(event: event, mods: mods)
  }

  private func handleCommandArrowMovement(
    event: NSEvent,
    mods: NSEvent.ModifierFlags
  ) -> Bool {
    let nonShiftMods = mods.subtracting(.shift)
    guard nonShiftMods == .command else { return false }
    guard vimEngine == nil || vimEngine?.mode == .insert else { return false }

    switch event.keyCode {
    case 123:
      if mods.contains(.shift) {
        moveToBeginningOfLineAndModifySelection(self)
      } else {
        moveToBeginningOfLine(self)
      }
    case 124:
      if mods.contains(.shift) {
        moveToEndOfLineAndModifySelection(self)
      } else {
        moveToEndOfLine(self)
      }
    default:
      return false
    }
    revealCaret()
    return true
  }

  private func revertRenderedTokenIfNeeded(
    event: NSEvent,
    mods: NSEvent.ModifierFlags,
    chars: String
  ) -> Bool {
    let isUndo = mods == .command && chars == "z"
    let isBackspace = mods.isEmpty && event.keyCode == 51
    return (isUndo || isBackspace) && revertLastRenderedTokenIfPossible()
  }

  private func handleTextHistoryShortcut(
    mods: NSEvent.ModifierFlags,
    chars: String
  ) -> Bool {
    guard chars == "z" else { return false }
    if mods == .command { return performTextUndo() }
    if mods == [.command, .shift] { return performTextRedo() }
    return false
  }

  private func handleControlDeletion(
    mods: NSEvent.ModifierFlags,
    chars: String
  ) -> Bool {
    guard mods == .control else { return false }
    if chars == "w" {
      deleteWordBackward(self)
      return true
    }
    if chars == "u" {
      deleteToBeginningOfLine(self)
      return true
    }
    return false
  }

  private func commitNavigationSelectionIfNeeded(
    event: NSEvent,
    mods: NSEvent.ModifierFlags
  ) -> Bool {
    mods.isEmpty && isReturnKey(event) && onCommitNavigationSelection?() == true
  }

  private func isReturnKey(_ event: NSEvent) -> Bool {
    event.keyCode == 36 || event.keyCode == 76
  }

  override func deleteBackward(_ sender: Any?) {
    if revertLastRenderedTokenIfPossible() { return }
    if removeChecklistMarkerBeforeCaret() { return }
    super.deleteBackward(sender)
  }

  override func paste(_ sender: Any?) {
    isPasting = true
    defer { isPasting = false }
    guard let raw = NSPasteboard.general.string(forType: .string) else {
      super.paste(sender)
      return
    }
    insertDiscreteEdit(
      ChecklistText.importFromPasteboard(raw),
      replacing: selectedRange,
      actionName: "Paste"
    )
  }

  /// `insertText` is treated as typing and coalesces with neighbouring
  /// keystrokes into one undo step. Paste, cut and vim operators must be
  /// their own undo step, so break coalescing around them.
  func insertDiscreteEdit(_ text: String, replacing range: NSRange, actionName: String? = nil) {
    breakUndoCoalescing()
    insertText(text, replacementRange: range)
    breakUndoCoalescing()
    if let actionName { undoManager?.setActionName(actionName) }
  }

  /// Vim `o`: on an empty checklist item open a plain line instead of
  /// letting Return's "empty item ends the list" rule delete the item.
  func insertNewlineForOpenLine() {
    if let (item, _) = checklistItemAtCaret(), item.isEmpty {
      insertText("\n", replacementRange: selectedRange)
      return
    }
    insertNewline(nil)
  }

  override func cut(_ sender: Any?) {
    guard selectedRange.length > 0 else {
      super.cut(sender)
      return
    }
    copy(sender)
    insertDiscreteEdit("", replacing: selectedRange, actionName: "Cut")
  }

  // MARK: - Checklist editing

  /// The checklist item on the caret's line, plus that line's range
  /// (without its newline). `nil` when the selection isn't a caret or the
  /// line doesn't start with a marker.
  private func checklistItemAtCaret() -> (item: ChecklistText.Item, line: NSRange)? {
    guard selectedRange.length == 0 else { return nil }
    let nsString = string as NSString
    let caret = selectedRange.location
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    nsString.getLineStart(
      &lineStart,
      end: &lineEnd,
      contentsEnd: &contentsEnd,
      for: NSRange(location: caret, length: 0)
    )
    let line = NSRange(location: lineStart, length: contentsEnd - lineStart)
    guard let item = ChecklistText.item(in: nsString.substring(with: line) as NSString) else {
      return nil
    }
    return (item, line)
  }

  /// Return on a checklist line continues the list at the same depth;
  /// Return on an empty item ends the list (clears the marker).
  override func insertNewline(_ sender: Any?) {
    guard let (item, line) = checklistItemAtCaret(),
      selectedRange.location > line.location + item.markerOffset
    else {
      super.insertNewline(sender)
      return
    }
    let nsString = string as NSString
    if item.isEmpty {
      insertText("", replacementRange: line)
      return
    }
    let continuation = ChecklistText.continuation(
      forLine: nsString.substring(with: line) as NSString,
      item: item
    )
    insertText(continuation, replacementRange: selectedRange)
  }

  /// Backspace right after a line's leading marker (and its space)
  /// removes the marker entirely instead of leaving a stray `☐` or
  /// reverting to `[ ]`.
  private func removeChecklistMarkerBeforeCaret() -> Bool {
    guard let (item, line) = checklistItemAtCaret() else { return false }
    let caret = selectedRange.location - line.location
    let markerEnd = item.markerOffset + 1
    guard caret == item.contentOffset || caret == markerEnd else { return false }
    let range = NSRange(location: line.location + item.markerOffset, length: caret - item.markerOffset)
    insertText("", replacementRange: range)
    return true
  }

  /// Lines touched by the selection that are checklist items.
  private func checklistLinesInSelection() -> [NSRange] {
    let nsString = string as NSString
    let span = nsString.lineRange(for: selectedRange)
    var result: [NSRange] = []
    nsString.enumerateSubstrings(in: span, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
      if ChecklistText.item(in: nsString.substring(with: range) as NSString) != nil {
        result.append(range)
      }
    }
    return result
  }

  /// Tab on checklist lines indents them (wherever the caret is);
  /// elsewhere Tab inserts a tab as usual.
  override func insertTab(_ sender: Any?) {
    let lines = checklistLinesInSelection()
    guard !lines.isEmpty else {
      super.insertTab(sender)
      return
    }
    shiftChecklistLines(lines, indent: true)
  }

  override func insertBacktab(_ sender: Any?) {
    let lines = checklistLinesInSelection()
    guard !lines.isEmpty else {
      super.insertBacktab(sender)
      return
    }
    shiftChecklistLines(lines, indent: false)
  }

  private func shiftChecklistLines(_ lines: [NSRange], indent: Bool) {
    let nsString = string as NSString
    let selection = selectedRange
    var edits: [(range: NSRange, text: String)] = []
    for line in lines {
      if indent {
        edits.append((NSRange(location: line.location, length: 0), ChecklistText.indentUnit))
        continue
      }
      let first = line.length > 0 ? nsString.character(at: line.location) : 0
      if first == 0x09 {
        edits.append((NSRange(location: line.location, length: 1), ""))
      } else if first == 0x20 {
        var count = 0
        // swiftlint:disable opening_brace
        while count < ChecklistText.tabWidth, count < line.length,
          nsString.character(at: line.location + count) == 0x20
        {
          // swiftlint:enable opening_brace
          count += 1
        }
        edits.append((NSRange(location: line.location, length: count), ""))
      }
    }
    guard !edits.isEmpty else { return }
    let span = NSRange(
      location: edits[0].range.location,
      length: NSMaxRange(lines[lines.count - 1]) - edits[0].range.location
    )
    let updated = NSMutableString(string: nsString.substring(with: span))
    for edit in edits.reversed() {
      let local = NSRange(location: edit.range.location - span.location, length: edit.range.length)
      updated.replaceCharacters(in: local, with: edit.text)
    }
    let replacement = updated as String
    guard shouldChangeText(in: span, replacementString: replacement) else { return }
    replaceCharacters(in: span, with: replacement)
    didChangeText()
    // Map each selection edge through the edits; an edge inside removed
    // indentation moves to where that indentation started.
    func mapped(_ position: Int) -> Int {
      var result = position
      for edit in edits where edit.range.location < position {
        let delta = (edit.text as NSString).length - edit.range.length
        if NSMaxRange(edit.range) <= position {
          result += delta
        } else {
          result -= position - edit.range.location
        }
      }
      return max(0, result)
    }
    let start = mapped(selection.location)
    let end = max(start, mapped(NSMaxRange(selection)))
    setSelectedRange(NSRange(location: start, length: end - start))
  }

  override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
    stabilizeTypingAttributes()
    // A rendered token is only revertible until the next edit; otherwise
    // backspacing later through the line could hit the stale token's
    // original end offset and turn `☐` back into `[ ]`.
    lastRenderedToken = nil
    lastEditContext = EditContext(
      range: affectedCharRange,
      replacement: replacementString,
      isPaste: isPasting
    )
    return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
  }

  override func mouseDown(with event: NSEvent) {
    if openLinkIfCommandClicked(event) { return }
    let point = convert(event.locationInWindow, from: nil)
    let containerPoint = NSPoint(
      x: point.x - textContainerOrigin.x,
      y: point.y - textContainerOrigin.y
    )
    if toggleChecklistAtPoint(containerPoint) { return }
    if openMarkdownLinkIfNeeded(at: containerPoint, event: event) { return }
    super.mouseDown(with: event)
  }

  override func tryToPerform(_ action: Selector, with object: Any?) -> Bool {
    if action == Selector(("undo:")) {
      return performTextUndo()
    }
    if action == Selector(("redo:")) {
      return performTextRedo()
    }
    return super.tryToPerform(action, with: object)
  }

  var canUndoText: Bool {
    undoManager?.canUndo == true || lastRenderedToken != nil
  }

  @discardableResult
  func performTextUndo(count: Int = 1) -> Bool {
    if count == 1, revertLastRenderedTokenIfPossible() { return true }
    guard count > 0, let manager = undoManager else { return false }
    var didUndo = false
    for _ in 0..<count {
      guard manager.canUndo else { break }
      manager.undo()
      didUndo = true
    }
    return didUndo
  }

  @discardableResult
  func performTextRedo(count: Int = 1) -> Bool {
    guard count > 0, let manager = undoManager else { return false }
    var didRedo = false
    for _ in 0..<count {
      guard manager.canRedo else { break }
      manager.redo()
      didRedo = true
    }
    return didRedo
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
    defer { revealCaret() }
    if let delta = logicalLineDelta(for: motion) {
      moveByVisualLines(delta)
      return
    }
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

  private func revealCaret() {
    let location = min(selectedRange.location, (string as NSString).length)
    scrollRangeToVisible(NSRange(location: location, length: 0))
  }

  private func repeatedMotion(_ motion: Motion) -> ((Any?) -> Void, Int)? {
    switch motion {
    case .left(let count): return (moveBackward(_:), count)
    case .right(let count): return (moveForward(_:), count)
    case .wordForward(let count), .wordEnd(let count):
      return (moveWordForward(_:), count)
    case .wordBackward(let count): return (moveWordBackward(_:), count)
    default: return nil
    }
  }

  private func logicalLineDelta(for motion: Motion) -> Int? {
    if case .up(let count) = motion { return -count }
    if case .down(let count) = motion { return count }
    return nil
  }

  /// Uses NSTextView's native vertical movement so Vim `j`/`k` follows the
  /// same rendered rows as arrow keys in insert mode, including soft wraps.
  private func moveByVisualLines(_ delta: Int) {
    guard delta != 0 else { return }
    let movement = delta > 0 ? moveDown(_:) : moveUp(_:)
    for _ in 0..<abs(delta) {
      let before = selectedRange.location
      let rowBefore = caretRowY(at: before)
      movement(nil)
      // On the first/last row AppKit jumps to the document start/end
      // without changing row; vim stays put instead.
      if let rowBefore, rowBefore == caretRowY(at: selectedRange.location) {
        setSelectedRange(NSRange(location: before, length: 0))
        break
      }
    }
  }

  private func caretRowY(at location: Int) -> CGFloat? {
    editorCaretRect(in: self, cursor: location, width: 0, fallbackHeight: EditorMetrics.lineHeight)?
      .origin.y
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

  func executeDeleteLinesInsert(_ count: Int) {
    executeDeleteLines(count)
    executeVimAction(.switchToInsert)
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
    drawCheckboxSymbols(in: dirtyRect)
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

  // round(22 × 0.64) = 14 pt — (22 − 14) / 2 = 4 pt headroom each side, no clipping.
  private var checkboxSymbolSize: CGFloat { round(EditorMetrics.lineHeight * 0.64) }

  /// Draws an SF Symbol in place of each ☐/☑ glyph (which CodeStyler
  /// hides with `.foregroundColor = .clear`). Called from `draw(_:)` so
  /// it happens in the same graphics context as the rest of the text view.
  private func drawCheckboxSymbols(in dirtyRect: NSRect) {
    guard let lm = layoutManager, let tc = textContainer else { return }
    let nsString = string as NSString
    guard nsString.length > 0 else { return }
    lm.ensureLayout(for: tc)
    let size = checkboxSymbolSize
    for charIdx in 0..<nsString.length {
      let ch = nsString.character(at: charIdx)
      guard ch == 0x2610 || ch == 0x2611 else { continue }
      let glyphIdx = lm.glyphIndexForCharacter(at: charIdx)
      let frag = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
      guard !frag.isEmpty else { continue }
      let fragTopInView = textContainerOrigin.y + frag.origin.y
      guard fragTopInView + frag.height > dirtyRect.minY,
        fragTopInView < dirtyRect.maxY
      else { continue }
      let isChecked = ch == 0x2611
      // checkmark.square = outline square + checkmark, no fill.
      // Single palette colour renders both the square border and the checkmark.
      let symbolName = isChecked ? "checkmark.square" : "square"
      let color = isChecked ? checkboxCheckedColor : checkboxUncheckedColor
      let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        .applying(.init(paletteColors: [color]))
      guard
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
          .withSymbolConfiguration(cfg)
      else { continue }
      let glyphLoc = lm.location(forGlyphAt: glyphIdx)
      let drawX = textContainerOrigin.x + frag.origin.x + glyphLoc.x
      let drawY = fragTopInView + (frag.height - size) / 2
      img.draw(in: NSRect(x: drawX, y: drawY, width: size, height: size))
    }
  }

  /// Shrink the blinking caret to the font's ascender-to-descender height
  /// rather than the full 22pt forced-line-height fragment. The fixed
  /// layout manager centers glyphs inside that fragment, so the caret uses
  /// the same vertical inset.
  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    let caretShouldBeVisible = flag || isCaretRevealActive
    let displayRect = insertionPointDisplayRect(for: rect, turnedOn: caretShouldBeVisible)
    if vimEngine?.mode == .normal {
      let blockWidth = max(displayRect.width, 8)
      let blockRect = NSRect(
        x: displayRect.origin.x,
        y: displayRect.origin.y,
        width: blockWidth,
        height: displayRect.height
      )
      guard caretShouldBeVisible else {
        invalidateInsertionPointRect(blockRect)
        return
      }
      lastInsertionPointDisplayRect = blockRect
      color.withAlphaComponent(0.4).setFill()
      blockRect.fill()
    } else {
      super.drawInsertionPoint(in: displayRect, color: color, turnedOn: caretShouldBeVisible)
      if caretShouldBeVisible {
        lastInsertionPointDisplayRect = displayRect
      } else {
        invalidateInsertionPointRect(displayRect)
      }
    }
  }

  func insertionPointDisplayRect(for rect: NSRect, turnedOn flag: Bool) -> NSRect {
    if !flag, let lastInsertionPointDisplayRect {
      return lastInsertionPointDisplayRect
    }
    let baseRect = flag ? normalizedInsertionPointRect(rect) : rect
    return shrinkInsertionPointRectToFont(baseRect)
  }

  private func shrinkInsertionPointRectToFont(_ rect: NSRect) -> NSRect {
    let caretFont = font ?? .systemFont(ofSize: 14)
    let fontHeight = caretFont.ascender - caretFont.descender
    let centeredGlyphInset = max(0, rect.height - fontHeight) / 2
    let normalized = NSRect(
      x: rect.origin.x,
      y: rect.origin.y + centeredGlyphInset,
      width: insertionPointWidth,
      height: fontHeight
    )
    return pixelAlignInsertionPoint(normalized)
  }

  private func pixelAlignInsertionPoint(_ rect: NSRect) -> NSRect {
    let scale = max(window?.backingScaleFactor ?? layer?.contentsScale ?? 1, 1)
    var aligned = rect
    aligned.origin.x = round(rect.origin.x * scale) / scale
    aligned.origin.y = round(rect.origin.y * scale) / scale
    return aligned
  }

  private func invalidateInsertionPointRect(_ rect: NSRect) {
    super.setNeedsDisplay(rect.insetBy(dx: -2, dy: -2))
    if let lastInsertionPointDisplayRect {
      super.setNeedsDisplay(lastInsertionPointDisplayRect.insetBy(dx: -2, dy: -2))
    }
    lastInsertionPointDisplayRect = nil
  }

  func normalizedInsertionPointRect(_ rect: NSRect) -> NSRect {
    if let caret = editorCaretRect(
      in: self,
      cursor: selectedRange.location,
      width: insertionPointWidth,
      fallbackHeight: EditorMetrics.lineHeight
    ) {
      return caret
    }
    return NSRect(
      x: rect.origin.x,
      y: rect.origin.y,
      width: insertionPointWidth,
      height: rect.height
    )
  }

  override func setNeedsDisplay(_ invalidRect: NSRect) {
    let dx: CGFloat = vimEngine?.mode == .normal ? -10 : 0
    super.setNeedsDisplay(invalidRect.insetBy(dx: dx, dy: -2))
    if let lastInsertionPointDisplayRect {
      super.setNeedsDisplay(lastInsertionPointDisplayRect.insetBy(dx: dx, dy: -2))
    }
  }

  override func setSelectedRange(_ charRange: NSRange) {
    super.setSelectedRange(charRange)
    revealCaretAfterMovementIfNeeded(for: charRange)
  }

  override func setSelectedRange(
    _ charRange: NSRange,
    affinity: NSSelectionAffinity,
    stillSelecting flag: Bool
  ) {
    super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
    revealCaretAfterMovementIfNeeded(for: charRange)
  }

  private var isCaretRevealActive: Bool {
    ProcessInfo.processInfo.systemUptime < caretVisibleUntil
  }

  private func revealCaretAfterMovementIfNeeded(for range: NSRange) {
    guard range.length == 0 else { return }
    caretVisibleUntil = ProcessInfo.processInfo.systemUptime + Self.caretRevealDuration
    caretRevealTimer?.invalidate()
    caretRevealTimer = Timer.scheduledTimer(
      withTimeInterval: Self.caretRevealDuration,
      repeats: false
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.caretRevealTimer = nil
        self.caretVisibleUntil = 0
        self.updateInsertionPointStateAndRestartTimer(true)
      }
    }
    updateInsertionPointStateAndRestartTimer(true)
  }

  @objc func insertTodayBadgeToken(_ sender: Any?) {
    insertText("@today", replacementRange: NSRange(location: NSNotFound, length: 0))
  }

  @objc func insertChecklistToken(_ sender: Any?) {
    insertText("@cl", replacementRange: NSRange(location: NSNotFound, length: 0))
  }

  @objc func toggleChecklistShortcut(_ sender: Any?) {
    toggleChecklistAtCurrentLine()
  }

  // swiftlint:disable opening_brace
  func normalizeSpecialTokens() -> Bool {
    let original = string
    var updated = original
    var targetSelection = selectedRange
    var renderedToken: RenderedToken?
    let originalNS = original as NSString

    guard let edit = lastEditContext else { return false }
    lastEditContext = nil
    if edit.isPaste { return false }
    pruneSuppressedOccurrences(after: edit, in: originalNS)

    if let replacement = edit.replacement,
      replacement.count == 1 || replacement == "@today" || replacement == "@cl"
    {
      let caret = selectedRange.location
      if let tokenRange = originalNS.trailingTokenRange("@today", endingAt: caret),
        !isSuppressed(literal: "@today", range: tokenRange, in: originalNS)
      {
        let date = Self.todayDisplayString()
        updated = originalNS.replacingCharacters(in: tokenRange, with: date)
        renderedToken = RenderedToken(
          kind: .today,
          tokenLiteral: "@today",
          reversionText: "@today",
          renderedText: date,
          renderedRange: NSRange(location: tokenRange.location, length: (date as NSString).length)
        )
        targetSelection = NSRange(location: tokenRange.location + (date as NSString).length, length: 0)
      } else if let tokenRange = originalNS.trailingTokenRange("@cl", endingAt: caret),
        !isSuppressed(literal: "@cl", range: tokenRange, in: originalNS),
        !originalNS.lineContainsCheckbox(at: tokenRange.location)
      {
        let replacementText = "☐"
        updated = originalNS.replacingCharacters(in: tokenRange, with: replacementText)
        renderedToken = RenderedToken(
          kind: .checklist,
          tokenLiteral: "@cl",
          reversionText: "[ ]",
          renderedText: replacementText,
          renderedRange: NSRange(
            location: tokenRange.location,
            length: (replacementText as NSString).length
          )
        )
        targetSelection = NSRange(
          location: tokenRange.location + (replacementText as NSString).length,
          length: 0
        )
      }
    }

    guard updated != original else { return false }
    replaceContentPreservingEditorAttributes(with: updated)
    let clamped = min(targetSelection.location, (updated as NSString).length)
    setInsertionPoint(clamped)
    lastRenderedToken = renderedToken
    return true
  }
  // swiftlint:enable opening_brace

  private static func todayDisplayString() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "d MMMM yyyy"
    return formatter.string(from: Date())
  }

  private func toggleChecklistAtCurrentLine() {
    let nsString = string as NSString
    let line = nsString.lineRange(for: NSRange(location: selectedRange.location, length: 0))
    let caretInLine = selectedRange.location - line.location
    guard toggleChecklist(in: line, targetOffset: caretInLine) else { return }
  }

  private func revertLastRenderedTokenIfPossible() -> Bool {
    guard let token = lastRenderedToken else { return false }
    let currentNS = string as NSString
    let max = token.renderedRange.location + token.renderedRange.length
    guard max <= currentNS.length else {
      lastRenderedToken = nil
      return false
    }
    let live = currentNS.substring(with: token.renderedRange)
    guard live == token.renderedText else {
      lastRenderedToken = nil
      return false
    }
    let caret = selectedRange.location
    let originalTokenEnd = token.renderedRange.location + (token.tokenLiteral as NSString).length
    let canRevert =
      selectedRange.length == 0
      && (caret == max || (caret == originalTokenEnd && originalTokenEnd <= currentNS.length))
    guard canRevert else { return false }
    if shouldChangeText(in: token.renderedRange, replacementString: token.reversionText) {
      replaceCharacters(in: token.renderedRange, with: token.reversionText)
      let location = token.renderedRange.location + (token.reversionText as NSString).length
      suppressedOccurrences.append(
        SuppressedTokenOccurrence(
          literal: token.reversionText,
          range: NSRange(
            location: token.renderedRange.location,
            length: (token.reversionText as NSString).length
          )
        )
      )
      setInsertionPoint(location)
      lastRenderedToken = nil
      didChangeText()
      return true
    }
    return false
  }

  private func replaceContentPreservingEditorAttributes(with updated: String) {
    guard let storage = textStorage else {
      string = updated
      return
    }
    let range = NSRange(location: 0, length: storage.length)
    let attributed = NSAttributedString(string: updated, attributes: typingAttributes)
    storage.beginEditing()
    storage.replaceCharacters(in: range, with: attributed)
    storage.endEditing()
    if let textContainer {
      layoutManager?.ensureLayout(for: textContainer)
    }
  }

  /// Toggles the checkbox only when `containerPoint` lands within the
  /// SF Symbol's drawn rect ± `hitPadding` horizontally (full line height
  /// vertically — the user doesn't need sub-pixel vertical precision).
  /// Clicking anywhere else on the line falls through to normal cursor
  /// placement via `super.mouseDown`.
  private func toggleChecklistAtPoint(_ containerPoint: NSPoint) -> Bool {
    guard let lm = layoutManager, let tc = textContainer else { return false }
    let nsString = string as NSString
    guard nsString.length > 0 else { return false }
    lm.ensureLayout(for: tc)
    let size = checkboxSymbolSize
    let hitPadding: CGFloat = 6
    for charIdx in 0..<nsString.length {
      let ch = nsString.character(at: charIdx)
      guard ch == 0x2610 || ch == 0x2611 else { continue }
      let glyphIdx = lm.glyphIndexForCharacter(at: charIdx)
      let frag = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
      guard !frag.isEmpty else { continue }
      let glyphLoc = lm.location(forGlyphAt: glyphIdx)
      let symX = frag.origin.x + glyphLoc.x
      let hitRect = NSRect(
        x: symX - hitPadding,
        y: frag.origin.y,
        width: size + hitPadding * 2,
        height: frag.height
      )
      guard hitRect.contains(containerPoint) else { continue }
      let line = nsString.lineRange(for: NSRange(location: charIdx, length: 0))
      return toggleChecklist(in: line, targetOffset: charIdx - line.location)
    }
    return false
  }

  @discardableResult
  private func toggleChecklist(in lineRange: NSRange, targetOffset: Int) -> Bool {
    let nsString = string as NSString
    let lineText = nsString.substring(with: lineRange)
    guard let markerRange = checklistMarkerRange(in: lineText, near: targetOffset) else { return false }
    let nsLine = lineText as NSString
    let marker = nsLine.substring(with: markerRange)
    let replacement = marker == "☐" ? "☑" : "☐"
    let absoluteRange = NSRange(location: lineRange.location + markerRange.location, length: markerRange.length)
    if shouldChangeText(in: absoluteRange, replacementString: replacement) {
      replaceCharacters(in: absoluteRange, with: replacement)
      didChangeText()
      propagateChecklistParents(fromLineContaining: absoluteRange.location)
      return true
    }
    return false
  }

  /// Checks (or unchecks) ancestors so a parent item is checked exactly
  /// when all of its directly nested checklist children are.
  private func propagateChecklistParents(fromLineContaining location: Int) {
    let nsString = string as NSString
    var lineRanges: [NSRange] = []
    nsString.enumerateSubstrings(
      in: NSRange(location: 0, length: nsString.length),
      options: [.byLines, .substringNotRequired]
    ) { _, range, _, _ in
      lineRanges.append(range)
    }
    if nsString.length == 0 || nsString.hasSuffix("\n") {
      lineRanges.append(NSRange(location: nsString.length, length: 0))
    }
    guard
      let changed = lineRanges.firstIndex(where: {
        location >= $0.location && location <= NSMaxRange($0)
      })
    else { return }
    let lines = lineRanges.map { nsString.substring(with: $0) }
    let updates = ChecklistText.parentUpdates(lines: lines, changedLine: changed)
    for (index, isChecked) in updates {
      guard let item = ChecklistText.item(in: lines[index]) else { continue }
      let range = NSRange(location: lineRanges[index].location + item.markerOffset, length: 1)
      let marker = isChecked ? ChecklistText.checkedString : ChecklistText.uncheckedString
      if shouldChangeText(in: range, replacementString: marker) {
        replaceCharacters(in: range, with: marker)
        didChangeText()
      }
    }
  }

  private func checklistMarkerRange(in lineText: String, near targetOffset: Int) -> NSRange? {
    let nsLine = lineText as NSString
    var matches: [NSRange] = []
    for index in 0..<nsLine.length {
      let character = nsLine.character(at: index)
      if character == 0x2610 || character == 0x2611 {
        matches.append(NSRange(location: index, length: 1))
      }
    }
    if matches.isEmpty { return nil }
    if let containing = matches.first(where: { NSLocationInRange(targetOffset, $0) }) {
      return containing
    }
    return matches.min { lhs, rhs in
      abs(lhs.location - targetOffset) < abs(rhs.location - targetOffset)
    }
  }

  private func stabilizeTypingAttributes() {
    guard !editorTextAttributes.isEmpty else { return }
    typingAttributes = editorTextAttributes
  }

  override func copy(_ sender: Any?) {
    if selectedRange.length == 0 {
      super.copy(sender)
      return
    }
    let nsString = string as NSString
    let raw = nsString.substring(with: selectedRange)
    let mapped = ChecklistText.exportForPasteboard(raw)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(mapped, forType: .string)
  }

  private func isSuppressed(literal: String, range: NSRange, in nsString: NSString) -> Bool {
    suppressedOccurrences = suppressedOccurrences.filter { item in
      let max = item.range.location + item.range.length
      guard max <= nsString.length else { return false }
      return nsString.substring(with: item.range) == item.literal
    }
    return suppressedOccurrences.contains {
      $0.literal == literal && NSEqualRanges($0.range, range)
    }
  }

  private func pruneSuppressedOccurrences(after edit: EditContext, in nsString: NSString) {
    suppressedOccurrences = suppressedOccurrences.filter { item in
      let max = item.range.location + item.range.length
      guard max <= nsString.length, nsString.substring(with: item.range) == item.literal else {
        return false
      }
      if edit.replacement == item.literal, edit.range.location == item.range.location {
        return true
      }
      if edit.range.length > 0 {
        return NSIntersectionRange(edit.range, item.range).length == 0
      }
      return edit.range.location <= item.range.location || edit.range.location >= max
    }
  }

  private func setInsertionPoint(_ location: Int) {
    setSelectedRange(
      NSRange(location: location, length: 0),
      affinity: .downstream,
      stillSelecting: false
    )
  }

}

extension String {
  var matchesDateLine: Bool {
    range(of: #"^\d{1,2}\s+[A-Za-z]+\s+\d{4}$"#, options: .regularExpression) != nil
  }
}

extension NSString {
  func trailingTokenRange(_ token: String, endingAt caret: Int) -> NSRange? {
    let tokenLen = (token as NSString).length
    guard caret >= tokenLen else { return nil }
    let start = caret - tokenLen
    guard start + tokenLen <= length else { return nil }
    let candidate = substring(with: NSRange(location: start, length: tokenLen))
    return candidate == token ? NSRange(location: start, length: tokenLen) : nil
  }

  func lineContainsCheckbox(at position: Int) -> Bool {
    let line = lineRange(for: NSRange(location: position, length: 0))
    for i in 0..<line.length {
      let ch = character(at: line.location + i)
      if ch == 0x2610 || ch == 0x2611 { return true }
    }
    return false
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
  /// Cached editor font used for baseline centering. Avoids looking up
  /// `at: 0` from storage on every glyph placement, which is fragile
  /// when position 0 holds a Unicode character (e.g. ☐) that triggers
  /// system font substitution and produces wrong ascender metrics.
  var editorFont: NSFont = .systemFont(ofSize: EditorMetrics.fontSize)
  var markdownGlyphs = MarkdownGlyphVisibility()

  override func setLineFragmentRect(
    _ fragmentRect: NSRect,
    forGlyphRange glyphRange: NSRange,
    usedRect: NSRect
  ) {
    var frag = fragmentRect
    // Derive origin.y from the previously stored rect so the typesetter's
    // internal Y-tracker (which advances by the glyph's *natural* height,
    // not our overridden height) cannot push subsequent lines off-grid.
    // Without this, a substituted-font glyph on line N (e.g. ☐) causes
    // line N+1 to land at natural_height instead of fixedLineHeight, and
    // the next partial re-layout corrects it — producing the visible shift.
    if glyphRange.location == 0 {
      frag.origin.y = 0
    } else {
      let prevFrag = lineFragmentRect(forGlyphAt: glyphRange.location - 1, effectiveRange: nil)
      if !prevFrag.isEmpty {
        frag.origin.y = prevFrag.maxY
      }
    }
    frag.size.height = fixedLineHeight
    var used = usedRect
    used.origin.y = frag.origin.y
    used.size.height = fixedLineHeight
    super.setLineFragmentRect(frag, forGlyphRange: glyphRange, usedRect: used)
  }

  override func setExtraLineFragmentRect(
    _ fragmentRect: NSRect,
    usedRect: NSRect,
    textContainer: NSTextContainer
  ) {
    var frag = fragmentRect
    var used = usedRect
    if numberOfGlyphs > 0 {
      let lastFrag = lineFragmentRect(forGlyphAt: numberOfGlyphs - 1, effectiveRange: nil)
      if !lastFrag.isEmpty {
        frag.origin.y = lastFrag.maxY
        used.origin.y = frag.origin.y
      }
    }
    frag.size.height = fixedLineHeight
    used.size.height = fixedLineHeight
    super.setExtraLineFragmentRect(frag, usedRect: used, textContainer: textContainer)
  }

  /// Skips the raw ☐ / ☑ glyphs: `PlaceholderTextView` draws an SF Symbol
  /// in their place. Hiding them with a clear temporary colour alone isn't
  /// enough, because selected text is drawn with `selectedTextAttributes`'
  /// foreground colour, which made the font's sharp-cornered box show up
  /// on top of the rounded symbol whenever a checklist line was selected.
  override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
    guard let storage = textStorage, glyphsToShow.length > 0 else {
      super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
      return
    }
    let nsString = storage.string as NSString
    let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
    let searchRange = NSIntersectionRange(charRange, NSRange(location: 0, length: nsString.length))
    let hasMarker =
      nsString.rangeOfCharacter(from: Self.checkboxCharacters, options: [], range: searchRange).location
      != NSNotFound
    guard hasMarker else {
      super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
      return
    }
    var runStart = glyphsToShow.location
    let end = NSMaxRange(glyphsToShow)
    for glyph in glyphsToShow.location..<end {
      let character = characterIndexForGlyph(at: glyph)
      guard character < nsString.length, ChecklistText.isMarker(nsString.character(at: character)) else {
        continue
      }
      if glyph > runStart {
        super.drawGlyphs(forGlyphRange: NSRange(location: runStart, length: glyph - runStart), at: origin)
      }
      runStart = glyph + 1
    }
    if end > runStart {
      super.drawGlyphs(forGlyphRange: NSRange(location: runStart, length: end - runStart), at: origin)
    }
  }

  private static let checkboxCharacters = CharacterSet(charactersIn: "☐☑")

  override func setLocation(
    _ location: NSPoint,
    forStartOfGlyphRange glyphRange: NSRange
  ) {
    let naturalHeight = editorFont.ascender - editorFont.descender
    let fixedY = editorFont.ascender + (fixedLineHeight - naturalHeight) / 2
    super.setLocation(
      NSPoint(x: location.x, y: fixedY),
      forStartOfGlyphRange: glyphRange
    )
  }

}

// MARK: - FixedLineHeightLayoutManager + NSLayoutManagerDelegate

/// Uses self-delegation to normalise the glyph advance of ☑ (U+2611) to
/// match ☐ (U+2610). Both characters are rendered invisible by CodeStyler
/// (`.foregroundColor = .clear`) and replaced visually with SF Symbols, so
/// the actual glyph drawn is irrelevant. What matters is that both share
/// the same advance width so toggling a checkbox never shifts text to its right.
extension FixedLineHeightLayoutManager: NSLayoutManagerDelegate {
  // swiftlint:disable:next function_parameter_count
  func layoutManager(
    _ layoutManager: NSLayoutManager,
    shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
    properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
    characterIndexes charIndexes: UnsafePointer<Int>,
    font aFont: NSFont,
    forGlyphRange glyphRange: NSRange
  ) -> Int {
    guard let storage = textStorage else { return 0 }
    let nsString = storage.string as NSString

    // Fast-path: no ☑ in range → nothing to substitute
    var hasChecked = false
    for i in 0..<glyphRange.length where charIndexes[i] < nsString.length {
      if nsString.character(at: charIndexes[i]) == 0x2611 {
        hasChecked = true
        break
      }
    }
    let hidesMarkdown = markdownGlyphs.hidesAny(charIndexes: charIndexes, count: glyphRange.length)
    guard hasChecked || hidesMarkdown else { return 0 }

    // Resolve ☐'s glyph in the current font so we can reuse it for ☑
    var uncheckedChar: UniChar = 0x2610
    var uncheckedGlyph: CGGlyph = 0
    let canSubstitute =
      hasChecked && CTFontGetGlyphsForCharacters(aFont as CTFont, &uncheckedChar, &uncheckedGlyph, 1)
      && uncheckedGlyph != 0
    guard canSubstitute || hidesMarkdown else { return 0 }

    var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
    for i in 0..<glyphRange.length where canSubstitute {
      guard charIndexes[i] < nsString.length,
        nsString.character(at: charIndexes[i]) == 0x2611
      else { continue }
      newGlyphs[i] = uncheckedGlyph
    }

    var propsArr = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
    if hidesMarkdown { markdownGlyphs.hide(properties: &propsArr, charIndexes: charIndexes) }
    let charArr = Array(UnsafeBufferPointer(start: charIndexes, count: glyphRange.length))
    newGlyphs.withUnsafeBufferPointer { gp in
      propsArr.withUnsafeBufferPointer { pp in
        charArr.withUnsafeBufferPointer { cp in
          guard let glyphBase = gp.baseAddress,
            let propertyBase = pp.baseAddress,
            let characterBase = cp.baseAddress
          else { return }
          setGlyphs(
            glyphBase,
            properties: propertyBase,
            characterIndexes: characterBase,
            font: aFont,
            forGlyphRange: glyphRange
          )
        }
      }
    }
    return glyphRange.length
  }
}

// MARK: - OverlayScrollView

/// Always uses overlay scrollers. With a mouse / external display attached
/// macOS switches to legacy scrollers, which take ~15pt of content width
/// when they appear. Near the end of a line that created a feedback loop:
/// a typed character wraps -> the panel grows a row -> the vertical
/// scroller toggles -> the width changes -> the line unwraps -> repeat,
/// visible as text flickering between two rows. Overlay scrollers never
/// change the content width (and the horizontal one in no-wrap mode never
/// changes the HUD height).
final class OverlayScrollView: NSScrollView {
  override var scrollerStyle: NSScroller.Style {
    get { .overlay }
    // swiftlint:disable:next unused_setter_value
    set { super.scrollerStyle = .overlay }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    super.scrollerStyle = .overlay
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    super.scrollerStyle = .overlay
  }
}
