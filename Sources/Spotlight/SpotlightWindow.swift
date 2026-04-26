// swiftlint:disable file_length type_body_length function_body_length
// swiftlint:disable cyclomatic_complexity
import AppKit
import Combine
import Core
import SwiftUI

@MainActor
public final class SpotlightWindowController {
  nonisolated static let panelStyleMask: NSWindow.StyleMask = [
    .borderless, .fullSizeContentView
  ]
  /// `.statusBar` floats the HUD above any fullscreen Space. `.floating`
  /// is below the menu-bar / fullscreen layer, so a fullscreen app
  /// would hide the panel even when ordered front.
  nonisolated static let panelLevel: NSWindow.Level = .statusBar
  /// `.fullScreenAuxiliary` is the load-bearing flag -- it lets a panel
  /// appear in a fullscreen Space alongside the fullscreen app.
  /// `.canJoinAllSpaces` keeps the panel reachable from every Space,
  /// and `.stationary` stops it being dragged along during Space
  /// transitions (which would otherwise yank focus during the swipe).
  nonisolated static let panelCollectionBehavior: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .fullScreenAuxiliary, .stationary
  ]
  nonisolated static let defaultUnfocusedAlpha: CGFloat = 0.55

  private var panel: SpotlightPanel?
  private let focusTrigger = FocusTrigger()
  let preferences: ThemePreferences
  let session: ChatSession
  private let shortcuts: ShortcutStore
  let findController = FindController()
  private let fuzzyController = FuzzyController()
  private let commandController = CommandController()
  private let copyController = CopyController()
  let vimController = VimController()
  private let onOpenSettings: () -> Void
  private var observers: [NSObjectProtocol] = []
  private weak var previouslyActiveApp: NSRunningApplication?
  /// Screen-space Y of the panel's intended top edge, cached on first
  /// placement and reused thereafter. Without this, AppKit's first
  /// `makeKeyAndOrderFront` landed the panel ~1pt lower than subsequent
  /// reshows (subpixel arithmetic on `visibleFrame.midY + h * 0.18`
  /// rounded one way for the first orderFront and another after the
  /// window was cached in the Dock server), which made the panel appear
  /// to "jump up" the first time it was re-toggled.
  private var pinnedTopY: CGFloat?
  /// Three-state machine that drives `setPanelHeight`:
  /// - `.none` -- top-anchored at `pinnedTopY` (the rest position).
  /// - `.pendingFirstResize` -- the navigation overlay just appeared;
  ///   the next resize keeps the panel top-anchored so the editor
  ///   doesn't visibly jump, and afterwards captures the new bottom
  ///   edge as the anchor for subsequent cycles.
  /// - `.bottomPinned(y)` -- every later resize while the overlay is
  ///   still visible keeps the panel's bottom at `y`, so chats with
  ///   different line counts grow/shrink the editor upward instead of
  ///   shifting the navigation list around.
  /// Driven by a Combine sink on `session.$navigationPreview`.
  private enum NavAnchorState {
    case none
    case pendingFirstResize
    case bottomPinned(CGFloat)

    var solverAnchor: HUDFrameSolver.NavAnchor {
      switch self {
      case .none: return .none
      case .pendingFirstResize: return .pendingFirstResize
      case .bottomPinned(let y): return .bottomPinned(y: y)
      }
    }
  }
  private var navAnchor: NavAnchorState = .none
  /// Screen-space `y` of the editor card's top edge. Every non-nav
  /// resize (tutorial toggle, editor text growth) keeps this point
  /// fixed so the editor never visually jumps. Reset to nil on every
  /// nav-exit and on `focusOrShow` so the next `setPanelHeight`
  /// re-derives it from the freshly-pinned screen position -- that's
  /// what snaps the drifted-during-cycling editor back to its rest
  /// position the moment the user starts typing again.
  private var editorTopY: CGFloat?
  private var cancellables: Set<AnyCancellable> = []

  /// Layout above the editor card inside the panel (find bar + tutorial
  /// when visible). Used to map between `panel.top` and `editorTopY`.
  private var chromeAboveEditor: CGFloat {
    var height: CGFloat = 0
    if findController.isVisible { height += EditorMetrics.findBarHeight }
    if preferences.showHints { height += EditorMetrics.tutorialBarHeight }
    return height
  }

  /// Layout below the editor card inside the panel -- fuzzy palette or
  /// nav overlay, mutually exclusive. Used by `focusOrShow` to predict
  /// SwiftUI's panel height before activating.
  private var chromeBelowEditor: CGFloat {
    var height: CGFloat = 0
    if preferences.vimMode { height += SpotlightRootView.vimBarHeight }
    if fuzzyController.isVisible {
      height += FuzzyPalette.reservedHeight
    } else if commandController.isVisible {
      height += CommandPalette.reservedHeight
    } else if session.navigationPreview != nil {
      height += NavigationOverlay.reservedHeight
    }
    return height
  }

  /// Total panel height SwiftUI will render with the current state.
  /// Mirrors `SpotlightRootView.extraChromeHeight + editor`.
  private var expectedPanelHeight: CGFloat {
    let lines = EditorMetrics.lineCount(in: session.currentText)
    let editor = EditorMetrics.panelHeight(forLines: lines, maxLines: preferences.maxVisibleLines)
    return editor + chromeAboveEditor + chromeBelowEditor
  }

  public init(
    preferences: ThemePreferences,
    store: ChatStore,
    shortcuts: ShortcutStore,
    onOpenSettings: @escaping () -> Void
  ) {
    self.preferences = preferences
    self.session = ChatSession(store: store)
    self.shortcuts = shortcuts
    self.onOpenSettings = onOpenSettings
    FontLoader.registerBundledFonts()
    observeActiveApp()
    installModifierMonitor()
    observeNavigationPreview()
    installVimCommandRunner()
    Task { [session] in await session.bootstrap() }
  }

  /// Watches for modifier-only key transitions so the navigation
  /// overlay can stay visible while the user holds the cycle modifier
  /// (⌃ by default for ⌃N/⌃P). Releasing the key resumes the normal
  /// auto-dismiss timer in `ChatSession.setNavigationHeldOpen(_:)`.
  private func installModifierMonitor() {
    _ = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      guard let self else { return event }
      let held = event.modifierFlags.contains(.control)
      Task { @MainActor [session = self.session] in
        session.setNavigationHeldOpen(held)
      }
      return event
    }
  }

  /// Flips `navAnchor` between `.none` and `.pendingFirstResize` as the
  /// navigation overlay's visibility toggles. On dismissal we clear the
  /// editor anchor and request an animated next-resize so the panel
  /// smoothly returns to its rest position (the drift accumulated
  /// during bottom-pinned cycling otherwise leaves the editor sitting
  /// where the now-gone nav list used to be).
  private func observeNavigationPreview() {
    session.$navigationPreview
      .map { $0 != nil }
      .removeDuplicates()
      .sink { [weak self] visible in
        MainActor.assumeIsolated {
          guard let self else { return }
          if visible {
            self.navAnchor = .pendingFirstResize
          } else {
            self.editorTopY = nil
            self.navAnchor = .none
          }
        }
      }
      .store(in: &cancellables)
  }

  public func handleHotkey() {
    if let panel, panel.isVisible, panel.isKeyWindow, NSApp.isActive {
      close()
    } else {
      focusOrShow()
    }
  }

  /// Summons the HUD on the most recently edited note with the caret
  /// already at the end. Bound to the `appendToLastNote` global chord
  /// (default ⌘⇧.). Falls back to plain show if the chat list hasn't
  /// finished bootstrapping yet.
  public func handleAppendToLastNote() {
    if panel == nil || panel?.isVisible == false {
      focusOrShow()
    } else {
      NSApp.activate(ignoringOtherApps: true)
      panel?.makeKeyAndOrderFront(nil)
    }
    if let mostRecent = session.chats.first {
      session.jump(to: mostRecent)
    }
    // Defer the caret bump one runloop tick so SwiftUI has a chance to
    // propagate the new chat's text into the NSTextView before we ask
    // for end-of-text.
    DispatchQueue.main.async { [weak self] in
      self?.focusTrigger.requestCaretEnd()
    }
  }

  public func close() {
    panel?.orderOut(nil)
    // If a bona-fide SpotNote window (Settings) is visible, leave the
    // app active so the user can keep working there. Filter to
    // `canBecomeMain` windows -- the panel itself, SwiftUI hosting
    // scratch windows, and AppKit's internal helper windows all report
    // `canBecomeMain == false`, which caused the previous
    // `$0.isVisible`-only check to spuriously retain focus and break
    // the Terminal -> HUD -> Terminal toggle.
    let hasVisibleMainWindow = NSApp.windows.contains { window in
      window !== panel && window.isVisible && window.canBecomeMain
    }
    if hasVisibleMainWindow { return }
    let target = previouslyActiveApp
    previouslyActiveApp = nil
    NSApp.hide(nil)
    if let target, target.bundleIdentifier != Bundle.main.bundleIdentifier {
      target.activate()
    }
  }

  private func focusOrShow() {
    let panel = panel ?? makePanel()
    self.panel = panel
    if !NSApp.isActive {
      previouslyActiveApp = NSWorkspace.shared.frontmostApplication
    }
    if !panel.isVisible {
      editorTopY = nil
      repositionForShow(panel)
    }
    panel.alphaValue = 1.0
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    focusTrigger.pulse()
  }

  private func repositionForShow(_ panel: NSPanel) {
    guard let screen = NSScreen.main else { return }
    let screenFrame = screen.visibleFrame
    let height = expectedPanelHeight
    let top: CGFloat
    if let cached = pinnedTopY {
      top = cached
    } else {
      top = (screenFrame.midY + screenFrame.height * 0.18 + height / 2).rounded()
      pinnedTopY = top
    }
    let x = (screenFrame.midX - panel.frame.width / 2).rounded()
    panel.setFrame(
      NSRect(x: x, y: top - height, width: panel.frame.width, height: height),
      display: false
    )
  }

  private func makePanel() -> SpotlightPanel {
    let initialHeight = EditorMetrics.panelHeight(
      forLines: 1,
      maxLines: preferences.maxVisibleLines
    )
    let size = NSSize(width: EditorMetrics.panelWidth, height: initialHeight)
    let panel = SpotlightPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: Self.panelStyleMask,
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.isMovableByWindowBackground = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = NSHostingView(
      rootView: SpotlightRootView(
        focusTrigger: focusTrigger,
        preferences: preferences,
        session: session,
        shortcuts: shortcuts,
        find: findController,
        fuzzy: fuzzyController,
        command: commandController,
        copy: copyController,
        vimController: vimController,
        onHeightChange: { [weak self] height in
          self?.setPanelHeight(height, animated: false)
        },
        onEscape: { [weak self] in
          self?.close()
        }
      )
    )
    panel.keyEquivalentHandler = { [weak self] event in
      self?.handleKeyEquivalent(event) ?? false
    }
    observeKeyState(panel)
    return panel
  }

  private static let driftCorrectionThreshold: CGFloat = 4

  private func pinnedOrigin(for panel: NSPanel) -> NSPoint? {
    guard let screen = NSScreen.main else { return nil }
    let screenFrame = screen.visibleFrame
    let top: CGFloat
    if let cached = pinnedTopY {
      top = cached
    } else {
      let initialHeight = EditorMetrics.panelHeight(
        forLines: 1,
        maxLines: preferences.maxVisibleLines
      )
      top = (screenFrame.midY + screenFrame.height * 0.18 + initialHeight / 2).rounded()
      pinnedTopY = top
    }
    let x = (screenFrame.midX - panel.frame.width / 2).rounded()
    let y = top - panel.frame.height
    return NSPoint(x: x, y: y)
  }

  private func correctDriftIfNeeded(_ panel: NSPanel) {
    guard let target = pinnedOrigin(for: panel) else { return }
    let current = panel.frame.origin
    let dx = abs(current.x - target.x)
    let dy = abs(current.y - target.y)
    guard dx > 0 || dy > 0 else { return }
    guard dx <= Self.driftCorrectionThreshold, dy <= Self.driftCorrectionThreshold else {
      return
    }
    panel.setFrameOrigin(target)
  }

  private func setPanelHeight(_ height: CGFloat, animated: Bool) {
    guard let panel else { return }
    let current = panel.frame
    let chromeAbove = chromeAboveEditor
    let resolved = HUDFrameSolver.resolveNewY(
      anchor: navAnchor.solverAnchor,
      currentOriginY: current.origin.y,
      currentHeight: current.size.height,
      newHeight: height,
      chromeAbove: chromeAbove,
      cachedEditorTopY: editorTopY,
      pinnedTopY: pinnedTopY
    )
    let newY = resolved.newOriginY
    if let updated = resolved.editorTopY { editorTopY = updated }
    let newFrame = NSRect(
      x: current.origin.x,
      y: newY,
      width: current.size.width,
      height: height
    )
    panel.setFrame(newFrame, display: true, animate: animated)
    if case .pendingFirstResize = navAnchor {
      // The overlay is now on screen. Lock its bottom edge for every
      // subsequent cycle.
      navAnchor = .bottomPinned(newY)
    }
  }

}

