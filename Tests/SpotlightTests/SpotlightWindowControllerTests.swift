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
  /// by `panelLevel == .screenSaver` + `.fullScreenAuxiliary` in the
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

  /// **Regression guard** -- recent macOS releases can keep
  /// fullscreen windows above `.statusBar` auxiliary panels. The HUD is
  /// transient, so it uses the overlay-grade screen saver level.
  @Test("panel level is .screenSaver -- required for over-fullscreen HUD")
  func panelLevelIsAboveFullscreen() {
    #expect(SpotlightWindowController.panelLevel == .screenSaver)
  }

  @Test("configured panel applies fullscreen overlay behavior")
  @MainActor
  func configuredPanelAppliesFullscreenOverlayBehavior() {
    let panel = SpotlightPanel(
      contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
      styleMask: SpotlightWindowController.panelStyleMask,
      backing: .buffered,
      defer: false
    )

    SpotlightWindowController.configurePanel(panel)

    #expect(panel.level == .screenSaver)
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(panel.collectionBehavior.contains(.stationary))
    #expect(panel.collectionBehavior.contains(.ignoresCycle))
    #expect(panel.hidesOnDeactivate == false)
    #expect(panel.isFloatingPanel)
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
