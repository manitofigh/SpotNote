import AppKit
import Spotlight
import SwiftUI

/// Owns the lazily-constructed Preferences window hosting `SettingsView`.
@MainActor
final class SettingsWindowController {
  private var window: NSWindow?
  private let preferences: ThemePreferences
  private let shortcuts: ShortcutStore

  init(preferences: ThemePreferences, shortcuts: ShortcutStore) {
    self.preferences = preferences
    self.shortcuts = shortcuts
  }

  /// Shows the Preferences window, creating it on first use.
  func show() {
    let window = window ?? makeWindow()
    self.window = window
    if window.isVisible == false {
      window.center()
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 740, height: 560),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "SpotNote Settings"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.isMovableByWindowBackground = true
    window.minSize = NSSize(width: 680, height: 480)
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = NSColor(
      red: 0.055,
      green: 0.055,
      blue: 0.065,
      alpha: 1
    )
    window.contentView = NSHostingView(
      rootView: SettingsView(preferences: preferences, shortcuts: shortcuts)
    )
    return window
  }
}