extension SpotlightWindowController {
  private func observeKeyState(_ panel: SpotlightPanel) {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: NSWindow.didResignKeyNotification,
        object: panel,
        queue: .main
      ) { [weak self, weak panel] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          if self.preferences.dimOnFocusLoss {
            panel?.animator().alphaValue = CGFloat(self.preferences.unfocusedOpacity)
          } else {
            self.close()
          }
        }
      }
    )
    observers.append(
      center.addObserver(
        forName: NSWindow.didBecomeKeyNotification,
        object: panel,
        queue: .main
      ) { [weak self, weak panel] _ in
        MainActor.assumeIsolated {
          panel?.animator().alphaValue = 1.0
          if let self, let panel { self.correctDriftIfNeeded(panel) }
        }
      }
    )
    observers.append(
      center.addObserver(
        forName: NSWindow.didMoveNotification,
        object: panel,
        queue: .main
      ) { [weak self, weak panel] _ in
        MainActor.assumeIsolated {
          guard let self, let panel else { return }
          let newTop = panel.frame.origin.y + panel.frame.size.height
          self.pinnedTopY = newTop
          self.editorTopY = newTop - self.chromeAboveEditor
        }
      }
    )
  }
  /// Called from `SpotlightPanel.performKeyEquivalent(with:)` so every
  /// chord in the HUD -- chat navigation, settings, undo, tutorial
  /// toggle -- flows through a single user-customizable binding table
  /// AND participates in AppKit's key-equivalent responder chain.
  /// Returning `true` tells macOS the event was consumed (no beep).
  ///
  private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
    // #lizard forgives
    if MainActor.assumeIsolated({ commandController.isVisible }) {
      if event.keyCode == 53 {
        MainActor.assumeIsolated { commandController.close() }
        return true
      }
      if event.keyCode == 36 || event.keyCode == 76 {
        return true
      }
    }
    let mask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    let mods = ShortcutModifierSet(event.modifierFlags.intersection(mask))
    let chars = Shortcut.normalize(event.charactersIgnoringModifiers ?? "")
    let resolved = MainActor.assumeIsolated { shortcuts.match(key: chars, modifiers: mods) }
    guard let action = resolved else { return false }
    if action == .toggleHotkey || action == .appendToLastNote { return false }
    if MainActor.assumeIsolated({ commandController.isVisible }) {
      switch action {
      case .olderChat, .newerChat:
        let delta = action == .olderChat ? 1 : -1
        Task { @MainActor [weak self] in self?.commandController.moveSelection(by: delta) }
        return true
      default: break
      }
    }
    if !shouldHandle(action: action) {
      if action == .copyContent {
        MainActor.assumeIsolated {
          _ = panel?.firstResponder?.tryToPerform(#selector(NSText.copy(_:)), with: nil)
        }
        return true
      }
      return false
    }
    if action == .newChat || action == .deleteChat, event.isARepeat { return true }
    Task { @MainActor [weak self] in self?.dispatch(action) }
    return true
  }

  /// Pass-through gates for context-sensitive shortcuts (undo with no
  /// pending delete, copy with an active selection).
  private func shouldHandle(action: ShortcutAction) -> Bool {
    if action == .undoDelete {
      return MainActor.assumeIsolated { session.lastDeleted != nil }
    }
    if action == .copyContent {
      let hasSelection = MainActor.assumeIsolated {
        (panel?.firstResponder as? NSTextView).map { $0.selectedRange.length > 0 } ?? false
      }
      return !hasSelection
    }
    return true
  }

  // #lizard forgives
  private func dispatch(_ action: ShortcutAction) {
    switch action {
    case .newChat, .olderChat, .newerChat, .deleteChat, .undoDelete:
      dispatchSessionAction(action)
    case .findInNote:
      if fuzzyController.isVisible { fuzzyController.close() }
      if commandController.isVisible { commandController.close() }
      findController.toggle(text: session.currentText)
    case .fuzzyFindAll:
      if findController.isVisible { findController.close() }
      if commandController.isVisible { commandController.close() }
      fuzzyController.toggle(corpus: session.chats)
    case .commandPalette:
      if findController.isVisible { findController.close() }
      if fuzzyController.isVisible { fuzzyController.close() }
      commandController.toggle(shortcuts: shortcuts, preferences: preferences)
    case .pinNote:
      Task { await session.togglePin() }
    case .copyContent:
      copyController.copy(session.currentText)
    case .openSettings: onOpenSettings()
    case .toggleTutorial: preferences.showHints.toggle()
    case .toggleHotkey, .appendToLastNote: break
    }
  }

  private func dispatchSessionAction(_ action: ShortcutAction) {
    let session = self.session
    switch action {
    case .newChat: Task { await session.newChat() }
    case .olderChat: Task { await session.cycleOlder() }
    case .newerChat: Task { await session.cycleNewer() }
    case .deleteChat: Task { await session.deleteCurrent() }
    case .undoDelete: Task { await session.undoDelete() }
    default: break
    }
  }

  private func observeActiveApp() {
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didResignActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          let next = NSWorkspace.shared.frontmostApplication
          if next?.bundleIdentifier != Bundle.main.bundleIdentifier {
            self?.previouslyActiveApp = next
          }
        }
      }
    )
  }
}
