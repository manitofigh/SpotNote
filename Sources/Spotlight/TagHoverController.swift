import AppKit

/// Hover affordance for `#tags` in the editor: while the pointer rests on
/// a tag, a small chevron badge appears just past the tag's trailing edge;
/// clicking it opens a colour menu that recolours that tag name globally.
///
/// Cost model: one `NSTrackingArea` (`.inVisibleRect`) on the text view,
/// one reusable chevron subview, and a glyph-index hit test per mouse move
/// against the tag ranges `TagStyler` already computed. The chevron is an
/// overlay subview, so text layout never shifts; clicks elsewhere in the
/// tag still reach the text view and place the caret normally.
///
/// Lifetime: the chevron view (retained by the text view's subview list)
/// owns the controller; the controller holds the text view and the
/// chevron weakly, so there is no retain cycle.
@MainActor
final class TagHoverController: NSResponder {
  private weak var textView: NSTextView?
  private weak var chevron: TagChevronView?
  private var matches: [TagMatch] = []
  private var theme: Theme = ThemeCatalog.theme(withID: ThemeCatalog.defaultID)
  private var store: TagColorStore = .shared
  private var hovered: TagMatch?

  private init(textView: NSTextView) {
    self.textView = textView
    super.init()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  /// The controller already installed on `textView`, if any.
  static func existing(on textView: NSTextView) -> TagHoverController? {
    textView.subviews.lazy.compactMap { $0 as? TagChevronView }.first?.controller
  }

  /// Returns the controller for `textView`, installing the tracking area
  /// and chevron on first call.
  static func attached(to textView: NSTextView) -> TagHoverController {
    if let existing = existing(on: textView) {
      return existing
    }
    let controller = TagHoverController(textView: textView)
    let chevron = TagChevronView(controller: controller)
    chevron.isHidden = true
    textView.addSubview(chevron)
    controller.chevron = chevron
    textView.addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: controller,
        userInfo: nil
      )
    )
    return controller
  }

  func update(matches: [TagMatch], theme: Theme, store: TagColorStore) {
    self.matches = matches
    self.theme = theme
    self.store = store
    hide()
  }

  // MARK: - Tracking

  override func mouseEntered(with event: NSEvent) {
    textView?.window?.acceptsMouseMovedEvents = true
  }

  override func mouseExited(with event: NSEvent) {
    hide()
  }

  override func mouseMoved(with event: NSEvent) {
    guard let textView, !matches.isEmpty else { return }
    let point = textView.convert(event.locationInWindow, from: nil)
    if let chevron, !chevron.isHidden, chevron.frame.insetBy(dx: -3, dy: -3).contains(point) { return }
    guard let hit = tag(at: point, in: textView) else {
      hide()
      return
    }
    show(for: hit.match, trailingRect: hit.trailingRect)
  }

  private func tag(at point: NSPoint, in textView: NSTextView) -> (match: TagMatch, trailingRect: NSRect)? {
    guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return nil }
    let origin = textView.textContainerOrigin
    let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
    let glyph = layoutManager.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: nil)
    let character = layoutManager.characterIndexForGlyph(at: glyph)
    guard let match = matches.first(where: { NSLocationInRange(character, $0.range) }) else { return nil }
    let glyphs = layoutManager.glyphRange(forCharacterRange: match.range, actualCharacterRange: nil)
    let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
    guard bounds.contains(local) else { return nil }
    let lastGlyph = NSRange(location: NSMaxRange(glyphs) - 1, length: 1)
    let trailing = layoutManager.boundingRect(forGlyphRange: lastGlyph, in: container)
    return (match, trailing.offsetBy(dx: origin.x, dy: origin.y))
  }

  private func show(for match: TagMatch, trailingRect: NSRect) {
    guard let chevron, let textView else { return }
    let side = TagChevronView.side
    let maxX = textView.bounds.maxX - side
    chevron.frame = NSRect(
      x: min(trailingRect.maxX + 1, maxX),
      y: trailingRect.midY - side / 2,
      width: side,
      height: side
    )
    chevron.tint = TagStyler.colors(for: store.color(for: match.name), mode: theme.mode).foreground
    chevron.symbolColor = NSColor(theme.background).withAlphaComponent(1)
    chevron.isHidden = false
    hovered = match
  }

  private func hide() {
    hovered = nil
    chevron?.isHidden = true
  }

  // MARK: - Menu

  func showMenu() {
    guard let hovered, let chevron else { return }
    let menu = TagColorMenu.make(
      tag: hovered.name,
      current: store.color(for: hovered.name),
      mode: theme.mode,
      target: self,
      action: #selector(pickColor(_:))
    )
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: chevron)
  }

  @objc private func pickColor(_ sender: NSMenuItem) {
    guard let name = sender.menu?.title, !name.isEmpty, let textView else { return }
    let color = (sender.representedObject as? String).flatMap(TagColor.init(rawValue:))
    store.setColor(color, for: name)
    TagStyler.apply(to: textView, theme: theme, store: store)
  }
}

/// Builds the per-tag colour menu. The menu's `title` carries the tag
/// name; each item's `representedObject` is a `TagColor` raw value, or
/// `nil` for "Default".
@MainActor
enum TagColorMenu {
  static func make(
    tag: String,
    current: TagColor?,
    mode: Theme.Mode,
    target: AnyObject,
    action: Selector
  ) -> NSMenu {
    let menu = NSMenu(title: tag)
    menu.autoenablesItems = false
    let header = NSMenuItem(title: "#\(tag)", action: nil, keyEquivalent: "")
    header.isEnabled = false
    menu.addItem(header)
    for color in TagColor.allCases {
      let item = NSMenuItem(title: color.title, action: action, keyEquivalent: "")
      item.target = target
      item.representedObject = color.rawValue
      item.image = swatch(color.foreground(for: mode))
      item.state = current == color ? .on : .off
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let reset = NSMenuItem(title: "Default", action: action, keyEquivalent: "")
    reset.target = target
    reset.image = swatch(TagStyler.colors(for: nil, mode: mode).foreground)
    reset.state = current == nil ? .on : .off
    menu.addItem(reset)
    return menu
  }

  private static func swatch(_ color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
      color.setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
      return true
    }
  }
}

/// The small chevron badge drawn over the gap after a hovered tag.
@MainActor
final class TagChevronView: NSView {
  static let side: CGFloat = 14

  let controller: TagHoverController
  var tint: NSColor = .controlAccentColor {
    didSet { needsDisplay = true }
  }
  var symbolColor: NSColor = .white {
    didSet { needsDisplay = true }
  }

  init(controller: TagHoverController) {
    self.controller = controller
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .arrow)
  }

  override func mouseDown(with event: NSEvent) {
    controller.showMenu()
  }

  override func draw(_ dirtyRect: NSRect) {
    let badge = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
    tint.withAlphaComponent(0.9).setFill()
    badge.fill()
    let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
      .applying(.init(paletteColors: [symbolColor]))
    guard
      let symbol = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Tag colour")?
        .withSymbolConfiguration(config)
    else { return }
    let size = symbol.size
    symbol.draw(
      in: NSRect(
        x: (bounds.width - size.width) / 2,
        y: (bounds.height - size.height) / 2,
        width: size.width,
        height: size.height
      )
    )
  }
}
