import AppKit

/// Installs a minimal `NSApp.mainMenu` carrying the standard Edit items.
///
/// Even for `LSUIElement` accessory apps whose menu bar is never displayed,
/// the menu must exist for standard text-editing key equivalents (⌘A, ⌘C,
/// ⌘V, ⌘X, ⌘Z, ⇧⌘Z) to flow through the responder chain into the focused
/// `NSTextField`. Without a main menu the edit commands are silently
/// dropped.
@MainActor
enum MainMenu {
  static func install(onOpenSettings: @escaping () -> Void) {
    let mainMenu = NSMenu()
    mainMenu.addItem(appMenuItem(onOpenSettings: onOpenSettings))
    mainMenu.addItem(editMenuItem())
    NSApp.mainMenu = mainMenu
  }

  private static func appMenuItem(onOpenSettings: @escaping () -> Void) -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: "SpotNote")

    let settingsItem = NSMenuItem(
      title: "Settings…",
      action: #selector(SettingsAction.open(_:)),
      keyEquivalent: ","
    )
    let target = SettingsAction(handler: onOpenSettings)
    settingsItem.target = target
    settingsItem.representedObject = target  // retain the target
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

    item.submenu = menu
    return item
  }

  private static func editMenuItem() -> NSMenuItem {
    let item = NSMenuItem()
    let menu = NSMenu(title: "Edit")
    menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(.separator())
    menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    // Copy has no key equivalent here on purpose: AppKit dispatches menu
    // equivalents ahead of our HUD key monitor, and `NSText.copy(_:)`
    // with no selection hits its no-op path and plays the error beep
    // before our monitor can translate ⌘C into "copy the whole note".
    // The HUD's `SpotlightWindowController.handleKeyEvent` is the sole
    // ⌘C handler; the menu item stays as a UI affordance only.
    menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Select All",
      action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a"
    )
    item.submenu = menu
    return item
  }
}

/// Small Objective-C-compatible target so the `Settings…` menu item can
/// carry a closure without leaking it to a dangling weak self.
@MainActor
private final class SettingsAction: NSObject {
  let handler: () -> Void
  init(handler: @escaping () -> Void) { self.handler = handler }
  @objc func open(_: Any?) { handler() }
}
