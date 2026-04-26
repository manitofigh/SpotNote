import Foundation
import Testing

@testable import Spotlight

@MainActor
@Suite("ShortcutStore")
struct ShortcutStoreTests {
  private func makeDefaults(_ tag: String = #function) -> UserDefaults {
    let suite = "spotnote.test.\(tag).\(UUID().uuidString)"
    return UserDefaults(suiteName: suite) ?? .standard
  }

  @Test("every action has a non-empty default chord")
  func defaultsCoverAllActions() {
    for action in ShortcutAction.allCases {
      let shortcut = action.defaultShortcut
      #expect(!shortcut.key.isEmpty)
      #expect(!shortcut.modifiers.isEmpty, "global plain-key chords would shadow typing")
    }
  }

  @Test("rebind succeeds when no other action owns the chord")
  func rebindSucceeds() {
    let store = ShortcutStore(defaults: makeDefaults())
    let result = store.setBinding(
      Shortcut(key: "j", modifiers: [.command, .shift]),
      for: .newChat
    )
    #expect(result == .ok)
    #expect(store.binding(for: .newChat).key == "j")
  }

  @Test("rebind to a chord owned by another action returns conflict")
  func rebindConflict() {
    let store = ShortcutStore(defaults: makeDefaults())
    // Default `.newChat` is ⌘N. Try to assign that to `.openSettings`.
    let result = store.setBinding(
      Shortcut(key: "n", modifiers: [.command]),
      for: .openSettings
    )
    #expect(result == .conflict(.newChat))
    #expect(store.binding(for: .openSettings).key == ",", "binding stays at default on conflict")
  }

  @Test("modifier-less chords are rejected")
  func rejectsBareKey() {
    let store = ShortcutStore(defaults: makeDefaults())
    let result = store.setBinding(Shortcut(key: "n", modifiers: []), for: .newChat)
    #expect(result == .missingModifier)
  }

  @Test("bindings persist across store instances")
  func persistsAcrossInstances() {
    let defaults = makeDefaults()
    let first = ShortcutStore(defaults: defaults)
    _ = first.setBinding(
      Shortcut(key: "k", modifiers: [.command, .option]),
      for: .deleteChat
    )
    let second = ShortcutStore(defaults: defaults)
    #expect(second.binding(for: .deleteChat).key == "k")
    #expect(second.binding(for: .deleteChat).modifiers == [.command, .option])
  }

  @Test("match resolves the action that owns a chord, ignoring others")
  func matchResolvesOwner() {
    let store = ShortcutStore(defaults: makeDefaults())
    let action = store.match(key: "n", modifiers: [.command])
    #expect(action == .newChat)
    let none = store.match(key: "j", modifiers: [.command])
    #expect(none == nil)
  }

  @Test("resetAll restores every action to its default")
  func resetAllRestoresDefaults() {
    let store = ShortcutStore(defaults: makeDefaults())
    _ = store.setBinding(
      Shortcut(key: "k", modifiers: [.command, .option]),
      for: .newChat
    )
    store.resetAll()
    #expect(store.binding(for: .newChat) == ShortcutAction.newChat.defaultShortcut)
  }

  @Test("normalize folds case and maps the bare space character to 'space'")
  func normalizes() {
    #expect(Shortcut.normalize("N") == "n")
    #expect(Shortcut.normalize(" ") == "space")
    #expect(Shortcut.normalize(",") == ",")
  }

  @Test("displayString renders modifiers in canonical macOS order")
  func displayStringOrder() {
    let chord = Shortcut(
      key: "space",
      modifiers: [.command, .control, .option, .shift]
    )
    #expect(chord.displayString == "⌃⌥⇧⌘Space")
  }
}
