// swiftlint:disable function_body_length
import AppKit
import Carbon.HIToolbox
import Combine
import Core
import Spotlight

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private lazy var preferences = ThemePreferences()
  private lazy var shortcutStore = ShortcutStore()
  private lazy var settings = SettingsWindowController(
    preferences: preferences,
    shortcuts: shortcutStore
  )
  private lazy var chatStore: ChatStore = {
    if let store = try? ChatStore(directory: ChatStore.defaultDirectory()) {
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
    onOpenSettings: { [weak self] in self?.settings.show() }
  )
  private var menuBar: MenuBarController?
  private var hotkey: GlobalHotkey?
  private var appendHotkey: GlobalHotkey?
  private var onboarding: OnboardingController?
  private var cancellables: Set<AnyCancellable> = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    DockIconSwitcher.applyVisibility(preferences.showDockIcon)
    MainMenu.install(onOpenSettings: { [weak self] in self?.settings.show() })

    enableLaunchAtLoginIfFirstRun()

    menuBar = MenuBarController(
      preferences: preferences,
      onOpenSettings: { [weak self] in self?.settings.show() }
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

    presentOnboardingIfNeeded()
  }

  private func presentOnboardingIfNeeded() {
    guard OnboardingController.shouldShow() else { return }
    let controller = OnboardingController(
      theme: preferences.activeTheme,
      shortcuts: shortcutStore,
      onFinished: { [weak self] _ in
        guard let self else { return }
        self.onboarding = nil
        self.preferences.showHints = true
        self.spotlight.handleHotkey()
      }
    )
    onboarding = controller
    // Defer one runloop tick so the spotlight controller and menu bar
    // finish their own first-pass setup before the tutorial steals focus.
    DispatchQueue.main.async { [weak controller] in controller?.show() }
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
      presentOnboardingIfNeeded()
    } else if onboarding?.isActive == true {
      onboarding?.handleGlobalToggleChord()
    } else {
      spotlight.handleHotkey()
    }
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    let store = chatStore
    let semaphore = DispatchSemaphore(value: 0)
    Task {
      await store.flush()
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
