import Core
import Foundation

/// Version-history hooks. Each is a cheap hop onto `NoteHistoryStore`,
/// which decides whether a snapshot is actually due (see
/// `HistorySnapshotTrigger`). All are no-ops when the session has no
/// history store or the user switched history off in Settings.
extension ChatSession {
  private var enabledHistory: NoteHistoryStore? {
    guard let history, NoteHistoryStore.isEnabled() else { return nil }
    return history
  }

  /// Keystroke hook. The `chats` entry still holds the text from the last
  /// list refresh, i.e. the note *before* this editing burst -- that is
  /// the baseline recorded when the note has no history yet.
  func recordHistoryEdit(id: UUID, text: String) {
    guard let history = enabledHistory else { return }
    let baseline = chats.first { $0.id == id }?.text
    Task { await history.record(id, text: text, trigger: .edit, baseline: baseline) }
  }

  /// Snapshots the open note if it changed since its last version. Called
  /// when the HUD hides, the app resigns active, and before switching
  /// notes.
  func checkpointHistory() {
    guard let history = enabledHistory, let id = currentID else { return }
    let text = currentText
    Task { await history.record(id, text: text, trigger: .checkpoint) }
  }

  /// Unconditional snapshot (unless unchanged), awaited so it lands
  /// before the destructive operation that follows.
  func recordHistoryBeforeDestructiveChange(id: UUID, text: String) async {
    await enabledHistory?.record(id, text: text, trigger: .destructive)
  }

  /// Keeps the deleted note's history for the undo window and beyond
  /// (`HistoryConfiguration.deletedRetention`). The tombstone is written
  /// even with history switched off so old versions still expire.
  func recordHistoryBeforeDelete(_ chat: Chat) async {
    await recordHistoryBeforeDestructiveChange(id: chat.id, text: chat.text)
    await history?.markDeleted(chat.id)
  }

  func recordHistoryUndelete(_ id: UUID) async {
    await history?.markRestored(id)
  }
}
