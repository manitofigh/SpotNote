import AppKit
import Testing

@testable import Spotlight

@Suite("SpotlightPanel")
struct SpotlightPanelTests {
  @Test("canBecomeKey is true -- a borderless panel cannot receive input otherwise")
  @MainActor
  func canBecomeKey() {
    let panel = SpotlightPanel(
      contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    #expect(panel.canBecomeKey)
  }

  @Test("canBecomeMain is false -- the HUD should never be the app's main window")
  @MainActor
  func canBecomeMainIsFalse() {
    let panel = SpotlightPanel(
      contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    #expect(panel.canBecomeMain == false)
  }
}
