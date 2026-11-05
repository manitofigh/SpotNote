// swiftlint:disable function_body_length
import AppKit
import Carbon.HIToolbox
import Combine
import Core
import CoreServices
import Spotlight

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private lazy var preferences = ThemePreferences()
  private lazy var shortcutStore = ShortcutStore()
  private lazy var settings = SettingsWindowController(
    preferences: preferences,
    shortcuts: shortcutStore,
    store: chatStore,
    storage: storage,
    onLibraryChanged: { [weak self] in self?.handleLibraryChangedFromSettings() }
  )
  private lazy var storage = StorageLocationController()
  private lazy var chatStore: ChatStore = {
    if let store = makeConfiguredChatStore() {
      return store
    }
    let fallback = FileManager.default.temporaryDirectory.appending(
      path: "SpotNote-Chats-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    guard let store = try? ChatStore(directory: fallback) else {
      fatalError("ChatStore fallback directory unreachable: \(fallback.path)")
    }
    return store
  }()
  private lazy var spotlight = SpotlightWindowController(
    preferences: preferences,
    store: chatStore,
    shortcuts: shortcutStore,
    onOpenSettings: { [weak self] in self?.showSettings() },
    history: NoteHistoryStore.shared
  )
  private var menuBar: MenuBarController?
  private var hotkey: GlobalHotkey?
  private var appendHotkey: GlobalHotkey?
  private var onboarding: OnboardingController?
  private var cancellables: Set<AnyCancellable> = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    DockIconSwitcher.applyVisibility(preferences.showDockIcon)
    MainMenu.install(onOpenSettings: { [weak self] in self?.showSettings() })

    enableLaunchAtLoginIfFirstRun()

    menuBar = MenuBarController(
      preferences: preferences,
      onOpenSettings: { [weak self] in self?.showSettings() }
    )

    NotificationCenter.default.addObserver(
      forName: .spotNoteCheckForUpdates,
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { UpdateController.shared.checkForUpdates(nil) }
    }

    hotkey = GlobalHotkey { [weak self] in
      guard let self else { return }
      if let onboarding = self.onboarding, onboarding.isActive {
        onboarding.handleGlobalToggleChord()
        return
      }
      self.spotlight.handleHotkey()
    }
    appendHotkey = GlobalHotkey { [weak self] in
      guard let self else { return }
      if self.onboarding?.isActive == true { return }
      self.spotlight.handleAppendToLastNote()
    }
    DockIconSwitcher.apply(preferences.dockIconStyle)
    // Force the Spotlight controller to initialize so its key monitor is
    // installed before the user presses the toggle chord.
    _ = spotlight
    applyToggleHotkey(shortcutStore.binding(for: .toggleHotkey))
    applyAppendHotkey(shortcutStore.binding(for: .appendToLastNote))

    shortcutStore.$bindings
      .map { $0[.toggleHotkey] ?? ShortcutAction.toggleHotkey.defaultShortcut }
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] shortcut in
        MainActor.assumeIsolated { self?.applyToggleHotkey(shortcut) }
      }
      .store(in: &cancellables)

    shortcutStore.$bindings
      .map { $0[.appendToLastNote] ?? ShortcutAction.appendToLastNote.defaultShortcut }
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] shortcut in
        MainActor.assumeIsolated { self?.applyAppendHotkey(shortcut) }
      }
      .store(in: &cancellables)

    preferences.$showDockIcon
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] show in
        MainActor.assumeIsolated {
          DockIconSwitcher.applyVisibility(show)
          if show {
            DockIconSwitcher.apply(self?.preferences.dockIconStyle ?? .dark)
          }
        }
      }
      .store(in: &cancellables)

    preferences.$dockIconStyle
      .removeDuplicates()
      .dropFirst()
      .sink { style in
        MainActor.assumeIsolated { DockIconSwitcher.apply(style) }
      }
      .store(in: &cancellables)

    observeStorageChanges()

    let didPresentOnboarding = presentOnboardingIfNeeded()
    if !didPresentOnboarding && !Self.wasLaunchedAsBackgroundItem {
      spotlight.openHUD()
    }
  }

  /// Opens the store at the user's chosen location. A Markdown folder that
  /// can't be opened falls back to built-in storage (the controller shows
  /// why); nil only if even built-in storage is unreachable.
  private func makeConfiguredChatStore() -> ChatStore? {
    let builtIn: URL
    do {
      builtIn = try ChatStore.defaultDirectory()
    } catch {
      NSLog("SpotNote: built-in storage unavailable: \(error)")
      return nil
    }
    let configuration = storage.launchConfiguration(builtInDirectory: builtIn)
    do {
      return try ChatStore(configuration: configuration)
    } catch {
      if configuration.markdownFolder != nil { storage.reportLaunchFailure(error) }
      do {
        return try ChatStore(directory: builtIn)
      } catch {
        NSLog("SpotNote: built-in storage unavailable: \(error)")
        return nil
      }
    }
  }

  /// Picks up notes changed by other apps / devices (folder mode) each
  /// time SpotNote becomes active, and reloads the HUD if anything moved.
  private func observeStorageChanges() {
    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.syncStorage() }
    }
    syncStorage()
    if let issue = storage.issue { presentStorageIssue(issue) }
  }

  private func syncStorage() {
    let store = chatStore
    // Save the live editor text before rescanning so an unsaved edit goes
    // through the store's conflict handling instead of being re-pushed
    // over an external edit by the reload afterwards.
    let unsaved = spotlight.unsavedEditorSnapshot()
    Task { @MainActor [weak self] in
      if let unsaved { await store.update(id: unsaved.id, text: unsaved.text) }
      guard let self, await self.storage.sync(store: store) else { return }
      self.spotlight.reloadLibrary(pushingLiveText: false)
    }
  }

  private func presentStorageIssue(_ issue: String) {
    let alert = NSAlert()
    alert.messageText = "Notes folder unavailable"
    alert.informativeText = issue
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "OK")
    if alert.runModal() == .alertFirstButtonReturn { showSettings() }
  }

  private func presentOnboardingIfNeeded() -> Bool {
    guard OnboardingController.shouldShow() else { return false }
    let controller = OnboardingController(
      theme: preferences.activeTheme,
      shortcuts: shortcutStore,
      onFinished: { [weak self] _ in
        guard let self else { return }
        self.onboarding = nil
        self.preferences.showHints = true
        self.spotlight.openHUD()
      }
    )
    onboarding = controller
    // Defer one runloop tick so the spotlight controller and menu bar
    // finish their own first-pass setup before the tutorial steals focus.
    DispatchQueue.main.async { [weak controller] in controller?.show() }
    return true
  }

  private func showSettings() {
    settings.show()
  }

  private func handleLibraryChangedFromSettings() {
    spotlight.reloadLibrary()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  // Re-clicking the app icon (Finder, /Applications, Launchpad, dock) on
  // a running instance routes through here. Treat it like the toggle
  // chord so users without the menubar icon visible can still summon
  // the HUD by opening the app. First-run users see onboarding instead.
  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if OnboardingController.shouldShow() {
      _ = presentOnboardingIfNeeded()
    } else if onboarding?.isActive == true {
      onboarding?.handleGlobalToggleChord()
    } else {
      spotlight.openHUD()
    }
    return true
  }

  private static var wasLaunchedAsBackgroundItem: Bool {
    guard
      let event = NSAppleEventManager.shared().currentAppleEvent,
      event.eventID == kAEOpenApplication,
      let launchKind = event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
    else {
      return false
    }
    return launchKind == keyAELaunchedAsLogInItem || launchKind == keyAELaunchedAsServiceItem
  }

  func applicationWillTerminate(_ notification: Notification) {
    let store = chatStore
    // The last keystrokes may still be queued in an unstructured
    // main-actor save task that can't run while we block below; hand the
    // live editor text to the store directly.
    let unsaved = spotlight.unsavedEditorSnapshot()
    let history = NoteHistoryStore.isEnabled() ? NoteHistoryStore.shared : nil
    let semaphore = DispatchSemaphore(value: 0)
    // Detached: the main thread is blocked on the semaphore below, so a
    // main-actor-inherited Task would never start and the flush would
    // just time out.
    Task.detached {
      if let unsaved { await store.update(id: unsaved.id, text: unsaved.text) }
      await store.flush()
      if let unsaved { await history?.record(unsaved.id, text: unsaved.text, trigger: .checkpoint) }
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + .milliseconds(800))
  }

  /// Opt every new install into background autostart so the global
  /// hotkey works after a reboot without any setup. Subsequent launches
  /// respect whatever the user toggles in Settings.
  private func enableLaunchAtLoginIfFirstRun() {
    let key = "launchAtLogin.didInitialize"
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: key) == nil else { return }
    defaults.set(true, forKey: key)
    if LaunchAtLogin.setEnabled(true) {
      preferences.launchAtLogin = true
    }
  }

  private func applyToggleHotkey(_ shortcut: Shortcut) {
    // Fall back to the default if the user somehow configured a key
    // we can't translate into a Carbon virtual code (the recorder
    // should prevent this, but keep the toggle functional regardless).
    if hotkey?.apply(shortcut) == true { return }
    _ = hotkey?.apply(ShortcutAction.toggleHotkey.defaultShortcut)
  }

  private func applyAppendHotkey(_ shortcut: Shortcut) {
    if appendHotkey?.apply(shortcut) == true { return }
    _ = appendHotkey?.apply(ShortcutAction.appendToLastNote.defaultShortcut)
  }
}
