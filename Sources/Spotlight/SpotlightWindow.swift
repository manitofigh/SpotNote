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
  /// `.screenSaver` keeps the HUD above the window layers used by
  /// fullscreen apps. Lower levels such as `.floating` and `.statusBar`
  /// can still be occluded by fullscreen windows on recent macOS
  /// releases even when the panel joins that Space.
  nonisolated static let panelLevel: NSWindow.Level = .screenSaver
  /// `.canJoinAllApplications` is the cross-app fullscreen guard:
  /// without it, an LSUIElement HUD can activate while the fullscreen
  /// app visibly blurs/refocuses, but the panel is not admitted into
  /// that app's fullscreen Space.
  /// `.canJoinAllSpaces` keeps the panel reachable from every Space,
  /// `.fullScreenAuxiliary` lets it sit alongside fullscreen windows,
  /// `.transient` keeps it in the floating Spaces group. `.stationary`
  /// looks tempting for all-space overlays, but AppKit treats it like
  /// desktop chrome; fullscreen Spaces can then leave a reused panel
  /// behind the fullscreen layer.
  /// `.ignoresCycle` keeps this transient HUD out of Cmd-` cycling.
  nonisolated static let panelCollectionBehavior: NSWindow.CollectionBehavior = [
    .canJoinAllApplications, .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle
  ]
  nonisolated static let defaultUnfocusedAlpha: CGFloat = 0.55

  private var panel: SpotlightPanel?
  private var fuzzyPreviewPanel: FuzzyPreviewPanel?
  private let focusTrigger = FocusTrigger()
  let preferences: ThemePreferences
  let session: ChatSession
  private let shortcuts: ShortcutStore
  private let defaults: UserDefaults
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
  /// Screen-space X of the panel's intended left edge. Kept alongside the
  /// top edge so shortcut moves survive both HUD dismissal and relaunch.
  private var pinnedOriginX: CGFloat?
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
  private enum FuzzyPreviewSide {
    case left
    case right
  }
  private var navAnchor: NavAnchorState = .none
  private struct MeasuredHeightCache {
    let text: String
    let maxVisibleLines: Int
    let chromeAbove: CGFloat
    let chromeBelow: CGFloat
    let height: CGFloat
  }

  /// Screen-space `y` of the editor card's top edge. Every non-nav
  /// resize (tutorial toggle, editor text growth) keeps this point
  /// fixed so the editor never visually jumps. Reset to nil on every
  /// nav-exit and on `focusOrShow` so the next `setPanelHeight`
  /// re-derives it from the freshly-pinned screen position -- that's
  /// what snaps the drifted-during-cycling editor back to its rest
  /// position the moment the user starts typing again.
  private var editorTopY: CGFloat?
  private var measuredHeightCache: MeasuredHeightCache?
  private var programmaticFrameToIgnore: NSRect?
  private var isMovingHUD = false
  private var cancellables: Set<AnyCancellable> = []
  private struct FuzzyEditorSnapshot {
    let chatID: UUID?
    let selectedRange: NSRange
    let selectionAffinity: NSSelectionAffinity
  }
  private var fuzzyEditorSnapshot: FuzzyEditorSnapshot?

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
    if preferences.vimMode || preferences.showWordCount {
      height += SpotlightRootView.bottomBarHeight
    }
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
    let chromeAbove = chromeAboveEditor
    let chromeBelow = chromeBelowEditor
    if let measuredHeightCache {
      if hasMeasuredHeight(forChromeAbove: chromeAbove, chromeBelow: chromeBelow) {
        return measuredHeightCache.height
      }
    }
    let lines = EditorMetrics.lineCount(in: session.currentText)
    let editor = EditorMetrics.panelHeight(forLines: lines, maxLines: preferences.maxVisibleLines)
    return editor + chromeAbove + chromeBelow
  }

  private func hasMeasuredHeight(forChromeAbove chromeAbove: CGFloat, chromeBelow: CGFloat) -> Bool {
    guard let measuredHeightCache else { return false }
    return measuredHeightCache.text == session.currentText
      && measuredHeightCache.maxVisibleLines == preferences.maxVisibleLines
      && measuredHeightCache.chromeAbove == chromeAbove
      && measuredHeightCache.chromeBelow == chromeBelow
  }

  public init(
    preferences: ThemePreferences,
    store: ChatStore,
    shortcuts: ShortcutStore,
    onOpenSettings: @escaping () -> Void,
    defaults: UserDefaults = .standard
  ) {
    self.preferences = preferences
    self.session = ChatSession(store: store)
    self.shortcuts = shortcuts
    self.defaults = defaults
    self.onOpenSettings = onOpenSettings
    FontLoader.registerBundledFonts()
    observeActiveApp()
    installModifierMonitor()
    observeNavigationPreview()
    observeFuzzyPreview()
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

  private func observeFuzzyPreview() {
    fuzzyController.$isVisible
      .combineLatest(fuzzyController.$results, fuzzyController.$selectedIndex)
      .sink { [weak self] isVisible, _, _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          if !isVisible { self.restoreFuzzyEditorState() }
          self.syncFuzzyPreviewPanel()
        }
      }
      .store(in: &cancellables)
  }

  private func restoreFuzzyEditorState() {
    guard let snapshot = fuzzyEditorSnapshot else { return }
    fuzzyEditorSnapshot = nil
    focusTrigger.pulse()

    // A palette dismissal can happen before SwiftUI has committed the
    // editor's restored subtree. Wait one main-run-loop turn so the
    // editor is present and its text has been updated before restoring
    // the exact selection.
    guard snapshot.chatID == session.currentID else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, let textView = self.editorTextView() else { return }
      let length = (textView.string as NSString).length
      let location = min(max(0, snapshot.selectedRange.location), length)
      let selectionLength = min(
        max(0, snapshot.selectedRange.length),
        max(0, length - location)
      )
      let range = NSRange(location: location, length: selectionLength)
      textView.window?.makeFirstResponder(textView)
      textView.setSelectedRange(
        range,
        affinity: snapshot.selectionAffinity,
        stillSelecting: false
      )
      textView.scrollRangeToVisible(range)
    }
  }

  private func syncFuzzyPreviewPanel() {
    guard
      fuzzyController.isVisible,
      fuzzyController.selectedResult() != nil,
      let panel,
      panel.isVisible,
      let frame = fuzzyPreviewFrame(for: panel)
    else {
      fuzzyPreviewPanel?.orderOut(nil)
      return
    }
    let preview = fuzzyPreviewPanel ?? makeFuzzyPreviewPanel(parent: panel)
    fuzzyPreviewPanel = preview
    if preview.parent !== panel {
      panel.addChildWindow(preview, ordered: .above)
    }
    if !Self.rect(preview.frame, isApproximatelyEqualTo: frame) {
      preview.setFrame(frame, display: true)
    }
    if !preview.isVisible {
      preview.orderFrontRegardless()
    }
  }

  private func fuzzyPreviewFrame(for panel: NSPanel) -> NSRect? {
    let screenFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
    guard let screenFrame else { return nil }
    let panelFrame = panel.frame
    let gap = FuzzyPreviewCard.gap
    let rightSpace = screenFrame.maxX - panelFrame.maxX - gap
    let leftSpace = panelFrame.minX - screenFrame.minX - gap
    let preferred = FuzzyPreviewCard.preferredWidth
    let minimum = FuzzyPreviewCard.minimumWidth
    let side: FuzzyPreviewSide
    let width: CGFloat
    if rightSpace >= preferred {
      side = .right
      width = preferred
    } else if leftSpace >= preferred {
      side = .left
      width = preferred
    } else if rightSpace >= leftSpace, rightSpace >= minimum {
      side = .right
      width = rightSpace
    } else if leftSpace >= minimum {
      side = .left
      width = leftSpace
    } else {
      return nil
    }
    let height = min(panelFrame.height, screenFrame.height)
    let y = min(panelFrame.maxY, screenFrame.maxY) - height
    let x: CGFloat
    switch side {
    case .right: x = panelFrame.maxX + gap
    case .left: x = panelFrame.minX - gap - width
    }
    return NSRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
  }

  public func handleHotkey() {
    if let panel, panel.isVisible, panel.isKeyWindow, NSApp.isActive {
      close()
    } else {
      focusOrShow()
    }
  }

  public func openHUD() {
    focusOrShow()
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
      if let panel { bringPanelToFront(panel) }
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

  public func reloadLibrary() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.session.reload()
      self.fuzzyController.updateCorpus(self.session.chats)
    }
  }

  public func close() {
    if fuzzyController.isVisible { fuzzyController.close() }
    fuzzyPreviewPanel?.orderOut(nil)
    if let panel, panel.isVisible { persistHUDPosition(of: panel) }
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
    bringPanelToFront(panel)
    focusTrigger.pulse()
  }

  private func bringPanelToFront(_ panel: NSPanel) {
    Self.configurePanel(panel)
    panel.orderFrontRegardless()
    panel.makeKeyAndOrderFront(nil)
    panel.orderFrontRegardless()
    syncFuzzyPreviewPanel()
  }

  private func repositionForShow(_ panel: NSPanel) {
    guard let screen = NSScreen.main else { return }
    let screenFrame = screen.visibleFrame
    let height = expectedPanelHeight
    let stored = HUDPositionStore.load(from: defaults)
    let fallbackTop = (screenFrame.midY + screenFrame.height * 0.18 + height / 2).rounded()
    let desired = HUDPosition(
      originX: pinnedOriginX
        ?? stored?.originX
        ?? (screenFrame.midX - panel.frame.width / 2).rounded(),
      topY: pinnedTopY ?? stored?.topY ?? fallbackTop
    )
    let resolved = HUDPositionStore.frame(
      for: desired,
      size: CGSize(width: panel.frame.width, height: height),
      in: screenFrame
    )
    pinnedOriginX = resolved.minX
    pinnedTopY = resolved.maxY
    setPanelFrame(resolved, display: false)
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
    Self.configurePanel(panel)
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
        },
        onCommand: { [weak self] action in
          self?.executeCommandPaletteAction(action)
        },
        onFuzzyPick: { [weak self] chat in
          self?.selectFuzzyResult(chat)
        }
      )
    )
    panel.keyEquivalentHandler = { [weak self] event in
      self?.handleKeyEquivalent(event) ?? false
    }
    observeKeyState(panel)
    return panel
  }

  static func configurePanel(_ panel: NSPanel) {
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isFloatingPanel = true
    panel.level = panelLevel
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.isMovableByWindowBackground = true
    panel.collectionBehavior = panelCollectionBehavior
  }

  private func makeFuzzyPreviewPanel(parent: NSPanel) -> FuzzyPreviewPanel {
    let preview = FuzzyPreviewPanel(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: FuzzyPreviewCard.preferredWidth,
        height: max(parent.frame.height, FuzzyPalette.reservedHeight)
      ),
      styleMask: Self.panelStyleMask,
      backing: .buffered,
      defer: false
    )
    Self.configurePanel(preview)
    preview.hasShadow = false
    preview.ignoresMouseEvents = false
    preview.contentView = NSHostingView(
      rootView: FuzzyPreviewCard(
        controller: fuzzyController,
        preferences: preferences
      )
    )
    parent.addChildWindow(preview, ordered: .above)
    return preview
  }

  private static let driftCorrectionThreshold: CGFloat = 4
  private static let hudMoveStep: CGFloat = 40

  private func pinnedOrigin(for panel: NSPanel) -> NSPoint? {
    guard let screen = NSScreen.main else { return nil }
    let screenFrame = screen.visibleFrame
    let stored = HUDPositionStore.load(from: defaults)
    let initialHeight = EditorMetrics.panelHeight(
      forLines: 1,
      maxLines: preferences.maxVisibleLines
    )
    let fallbackTop = (screenFrame.midY + screenFrame.height * 0.18 + initialHeight / 2).rounded()
    let desired = HUDPosition(
      originX: pinnedOriginX
        ?? stored?.originX
        ?? (screenFrame.midX - panel.frame.width / 2).rounded(),
      topY: pinnedTopY ?? stored?.topY ?? fallbackTop
    )
    let resolved = HUDPositionStore.frame(
      for: desired,
      size: panel.frame.size,
      in: screenFrame
    )
    pinnedOriginX = resolved.minX
    pinnedTopY = resolved.maxY
    return resolved.origin
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
    setPanelFrame(
      NSRect(origin: target, size: panel.frame.size),
      display: true
    )
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
    measuredHeightCache = MeasuredHeightCache(
      text: session.currentText,
      maxVisibleLines: preferences.maxVisibleLines,
      chromeAbove: chromeAbove,
      chromeBelow: chromeBelowEditor,
      height: height
    )
    setPanelFrame(newFrame, display: true, animate: animated)
    if case .pendingFirstResize = navAnchor {
      // The overlay is now on screen. Lock its bottom edge for every
      // subsequent cycle.
      navAnchor = .bottomPinned(newY)
    }
  }

  private func setPanelFrame(_ frame: NSRect, display: Bool, animate: Bool = false) {
    guard let panel else { return }
    programmaticFrameToIgnore = frame
    panel.setFrame(frame, display: display, animate: animate)
    syncFuzzyPreviewPanel()
  }

  private func shouldIgnoreProgrammaticMove(_ frame: NSRect) -> Bool {
    guard let expected = programmaticFrameToIgnore else { return false }
    guard Self.rect(frame, isApproximatelyEqualTo: expected) else { return false }
    programmaticFrameToIgnore = nil
    return true
  }

  private static func rect(_ lhs: NSRect, isApproximatelyEqualTo rhs: NSRect) -> Bool {
    let tolerance: CGFloat = 0.5
    return abs(lhs.origin.x - rhs.origin.x) <= tolerance
      && abs(lhs.origin.y - rhs.origin.y) <= tolerance
      && abs(lhs.size.width - rhs.size.width) <= tolerance
      && abs(lhs.size.height - rhs.size.height) <= tolerance
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
          if self.isMovingHUD { return }
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
          if self.shouldIgnoreProgrammaticMove(panel.frame) { return }
          let newTop = panel.frame.origin.y + panel.frame.size.height
          self.pinnedOriginX = panel.frame.origin.x
          self.pinnedTopY = newTop
          self.editorTopY = newTop - self.chromeAboveEditor
          self.persistHUDPosition(of: panel)
          self.syncFuzzyPreviewPanel()
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
        MainActor.assumeIsolated { executeSelectedCommand() }
        return true
      }
    }
    if MainActor.assumeIsolated({ fuzzyController.isVisible }) {
      if event.keyCode == 53 {
        MainActor.assumeIsolated { fuzzyController.close() }
        return true
      }
      if event.keyCode == 36 || event.keyCode == 76 {
        MainActor.assumeIsolated { openSelectedFuzzyResult() }
        return true
      }
    }
    if event.keyCode == 36 || event.keyCode == 76 {
      if MainActor.assumeIsolated({ session.commitNavigationSelection() }) {
        return true
      }
    }
    let mask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    let mods = ShortcutModifierSet(event.modifierFlags.intersection(mask))
    let chars = Shortcut.key(from: event)

    // Search fields own their own edit history. Let Cmd-Z pass through to
    // the focused palette/find field instead of undoing the note behind it.
    let paletteIsVisible = MainActor.assumeIsolated {
      commandController.isVisible || fuzzyController.isVisible || findController.isVisible
    }
    if mods == .command || mods == [.command, .shift], chars == "z" {
      if paletteIsVisible { return false }
      if mods == .command, let textView = editorTextView(), textView.canUndoText {
        return textView.performTextUndo()
      }
      if mods == [.command, .shift], let textView = editorTextView() {
        return textView.performTextRedo()
      }
    }
    let resolved = MainActor.assumeIsolated { shortcuts.match(key: chars, modifiers: mods) }
    guard let action = resolved else { return false }
    if action == .toggleHotkey || action == .appendToLastNote { return false }
    if MainActor.assumeIsolated({ commandController.isVisible }) {
      switch action {
      case .commandPalette:
        MainActor.assumeIsolated { commandController.requestFocus() }
        return true
      case .olderChat, .newerChat:
        let delta = action == .olderChat ? 1 : -1
        Task { @MainActor [weak self] in self?.commandController.moveSelection(by: delta) }
        return true
      default: break
      }
    }
    if MainActor.assumeIsolated({ fuzzyController.isVisible }) {
      switch action {
      case .olderChat, .newerChat:
        let delta = action == .olderChat ? 1 : -1
        Task { @MainActor [weak self] in self?.fuzzyController.moveSelection(by: delta) }
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
    if isHUDMove(action) {
      dispatch(action)
      return true
    }
    if action == .newChat || action == .deleteChat, event.isARepeat { return true }
    Task { @MainActor [weak self] in self?.dispatch(action) }
    return true
  }

  private func isHUDMove(_ action: ShortcutAction) -> Bool {
    switch action {
    case .moveHUDLeft, .moveHUDRight, .moveHUDDown, .moveHUDUp: return true
    default: return false
    }
  }

  private func openSelectedFuzzyResult() {
    guard let chat = fuzzyController.selectedChat() else { return }
    selectFuzzyResult(chat)
  }

  private func selectFuzzyResult(_ chat: Chat) {
    // The fuzzy corpus is based on persisted chats while the editor can
    // contain newer unsaved text. Reassigning the current chat here would
    // replace that live text with the stale corpus snapshot.
    if chat.id != session.currentID {
      session.jump(to: chat)
    }
    fuzzyController.close()
  }

  private func executeSelectedCommand() {
    guard let action = commandController.selectedExecutableAction() else { return }
    executeCommandPaletteAction(action)
  }

  private func executeCommandPaletteAction(_ action: ShortcutAction) {
    commandController.close()
    dispatch(action)
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
    case .moveHUDLeft, .moveHUDRight, .moveHUDDown, .moveHUDUp:
      moveHUD(action)
    case .newChat, .olderChat, .newerChat, .deleteChat, .undoDelete:
      dispatchSessionAction(action)
    case .findInNote:
      if fuzzyController.isVisible { fuzzyController.close() }
      if commandController.isVisible { commandController.close() }
      findController.toggle(text: session.currentText)
    case .fuzzyFindAll:
      if findController.isVisible { findController.close() }
      if commandController.isVisible { commandController.close() }
      toggleFuzzyPalette()
    case .commandPalette:
      if findController.isVisible { findController.close() }
      if fuzzyController.isVisible { fuzzyController.close() }
      commandController.toggle(shortcuts: shortcuts, preferences: preferences)
    case .insertTodayBadge:
      _ = editorTextView()?.tryToPerform(
        #selector(PlaceholderTextView.insertTodayBadgeToken(_:)),
        with: nil
      )
    case .insertChecklist:
      _ = editorTextView()?.tryToPerform(
        #selector(PlaceholderTextView.insertChecklistToken(_:)),
        with: nil
      )
    case .toggleChecklist:
      _ = editorTextView()?.tryToPerform(
        #selector(PlaceholderTextView.toggleChecklistShortcut(_:)),
        with: nil
      )
    case .pinNote:
      Task { await session.togglePin() }
    case .shareCurrentChat:
      shareCurrentChat()
    case .copyContent:
      copyController.copy(session.currentText)
    case .openSettings: onOpenSettings()
    case .toggleTutorial: preferences.showHints.toggle()
    case .toggleHotkey, .appendToLastNote: break
    }
  }

  private func toggleFuzzyPalette() {
    if fuzzyController.isVisible {
      fuzzyController.close()
      return
    }

    if let textView = editorTextView() {
      fuzzyEditorSnapshot = FuzzyEditorSnapshot(
        chatID: session.currentID,
        selectedRange: textView.selectedRange,
        selectionAffinity: textView.selectionAffinity
      )
    } else {
      fuzzyEditorSnapshot = nil
    }
    fuzzyController.open(corpus: session.chats)
  }

  private func moveHUD(_ action: ShortcutAction) {
    guard let panel else { return }
    isMovingHUD = true
    defer { isMovingHUD = false }
    let step = Self.hudMoveStep
    var frame = panel.frame
    switch action {
    case .moveHUDLeft: frame.origin.x -= step
    case .moveHUDRight: frame.origin.x += step
    case .moveHUDDown: frame.origin.y -= step
    case .moveHUDUp: frame.origin.y += step
    default: return
    }
    let screenFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
    if let screenFrame {
      frame.origin.x = min(max(frame.origin.x, screenFrame.minX), screenFrame.maxX - frame.width)
      frame.origin.y = min(max(frame.origin.y, screenFrame.minY), screenFrame.maxY - frame.height)
    }
    frame.origin.x = frame.origin.x.rounded()
    frame.origin.y = frame.origin.y.rounded()
    pinnedOriginX = frame.origin.x
    pinnedTopY = frame.maxY
    editorTopY = frame.maxY - chromeAboveEditor
    setPanelFrame(frame, display: true)
    persistHUDPosition(of: panel)
    panel.alphaValue = 1.0
    bringPanelToFront(panel)
  }

  private func persistHUDPosition(of panel: NSPanel) {
    let position = HUDPosition(originX: panel.frame.minX, topY: panel.frame.maxY)
    pinnedOriginX = position.originX
    pinnedTopY = position.topY
    HUDPositionStore.save(position, to: defaults)
  }

  private func editorTextView() -> PlaceholderTextView? {
    findEditorTextView(in: panel?.contentView)
  }

  private func findEditorTextView(in view: NSView?) -> PlaceholderTextView? {
    guard let view else { return nil }
    if let textView = view as? PlaceholderTextView { return textView }
    for subview in view.subviews {
      if let textView = findEditorTextView(in: subview) { return textView }
    }
    return nil
  }

  private func shareCurrentChat() {
    guard let chat = session.currentChatSnapshot(), let view = panel?.contentView else {
      NSSound.beep()
      return
    }
    do {
      try ChatTransferService.share(chats: [chat], from: view)
    } catch {
      NSSound.beep()
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
