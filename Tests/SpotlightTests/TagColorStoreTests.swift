import AppKit
import Foundation
import Testing

@testable import Spotlight

@Suite("TagColorStore")
@MainActor
struct TagColorStoreTests {
  private func makeDefaults() -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: "spotnote.tests.tags.\(UUID())") else {
      Issue.record("UserDefaults suite creation failed")
      return .standard
    }
    return defaults
  }

  @Test("unassigned tags have no colour")
  func unassignedIsNil() {
    let store = TagColorStore(defaults: makeDefaults())
    #expect(store.color(for: "work") == nil)
  }

  @Test("assignments are case-insensitive")
  func caseInsensitive() {
    let store = TagColorStore(defaults: makeDefaults())
    store.setColor(.teal, for: "Work")
    #expect(store.color(for: "WORK") == .teal)
  }

  @Test("assignments persist across store instances")
  func persists() {
    let defaults = makeDefaults()
    TagColorStore(defaults: defaults).setColor(.purple, for: "proj/alpha")
    #expect(TagColorStore(defaults: defaults).color(for: "proj/alpha") == .purple)
  }

  @Test("assigning nil restores the default")
  func resetToDefault() {
    let defaults = makeDefaults()
    let store = TagColorStore(defaults: defaults)
    store.setColor(.red, for: "work")
    store.setColor(nil, for: "work")
    #expect(store.color(for: "work") == nil)
    #expect(TagColorStore(defaults: defaults).color(for: "work") == nil)
  }

  @Test("unknown persisted colour ids are ignored")
  func ignoresUnknownIDs() {
    let defaults = makeDefaults()
    defaults.set(["work": "chartreuse", "home": "green"], forKey: "tags.colors.v1")
    let store = TagColorStore(defaults: defaults)
    #expect(store.color(for: "work") == nil)
    #expect(store.color(for: "home") == .green)
  }

  @Test("styler paints tag ranges with the assigned colour")
  func stylerUsesAssignedColor() {
    let store = TagColorStore(defaults: makeDefaults())
    store.setColor(.blue, for: "work")
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
    textView.string = "hi #work"
    TagStyler.apply(to: textView, theme: ThemeCatalog.obsidian, store: store)
    let color =
      textView.layoutManager?.temporaryAttribute(
        .foregroundColor,
        atCharacterIndex: 4,
        effectiveRange: nil
      ) as? NSColor
    #expect(color == TagColor.blue.foreground(for: .dark))
    let untouched = textView.layoutManager?.temporaryAttribute(
      .backgroundColor,
      atCharacterIndex: 0,
      effectiveRange: nil
    )
    #expect(untouched == nil)
  }
}
