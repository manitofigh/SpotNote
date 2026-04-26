import AppKit
import Combine
import Foundation

/// User-customizable keyboard chord. The `key` is stored as a normalized
/// lowercase string ("n", "z", ",", "/", "space") so equality across
/// recordings and lookups is deterministic regardless of how AppKit
/// reports the character.
public struct Shortcut: Codable, Hashable, Sendable {
  public let key: String
  public let modifiers: ShortcutModifierSet

  public init(key: String, modifiers: ShortcutModifierSet) {
    self.key = Self.normalize(key)
    self.modifiers = modifiers
  }

  public var displayString: String {
    modifiers.displayString + Self.displayKey(key)
  }

  /// Normalizes characters reported by
  /// `NSEvent.charactersIgnoringModifiers` into the canonical form used
  /// as map keys.
  public static func normalize(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower == " " { return "space" }
    return lower
  }

  static func displayKey(_ key: String) -> String {
    switch key {
    case "space": return "Space"
    case "tab": return "Tab"
    case "return": return "Return"
    case "escape": return "Esc"
    default: return key.uppercased()
    }
  }
}

public struct ShortcutModifierSet: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let command = ShortcutModifierSet(rawValue: 1 << 0)
  public static let shift = ShortcutModifierSet(rawValue: 1 << 1)
  public static let option = ShortcutModifierSet(rawValue: 1 << 2)
  public static let control = ShortcutModifierSet(rawValue: 1 << 3)

  public init(_ flags: NSEvent.ModifierFlags) {
    var set: ShortcutModifierSet = []
    if flags.contains(.command) { set.insert(.command) }
    if flags.contains(.shift) { set.insert(.shift) }
    if flags.contains(.option) { set.insert(.option) }
    if flags.contains(.control) { set.insert(.control) }
    self = set
  }

  /// Canonical macOS modifier glyph order: ⌃⌥⇧⌘.
  public var displayString: String {
    var output = ""
    if contains(.control) { output += "⌃" }
    if contains(.option) { output += "⌥" }
    if contains(.shift) { output += "⇧" }
    if contains(.command) { output += "⌘" }
    return output
  }
}

public enum ShortcutAction: String, CaseIterable, Codable, Sendable, Identifiable {
  case toggleHotkey
  case appendToLastNote
  case newChat
  case olderChat
  case newerChat
  case deleteChat
  case undoDelete
  case findInNote
  case fuzzyFindAll
  case copyContent
  case openSettings
  case pinNote
  case commandPalette
  case toggleTutorial

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .toggleHotkey: return "Show / hide HUD"
    case .appendToLastNote: return "Append to most recent"
    case .newChat: return "New note"
    case .olderChat: return "Older note"
    case .newerChat: return "Newer note"
    case .deleteChat: return "Delete current note"
    case .undoDelete: return "Undo delete"
    case .findInNote: return "Find in note"
    case .fuzzyFindAll: return "Fuzzy find any note"
    case .copyContent: return "Copy note"
    case .openSettings: return "Open settings"
    case .pinNote: return "Pin / unpin note"
    case .commandPalette: return "Command palette"
    case .toggleTutorial: return "Toggle hints bar"
    }
  }

  public var subtitle: String {
    switch self {
    case .toggleHotkey: return "Global hotkey to summon SpotNote from any app."
    case .appendToLastNote:
      return "Summon the HUD on the most recently edited note with the caret already at the end."
    case .newChat: return "Start a fresh blank note."
    case .olderChat: return "Step back through your saved notes (hold to repeat)."
    case .newerChat: return "Step forward through your saved notes (hold to repeat)."
    case .deleteChat: return "Delete the note currently in the editor."
    case .undoDelete: return "Restore the most recently deleted note."
    case .findInNote: return "Search for text inside the current note."
    case .fuzzyFindAll: return "Open the fuzzy palette to jump to any saved note."
    case .copyContent: return "Copy the whole note. With a selection, copies just the selection."
    case .openSettings: return "Open this settings window."
    case .pinNote: return "Pin the current note so it stays at the top of the list."
    case .commandPalette: return "Search settings and keyboard shortcuts."
    case .toggleTutorial: return "Show or hide the hint strip above the editor."
    }
  }

  public var defaultShortcut: Shortcut {
    switch self {
    case .toggleHotkey: return Shortcut(key: "space", modifiers: [.command, .shift])
    case .appendToLastNote: return Shortcut(key: ".", modifiers: [.command, .shift])
    case .newChat: return Shortcut(key: "n", modifiers: [.command])
    case .olderChat: return Shortcut(key: "n", modifiers: [.control])
    case .newerChat: return Shortcut(key: "p", modifiers: [.control])
    case .deleteChat: return Shortcut(key: "d", modifiers: [.command])
    case .undoDelete: return Shortcut(key: "z", modifiers: [.command])
    case .findInNote: return Shortcut(key: "f", modifiers: [.command])
    case .fuzzyFindAll: return Shortcut(key: "p", modifiers: [.command])
    case .copyContent: return Shortcut(key: "c", modifiers: [.command])
    case .openSettings: return Shortcut(key: ",", modifiers: [.command])
    case .pinNote: return Shortcut(key: "s", modifiers: [.command])
    case .commandPalette: return Shortcut(key: "k", modifiers: [.command])
    case .toggleTutorial: return Shortcut(key: "/", modifiers: [.command])
    }
  }
}

