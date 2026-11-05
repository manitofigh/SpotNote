import AppKit
import Core

/// Version-history wiring for the HUD: checkpoints on deactivation, the
/// ⌘Y browser's keyboard handling, and undoable restore.
extension SpotlightWindowController {
  /// Returns the notification tokens so the caller can own them.
  func installHistoryHooks() -> [NSObjectProtocol] {
    if let history = session.history {
      // One-shot, fire-and-forget: only reads the small tombstone index.
      Task { await history.purgeExpiredDeletions() }
    }
    historyController.onRestore = { [weak self] text in self?.restoreHistoryVersion(text) }
    let token = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.session.checkpointHistory() }
    }
    return [token]
  }

  func toggleHistoryPalette() {
    historyController.toggle(
      noteID: session.currentID,
      currentText: session.currentText,
      history: session.history
    )
  }

  /// Keys consumed while the browser is open; `false` lets normal
  /// shortcut handling continue.
  func handleHistoryPaletteKey(_ event: NSEvent, action: ShortcutAction?) -> Bool {
    guard historyController.isVisible else { return false }
    let hasModifiers = !event.modifierFlags.isDisjoint(with: [.command, .control, .option])
    switch event.keyCode {
    case 53:
      historyController.close()
      return true
    case 36, 76:
      historyController.restoreSelected()
      return true
    case 125 where !hasModifiers:
      historyController.moveSelection(by: +1)
      return true
    case 126 where !hasModifiers:
      historyController.moveSelection(by: -1)
      return true
    default:
      break
    }
    guard action == .olderChat || action == .newerChat else { return false }
    historyController.moveSelection(by: action == .olderChat ? 1 : -1)
    return true
  }

  /// Replaces the note with `text` through the editor so ⌘Z undoes the
  /// restore. The text before and after is snapshotted first, so the
  /// restore itself is also reversible from the version list.
  private func restoreHistoryVersion(_ text: String) {
    guard let id = session.currentID, session.currentText != text else { return }
    let previous = session.currentText
    let session = self.session
    Task { [weak self] in
      await session.recordHistoryBeforeDestructiveChange(id: id, text: previous)
      guard let self, session.currentID == id else { return }
      self.replaceEditorText(with: text)
      await session.recordHistoryBeforeDestructiveChange(id: id, text: text)
    }
  }

  private func replaceEditorText(with text: String) {
    if let textView = editorTextView() {
      textView.window?.makeFirstResponder(textView)
      let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
      textView.insertDiscreteEdit(text, replacing: fullRange, actionName: "Restore Version")
    }
    // Fallback when the editor isn't mounted (or its delegate didn't push
    // the change synchronously): update the session directly.
    if session.currentText != text {
      session.currentText = text
      session.persistIfNeeded()
    }
  }
}
