import AppKit

/// A borderless floating panel tuned for HUD-style input.
///
/// Overrides `canBecomeKey` so the panel can receive keyboard focus even
/// though its window style is borderless, and uses `.nonactivatingPanel`
/// so showing the panel does not steal focus from the frontmost app.
final class SpotlightPanel: NSPanel {
  var keyEquivalentHandler: ((NSEvent) -> Bool)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if keyEquivalentHandler?(event) == true { return true }
    return super.performKeyEquivalent(with: event)
  }
}
