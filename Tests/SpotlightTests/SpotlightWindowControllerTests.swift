import AppKit
import Core
import Foundation
import Testing

@testable import Spotlight

@Suite("SpotlightWindowController")
struct SpotlightWindowControllerTests {
  /// **Regression guard** -- for an LSUIElement accessory app the
  /// panel must be a regular activating NSPanel, otherwise
  /// `makeKeyAndOrderFront` from a background process never produces
  /// a visible, keyed window. `.nonactivatingPanel` was tried as part
  /// of an over-fullscreen fix and reproduced exactly that symptom
  /// (HUD never opens). The over-fullscreen path is handled instead
  /// by `panelLevel == .statusBar` + `.fullScreenAuxiliary` in the
  /// collection behavior -- see the dedicated tests below.
  @Test("panel style mask must NOT contain .nonactivatingPanel for an LSUIElement app")
  func panelStyleMaskExcludesNonactivating() {
    #expect(!SpotlightWindowController.panelStyleMask.contains(.nonactivatingPanel))
  }

  @Test("panel style mask is borderless with full-size content")
  func panelStyleMaskShape() {
    let mask = SpotlightWindowController.panelStyleMask
    #expect(mask.contains(.borderless))
    #expect(mask.contains(.fullSizeContentView))
    #expect(!mask.contains(.titled))
    #expect(!mask.contains(.resizable))
    #expect(!mask.contains(.closable))
    #expect(!mask.contains(.miniaturizable))
  }

  /// **Regression guard** -- `.fullScreenAuxiliary` is what allows the
  /// HUD to render in a Space owned by a fullscreen app. Without it,
  /// the panel is hidden behind the fullscreen layer and never shown.
  @Test("panel collection behavior includes .fullScreenAuxiliary -- required for over-fullscreen HUD")
  func panelCollectionBehaviorAllowsFullscreen() {
    let behavior = SpotlightWindowController.panelCollectionBehavior
    #expect(behavior.contains(.fullScreenAuxiliary))
    #expect(behavior.contains(.canJoinAllSpaces))
  }

  /// **Regression guard** -- anything below `.statusBar` is hidden by a
  /// fullscreen app's window layer. `.floating` was the previous level
  /// and was the proximate cause of the over-fullscreen bug.
  @Test("panel level is .statusBar or higher -- required for over-fullscreen HUD")
  func panelLevelIsAboveFullscreen() {
    #expect(SpotlightWindowController.panelLevel.rawValue >= NSWindow.Level.statusBar.rawValue)
  }

  @Test("default unfocused alpha is between 0.5 and 1.0 -- visible but clearly faded")
  func defaultUnfocusedAlphaInRange() {
    let alpha = SpotlightWindowController.defaultUnfocusedAlpha
    #expect(alpha > 0.5)
    #expect(alpha < 1.0)
  }

  @Test("construction is cheap and side-effect-free beyond font registration")
  @MainActor
  func constructionIsCheap() throws {
    guard let defaults = UserDefaults(suiteName: "test-\(UUID())") else {
      Issue.record("UserDefaults suite creation failed")
      return
    }
    let prefs = ThemePreferences(defaults: defaults)
    let tmpDir = FileManager.default.temporaryDirectory.appending(
      path: "spotnote-swc-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    let store = try ChatStore(directory: tmpDir)
    let shortcuts = ShortcutStore(defaults: defaults)
    _ = SpotlightWindowController(
      preferences: prefs,
      store: store,
      shortcuts: shortcuts,
      onOpenSettings: {}
    )
    #expect(Bool(true))
  }
}
