import AppKit

/// A borderless floating panel tuned for HUD-style input.
///
/// Overrides `canBecomeKey` so the panel can receive keyboard focus even
/// though its window style is borderless. The panel intentionally avoids
/// `.nonactivatingPanel`: SpotNote is an LSUIElement app, and its HUD must
/// become a real key window when summoned from another app.
final class SpotlightPanel: NSPanel {
  var keyEquivalentHandler: ((NSEvent) -> Bool)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if keyEquivalentHandler?(event) == true { return true }
    return super.performKeyEquivalent(with: event)
  }
}
