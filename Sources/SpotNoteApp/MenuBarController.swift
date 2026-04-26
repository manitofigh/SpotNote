import AppKit
import Combine
import Spotlight

/// Installs an `NSStatusItem` in the macOS menu bar.
///
/// Always uses `SpotNote-Menubar-Dark.svg` -- a single icon that reads
/// well on both light and dark menu bars, so no appearance switching
/// is needed.
///
/// Visibility is bound to `ThemePreferences.showMenuBarIcon`; turning
/// the toggle off hides the status item, turning it on re-shows it.
@MainActor
final class MenuBarController {
  private static let iconSize = NSSize(width: 16.5, height: 16.5)
  private static let iconName = "SpotNote-Menubar-Dark"

  private let statusItem: NSStatusItem
  private let preferences: ThemePreferences
  private let onOpenSettings: () -> Void
  private var visibilityCancellable: AnyCancellable?

  init(preferences: ThemePreferences, onOpenSettings: @escaping () -> Void) {
    self.preferences = preferences
    self.onOpenSettings = onOpenSettings
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    configureButton()
    configureMenu()
    observeVisibility()
  }

  private func configureButton() {
    guard let button = statusItem.button else { return }
    button.image = Self.iconImage()
    button.image?.size = Self.iconSize
    button.imagePosition = .imageOnly
  }

  private func configureMenu() {
    let menu = NSMenu()
    let settingsItem = NSMenuItem(
      title: "Settings…",
      action: #selector(openSettings),
      keyEquivalent: ","
    )
    settingsItem.target = self
    menu.addItem(settingsItem)
    let updateItem = NSMenuItem(
      title: "Check for Updates…",
      action: #selector(UpdateController.checkForUpdates(_:)),
      keyEquivalent: ""
    )
    updateItem.target = UpdateController.shared
    menu.addItem(updateItem)
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit SpotNote",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    statusItem.menu = menu
  }

  @objc private func openSettings() {
    onOpenSettings()
  }

  private func observeVisibility() {
    statusItem.isVisible = preferences.showMenuBarIcon
    visibilityCancellable = preferences.$showMenuBarIcon
      .receive(on: RunLoop.main)
      .sink { [weak self] shouldShow in
        self?.statusItem.isVisible = shouldShow
      }
  }

  private static func iconImage() -> NSImage? {
    let bundle = Bundle.spotlightResources
    guard let url = bundle.url(forResource: iconName, withExtension: "svg") else { return nil }
    let image = NSImage(contentsOf: url)
    image?.isTemplate = false
    return image
  }
}
