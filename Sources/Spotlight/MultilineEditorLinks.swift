import AppKit

/// ⌘-click and ⌘-hover handling for links styled by `LinkStyler`. The
/// styler tags each link with the `.spotNoteLink` temporary attribute,
/// so lookups here are a glyph hit-test plus one attribute read -- no
/// detection runs on hover.
extension PlaceholderTextView {
  private static let linkTrackingKey = "SpotNoteLinkTracking"

  /// Opens the link under a ⌘-click. Returns `false` (so `mouseDown`
  /// falls through to normal caret placement) for plain clicks or when
  /// no link sits under the pointer.
  func openLinkIfCommandClicked(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.command),
      let hit = linkHit(atWindowPoint: event.locationInWindow),
      let target = LinkDetector.target(for: hit.literal, kind: hit.kind)
    else { return false }
    LinkOpener.open(target)
    return true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    let installed = trackingAreas.contains {
      $0.owner === self && $0.userInfo?[Self.linkTrackingKey] != nil
    }
    guard !installed else { return }
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
        owner: self,
        userInfo: [Self.linkTrackingKey: true]
      )
    )
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    if isCommandHoveringLink(event.modifierFlags, at: event.locationInWindow) {
      NSCursor.pointingHand.set()
    }
  }

  override func cursorUpdate(with event: NSEvent) {
    guard isCommandHoveringLink(event.modifierFlags, at: event.locationInWindow) else {
      super.cursorUpdate(with: event)
      return
    }
    NSCursor.pointingHand.set()
  }

  /// Pressing / releasing ⌘ while the pointer rests over a link swaps
  /// the cursor without waiting for the next mouse move.
  override func flagsChanged(with event: NSEvent) {
    super.flagsChanged(with: event)
    guard let window, let superview else { return }
    let windowPoint = window.mouseLocationOutsideOfEventStream
    guard visibleRect.contains(convert(windowPoint, from: nil)),
      hitTest(superview.convert(windowPoint, from: nil)) === self
    else { return }
    if isCommandHoveringLink(event.modifierFlags, at: windowPoint) {
      NSCursor.pointingHand.set()
    } else {
      NSCursor.iBeam.set()
    }
  }

  /// Cheap when ⌘ isn't held: the glyph hit-test only runs with ⌘ down.
  private func isCommandHoveringLink(_ flags: NSEvent.ModifierFlags, at windowPoint: NSPoint) -> Bool {
    flags.contains(.command) && linkHit(atWindowPoint: windowPoint) != nil
  }

  private func linkHit(atWindowPoint windowPoint: NSPoint) -> (literal: String, kind: LinkKind)? {
    guard let layoutManager, let textContainer else { return nil }
    let nsString = string as NSString
    guard nsString.length > 0 else { return nil }
    let local = convert(windowPoint, from: nil)
    let point = NSPoint(x: local.x - textContainerOrigin.x, y: local.y - textContainerOrigin.y)
    let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
    let glyphRect = layoutManager.boundingRect(
      forGlyphRange: NSRange(location: glyphIndex, length: 1),
      in: textContainer
    )
    // `glyphIndex(for:in:)` snaps to the nearest glyph; require the
    // point to actually sit on it so clicks past a line's end don't
    // count as hits on its last character.
    guard glyphRect.contains(point) else { return nil }
    let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
    guard charIndex < nsString.length else { return nil }
    var range = NSRange(location: 0, length: 0)
    let value = layoutManager.temporaryAttribute(
      .spotNoteLink,
      atCharacterIndex: charIndex,
      longestEffectiveRange: &range,
      in: nsString.lineRange(for: NSRange(location: charIndex, length: 0))
    )
    guard let raw = value as? String, let kind = LinkKind(rawValue: raw) else { return nil }
    return (nsString.substring(with: range), kind)
  }
}

/// Side-effecting half of link activation, kept apart from detection so
/// the latter stays pure and testable.
@MainActor
private enum LinkOpener {
  static func open(_ target: LinkTarget) {
    let workspace = NSWorkspace.shared
    switch target {
    case .url(let url):
      workspace.open(url)
    case .file(let url):
      openFile(url, workspace: workspace)
    case .date:
      // macOS has no public URL scheme for "show Calendar at date X";
      // AppleScript could do it but needs an Automation (TCC) prompt
      // and an Info.plist usage string. Bringing Calendar forward is
      // the clean, permission-free subset.
      openCalendar(workspace: workspace)
    }
  }

  /// Plain directories open in Finder; files and bundles are revealed
  /// rather than opened so ⌘-clicking a path in a note can never launch
  /// a script or app.
  private static func openFile(_ url: URL, workspace: NSWorkspace) {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      NSSound.beep()
      return
    }
    if isDirectory.boolValue, !workspace.isFilePackage(atPath: url.path) {
      workspace.open(url)
    } else {
      workspace.activateFileViewerSelecting([url])
    }
  }

  private static func openCalendar(workspace: NSWorkspace) {
    guard let app = workspace.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
    workspace.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
  }
}
