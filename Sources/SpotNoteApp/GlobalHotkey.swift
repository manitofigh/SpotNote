import AppKit
import Carbon.HIToolbox
import Spotlight

/// Registers a process-global hotkey via the Carbon Event Manager.
///
/// Unlike `NSEvent.addGlobalMonitorForEvents`, this does not require
/// Accessibility permission and consumes the event so it does not leak
/// to the focused application. Multiple instances coexist via a static
/// id-keyed handler dictionary so the app can register the HUD's
/// summon chord and the append-to-last-note chord side-by-side.
@MainActor
final class GlobalHotkey {
  private var hotKeyRef: EventHotKeyRef?
  private let handler: @MainActor () -> Void
  private let hotkeyID: UInt32

  private static var handlersByID: [UInt32: @MainActor () -> Void] = [:]
  private static var nextID: UInt32 = 1
  private static var carbonHandler: EventHandlerRef?

  init(handler: @escaping @MainActor () -> Void) {
    self.handler = handler
    let id = Self.nextID
    Self.nextID += 1
    self.hotkeyID = id
  }

  /// Replaces any previously registered chord with `shortcut`. Silently
  /// no-ops when the shortcut's key cannot be mapped to a Carbon virtual
  /// keycode -- the caller keeps the last-successful binding active.
  @discardableResult
  func apply(_ shortcut: Shortcut) -> Bool {
    guard let keyCode = Self.keyCode(for: shortcut.key) else { return false }
    Self.installHandlerIfNeeded()
    unregister()
    let hkID = EventHotKeyID(signature: OSType(0x534E_5448), id: hotkeyID)  // 'SNTH'
    Self.handlersByID[hotkeyID] = handler
    RegisterEventHotKey(
      keyCode,
      Self.carbonModifiers(shortcut.modifiers),
      hkID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
    return true
  }

  private func unregister() {
    if let ref = hotKeyRef {
      UnregisterEventHotKey(ref)
      hotKeyRef = nil
    }
    Self.handlersByID[hotkeyID] = nil
  }

  private static func installHandlerIfNeeded() {
    guard carbonHandler == nil else { return }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ -> OSStatus in
        guard let event else { return noErr }
        var hkID = EventHotKeyID()
        GetEventParameter(
          event,
          UInt32(kEventParamDirectObject),
          UInt32(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hkID
        )
        let id = hkID.id
        DispatchQueue.main.async {
          GlobalHotkey.handlersByID[id]?()
        }
        return noErr
      },
      1,
      &eventType,
      nil,
      &carbonHandler
    )
  }

  private static func carbonModifiers(_ set: ShortcutModifierSet) -> UInt32 {
    var flags: UInt32 = 0
    if set.contains(.command) { flags |= UInt32(cmdKey) }
    if set.contains(.shift) { flags |= UInt32(shiftKey) }
    if set.contains(.option) { flags |= UInt32(optionKey) }
    if set.contains(.control) { flags |= UInt32(controlKey) }
    return flags
  }

  /// Covers the keys that the shortcut recorder currently accepts:
  /// letters, digits, space, and the punctuation used by the default
  /// bindings. Non-mapped keys can still be bound as in-app shortcuts
  /// (handled by the NSEvent monitor) -- only the global chord requires
  /// a Carbon virtual keycode.
  private static func keyCode(for key: String) -> UInt32? {
    let table: [String: Int] = [
      "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
      "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
      "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
      "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
      "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
      "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
      "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
      "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
      "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
      "8": kVK_ANSI_8, "9": kVK_ANSI_9,
      "space": kVK_Space, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
      "/": kVK_ANSI_Slash, "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal,
      "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
      ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "\\": kVK_ANSI_Backslash,
      "`": kVK_ANSI_Grave
    ]
    return table[key].map { UInt32($0) }
  }

  // Intentionally no deinit: this object is a process-lifetime singleton held
  // by the app delegate. Carbon resources are released on process exit, and a
  // `@MainActor` property cannot be safely read from a nonisolated deinit
  // under Swift 6 strict concurrency.
}
