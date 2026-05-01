import AppKit
import Combine
import SwiftUI

/// User-configurable preferences, persisted to `UserDefaults`.
@MainActor
public final class ThemePreferences: ObservableObject {
  public static let minVisibleLines = 1
  public static let maxVisibleLinesCap = 30
  public static let defaultVisibleLines = 3

  private enum Key {
    static let selectedID = "theme.selected.id"
    static let showLineNumbers = "editor.showLineNumbers"
    static let showMenuBarIcon = "menubar.showIcon"
    static let maxVisibleLines = "editor.maxVisibleLines"
    static let showHints = "hud.showTutorial"
    static let vimMode = "editor.vimMode"
    static let dimOnFocusLoss = "hud.dimOnFocusLoss"
    static let unfocusedOpacity = "hud.unfocusedOpacity"
    static let dockIconStyle = "dock.iconStyle"
    static let showDockIcon = "dock.showIcon"
  }

  @Published public var selectedThemeID: String {
    didSet { defaults.set(selectedThemeID, forKey: Key.selectedID) }
  }

  @Published public var showLineNumbers: Bool {
    didSet { defaults.set(showLineNumbers, forKey: Key.showLineNumbers) }
  }

  @Published public var showMenuBarIcon: Bool {
    didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
  }

  @Published public var showHints: Bool {
    didSet { defaults.set(showHints, forKey: Key.showHints) }
  }

  @Published public var vimMode: Bool {
    didSet { defaults.set(vimMode, forKey: Key.vimMode) }
  }

  @Published public var showDockIcon: Bool {
    didSet { defaults.set(showDockIcon, forKey: Key.showDockIcon) }
  }

  /// Backed by `SMAppService.mainApp`, not `UserDefaults`: the system
  /// owns the source of truth and may revoke the registration if the
  /// user disables it from System Settings.
  @Published public var launchAtLogin: Bool {
    didSet {
      guard launchAtLogin != oldValue else { return }
      let applied = LaunchAtLogin.setEnabled(launchAtLogin)
      if !applied {
        let actual = LaunchAtLogin.isEnabled
        if actual != launchAtLogin {
          launchAtLogin = actual
        }
      }
    }
  }

  @Published public var dockIconStyle: DockIconStyle {
    didSet { defaults.set(dockIconStyle.rawValue, forKey: Key.dockIconStyle) }
  }

  @Published public var dimOnFocusLoss: Bool {
    didSet { defaults.set(dimOnFocusLoss, forKey: Key.dimOnFocusLoss) }
  }

  @Published public var unfocusedOpacity: Double {
    didSet {
      let clamped = min(max(0.1, unfocusedOpacity), 1.0)
      if clamped != unfocusedOpacity {
        unfocusedOpacity = clamped
        return
      }
      defaults.set(unfocusedOpacity, forKey: Key.unfocusedOpacity)
    }
  }

  /// Maximum layout rows the Spotlight panel grows to before scrolling.
  /// Clamped to `[minVisibleLines, maxVisibleLinesCap]` in the setter so
  /// a corrupt defaults entry can't blow out the HUD.
  @Published public var maxVisibleLines: Int {
    didSet {
      let clamped = Self.clampVisibleLines(maxVisibleLines)
      if clamped != maxVisibleLines {
        maxVisibleLines = clamped
        return  // the recursive set persists
      }
      defaults.set(maxVisibleLines, forKey: Key.maxVisibleLines)
    }
  }

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.selectedThemeID = defaults.string(forKey: Key.selectedID) ?? ThemeCatalog.defaultID
    self.showLineNumbers = Self.boolOrDefault(defaults, Key.showLineNumbers, default: true)
    self.showMenuBarIcon = Self.boolOrDefault(defaults, Key.showMenuBarIcon, default: true)
    self.showHints = Self.boolOrDefault(defaults, Key.showHints, default: true)
    self.vimMode = Self.boolOrDefault(defaults, Key.vimMode, default: false)
    self.showDockIcon = Self.boolOrDefault(defaults, Key.showDockIcon, default: false)
    self.launchAtLogin = LaunchAtLogin.isEnabled
    let storedStyle = defaults.string(forKey: Key.dockIconStyle) ?? DockIconStyle.dark.rawValue
    self.dockIconStyle = DockIconStyle(rawValue: storedStyle) ?? .dark
    self.dimOnFocusLoss = Self.boolOrDefault(defaults, Key.dimOnFocusLoss, default: false)
    let storedOpacity = defaults.object(forKey: Key.unfocusedOpacity) as? Double
    self.unfocusedOpacity = min(max(0.1, storedOpacity ?? 0.55), 1.0)
    let stored = defaults.object(forKey: Key.maxVisibleLines) as? Int
    self.maxVisibleLines = Self.clampVisibleLines(stored ?? Self.defaultVisibleLines)
  }

  public static func clampVisibleLines(_ value: Int) -> Int {
    min(max(minVisibleLines, value), maxVisibleLinesCap)
  }

  public var activeTheme: Theme {
    ThemeCatalog.theme(withID: selectedThemeID)
  }

  private static func boolOrDefault(
    _ defaults: UserDefaults,
    _ key: String,
    default value: Bool
  ) -> Bool {
    defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
  }
}