/// Persistent, observable map of `ShortcutAction -> Shortcut`. Refuses
/// rebinds that collide with another action (so the user can't double-
/// book a chord) or that drop the modifier (which would shadow plain
/// typing). Persists to `UserDefaults` on every successful change.
@MainActor
public final class ShortcutStore: ObservableObject {
  public enum SetResult: Equatable {
    case ok
    case conflict(ShortcutAction)
    case missingModifier
  }

  @Published public private(set) var bindings: [ShortcutAction: Shortcut] = [:]

  private let defaults: UserDefaults
  private let storageKey: String

  public init(defaults: UserDefaults = .standard, storageKey: String = "shortcuts.bindings.v5") {
    self.defaults = defaults
    self.storageKey = storageKey
    self.bindings = Self.load(defaults: defaults, key: storageKey)
  }

  public func binding(for action: ShortcutAction) -> Shortcut {
    bindings[action] ?? action.defaultShortcut
  }

  @discardableResult
  public func setBinding(_ shortcut: Shortcut, for action: ShortcutAction) -> SetResult {
    guard !shortcut.modifiers.isEmpty else { return .missingModifier }
    if let other = bindings.first(where: { $0.key != action && $0.value == shortcut })?.key {
      return .conflict(other)
    }
    bindings[action] = shortcut
    persist()
    return .ok
  }

  @discardableResult
  public func reset(_ action: ShortcutAction) -> SetResult {
    setBinding(action.defaultShortcut, for: action)
  }

  public func resetAll() {
    var rebuilt: [ShortcutAction: Shortcut] = [:]
    for action in ShortcutAction.allCases {
      rebuilt[action] = action.defaultShortcut
    }
    bindings = rebuilt
    persist()
  }

  public func match(key: String, modifiers: ShortcutModifierSet) -> ShortcutAction? {
    let lookup = Shortcut(key: key, modifiers: modifiers)
    return bindings.first(where: { $0.value == lookup })?.key
  }

  private static func load(defaults: UserDefaults, key: String) -> [ShortcutAction: Shortcut] {
    var loaded: [ShortcutAction: Shortcut] = [:]
    let data = defaults.data(forKey: key)
    let decoded = data.flatMap { try? JSONDecoder().decode([String: Shortcut].self, from: $0) }
    if let decoded {
      for (raw, shortcut) in decoded {
        if let action = ShortcutAction(rawValue: raw) {
          loaded[action] = shortcut
        }
      }
    }
    var result: [ShortcutAction: Shortcut] = [:]
    for action in ShortcutAction.allCases {
      result[action] = loaded[action] ?? action.defaultShortcut
    }
    return result
  }

  private func persist() {
    var raw: [String: Shortcut] = [:]
    for (action, shortcut) in bindings {
      raw[action.rawValue] = shortcut
    }
    if let data = try? JSONEncoder().encode(raw) {
      defaults.set(data, forKey: storageKey)
    }
  }
}
