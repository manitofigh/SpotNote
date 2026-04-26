import AppKit
import SwiftUI

struct ShortcutsPane: View {
  @ObservedObject var shortcuts: ShortcutStore
  @State private var confirmResetAll = false

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Shortcuts")
          .font(.system(.title, design: .default, weight: .bold))
        Text("Click any shortcut to record a new chord. A modifier (⌘ ⇧ ⌃ ⌥) is required.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      ShortcutGroup(title: "Global", actions: [.toggleHotkey, .appendToLastNote], store: shortcuts)
      ShortcutGroup(
        title: "Notes",
        actions: [.newChat, .olderChat, .newerChat, .deleteChat, .undoDelete, .pinNote, .copyContent],
        store: shortcuts
      )
      ShortcutGroup(
        title: "Navigation",
        actions: [.findInNote, .fuzzyFindAll, .commandPalette, .openSettings, .toggleTutorial],
        store: shortcuts
      )

      SettingsPillButton("Reset all to defaults") { confirmResetAll = true }
        .confirmationDialog(
          "Reset all shortcuts to their defaults?",
          isPresented: $confirmResetAll,
          titleVisibility: .visible
        ) {
          Button("Reset All", role: .destructive) { shortcuts.resetAll() }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Every shortcut will revert to its factory binding. This cannot be undone.")
        }
    }
  }
}

private struct ShortcutGroup: View {
  let title: String
  let actions: [ShortcutAction]
  @ObservedObject var store: ShortcutStore

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(.subheadline, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(0.6)

      VStack(spacing: 0) {
        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
          if index > 0 {
            Divider()
              .padding(.leading, 16)
              .opacity(0.5)
          }
          ShortcutRow(action: action, store: store)
        }
      }
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.white.opacity(0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
      )
    }
  }
}

private struct ShortcutRow: View {
  let action: ShortcutAction
  @ObservedObject var store: ShortcutStore

  private var keyCapTheme: Theme {
    NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
      ? ThemeCatalog.theme(withID: ThemeCatalog.defaultID)
      : ThemeCatalog.theme(withID: "porcelain")
  }

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(action.displayName)
          .font(.system(.body, weight: .regular))
        Text(action.subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      ShortcutRecorderField(action: action, store: store, theme: keyCapTheme)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}

private struct ShortcutRecorderField: View {
  let action: ShortcutAction
  @ObservedObject var store: ShortcutStore
  let theme: Theme

  @State private var isRecording = false
  @State private var conflictAction: ShortcutAction?
  @State private var monitor: Any?
  @State private var confirmReset = false

  var body: some View {
    HStack(spacing: 8) {
      if let conflict = conflictAction {
        Text("conflicts with \(conflict.displayName)")
          .font(.caption)
          .foregroundStyle(Color(red: 0.725, green: 0.110, blue: 0.110))
          .padding(.trailing, 4)
      }
      capsContent
      trailingButton
    }
    .confirmationDialog(
      Text("Reset \(action.displayName)?"),
      isPresented: $confirmReset,
      titleVisibility: .visible
    ) {
      Button("Reset to \(action.defaultShortcut.displayString)", role: .destructive) {
        conflictAction = nil
        let result = store.reset(action)
        if case .conflict(let other) = result { conflictAction = other }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will change the binding back to \(action.defaultShortcut.displayString).")
    }
  }

  @ViewBuilder
  private var trailingButton: some View {
    if isRecording {
      SettingsPillButton("Cancel", action: stopRecording)
    } else {
      SettingsPillButton("Reset") { confirmReset = true }
    }
  }

  @ViewBuilder
  private var capsContent: some View {
    if isRecording {
      recordingPlaceholder
    } else {
      idleButton
    }
  }

  private var recordingPlaceholder: some View {
    Text("Press a chord…")
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(
            Color.accentColor.opacity(0.6),
            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
          )
      )
  }

  private var idleButton: some View {
    Button(action: startRecording) {
      KeyCap.row(
        for: store.binding(for: action).displayString,
        theme: theme,
        size: .regular
      )
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .help("Click to record a new chord")
  }

  private func startRecording() {
    conflictAction = nil
    isRecording = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handleRecorded(event)
    }
  }

  private func handleRecorded(_ event: NSEvent) -> NSEvent? {
    let mask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    let mods = ShortcutModifierSet(event.modifierFlags.intersection(mask))
    if mods.isEmpty {
      if event.keyCode == 53 { stopRecording() }
      return nil
    }
    let chars = Shortcut.normalize(event.charactersIgnoringModifiers ?? "")
    guard !chars.isEmpty else { return nil }
    let candidate = Shortcut(key: chars, modifiers: mods)
    switch store.setBinding(candidate, for: action) {
    case .ok:
      conflictAction = nil
      stopRecording()
    case .conflict(let other):
      conflictAction = other
    case .missingModifier:
      break
    }
    return nil
  }

  private func stopRecording() {
    if let monitor = monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    isRecording = false
  }
}
