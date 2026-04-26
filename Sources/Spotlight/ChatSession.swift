import Combine
import Core
import Foundation

/// Transient state pushed by `ChatSession` whenever a navigation action
/// happens. The UI renders a small overlay from it and auto-clears after
/// a short delay.
struct NavigationPreview: Equatable, Sendable {
  /// Short human-readable label shown at the top of the overlay
  /// ("new note", "note 2 of 5", "only one note", "already on a blank note").
  let actionLabel: String
  /// Chats to list in the overlay. For single-message indicators this
  /// may be empty.
  let chats: [Chat]
  let currentID: UUID?
  /// Optional chat to flash with a transient accent so the user can
  /// see exactly which row a non-cycling action affected. Currently set
  /// when ⌘Z restores a previously deleted chat.
  let highlightedID: UUID?
}

/// UI-facing, main-actor-isolated view model over a `ChatStore`. Owns
/// the currently-edited chat's `id` and `text`, forwards user edits to
/// the store (which debounces disk writes internally), and publishes
/// transient `NavigationPreview` snapshots driving the HUD's feedback
/// overlay.
///
/// All chat-switching happens by assigning to `currentID` + `currentText`
/// directly -- `persistIfNeeded()` is only invoked from the SwiftUI
/// binding setter, so programmatic switches never overwrite the old
/// chat with the new chat's text.
@MainActor
final class ChatSession: ObservableObject {
  @Published var currentText: String = ""
  @Published private(set) var currentID: UUID?
  @Published private(set) var chats: [Chat] = []
  @Published private(set) var navigationPreview: NavigationPreview?
  /// Stack of deleted-chat snapshots pushed by `deleteCurrent` and
  /// popped by `undoDelete` (⌘Z). Supports multi-level undo -- pressing
  /// ⌘Z repeatedly restores successive deletions in reverse order.
  /// Cleared whole on the next user-driven edit or new-chat action so
  /// undo doesn't span unrelated work.
  @Published private(set) var deletedStack: [Chat] = []

  /// Convenience: the most recently deleted chat, nil when nothing is
  /// pending restore. Views (`NavigationOverlay.canUndo`) and the
  /// window controller's key monitor read this.
  var lastDeleted: Chat? { deletedStack.last }

  private let store: ChatStore
  private var previewDismissTask: Task<Void, Never>?
  /// While true, `announce` skips scheduling auto-dismiss so the
  /// navigation overlay stays put. Driven by the window controller's
  /// modifier-key monitor (typically the ⌃ key for ⌃N/⌃P cycling).
  private var keepNavigationOpen = false
  private static let previewDismissDelay: Duration = .milliseconds(1400)
  private static let deletePreviewDelay: Duration = .milliseconds(4000)

  init(store: ChatStore) {
    self.store = store
  }

  /// Loads the chat list and restores the most-recently-edited chat. If
  /// the store is empty, creates a fresh chat so the user can start
  /// typing immediately.
  func bootstrap() async {
    chats = await store.list()
    if let mostRecent = chats.first {
      currentID = mostRecent.id
      currentText = mostRecent.text
    } else {
      _ = await createBlankChat()
    }
  }

  /// Binds to ⌘N -- creates a fresh blank chat unconditionally (even
  /// when already on an empty one; a user may deliberately want a
  /// second blank slate).
  func newChat() async {
    deletedStack = []
    guard await createBlankChat() else { return }
    announce("new note")
  }

  /// Binds to ⌃N -- step to the next older chat, wrapping to the
  /// newest after the oldest. Never creates a chat.
  func cycleOlder() async { await cycle(by: +1) }

  /// Binds to ⌃P -- step to the next newer chat, wrapping to the
  /// oldest after the newest. Never creates a chat.
  func cycleNewer() async { await cycle(by: -1) }

  private func cycle(by delta: Int) async {
    chats = await store.list()
    guard !chats.isEmpty else { return }
    guard chats.count > 1 else {
      announce("only one note")
      return
    }
    let index = chats.firstIndex(where: { $0.id == currentID }) ?? 0
    let count = chats.count
    let next = ((index + delta) % count + count) % count
    let chat = chats[next]
    currentID = chat.id
    currentText = chat.text
    announce("note \(next + 1) of \(count)")
  }

  /// Switches the editor to `chat` immediately. Used by the fuzzy
  /// palette (⌘P) to jump to any saved note. Bypasses the cycle preview
  /// since the user just made an explicit choice.
  func jump(to chat: Chat) {
    deletedStack = []
    if navigationPreview != nil {
      navigationPreview = nil
      previewDismissTask?.cancel()
      previewDismissTask = nil
    }
    currentID = chat.id
    currentText = chat.text
  }

  /// Binds to ⌘D -- removes the current chat and lands on the next
  /// most-recently-edited one. When the store becomes empty a fresh
  /// blank chat is created so the user can keep typing immediately.
  /// The deleted chat (with the in-memory text, in case of unsaved
  /// edits) is captured into `lastDeleted` so ⌘Z can restore it.
  func deleteCurrent() async {
    guard let id = currentID else { return }
    var snapshot =
      chats.first(where: { $0.id == id })
      ?? Chat(id: id, createdAt: Date(), updatedAt: Date(), text: currentText)
    snapshot.text = currentText
    try? await store.delete(id: id)
    deletedStack.append(snapshot)
    chats = await store.list()
    if let replacement = chats.first {
      currentID = replacement.id
      currentText = replacement.text
      announce("deleted", sticky: true)
    } else {
      _ = await createBlankChat()
      announce("deleted", includingList: false, sticky: true)
    }
  }

  /// Binds to ⌘Z when `lastDeleted != nil`. Re-inserts the captured
  /// chat (preserving its original id/timestamps) and switches to it.
  /// No-op when there is nothing to restore -- the window controller's
  /// key monitor checks this and lets the editor handle text undo
  /// instead.
  func undoDelete() async {
    guard let chat = deletedStack.popLast() else { return }
    try? await store.restore(chat)
    chats = await store.list()
    currentID = chat.id
    currentText = chat.text
    announce("restored", sticky: true, highlightedID: chat.id)
  }

  func togglePin() async {
    guard let id = currentID else { return }
    try? await store.togglePin(id: id)
    chats = await store.list()
    let wasPinned = chats.first(where: { $0.id == id })?.isPinned ?? false
    announce(wasPinned ? "pinned ★" : "unpinned", sticky: false)
  }

  /// Called from the SwiftUI binding setter after a user-driven edit so
  /// the store can schedule its debounced write. Also clears
  /// `lastDeleted` (so ⌘Z stops undoing a delete once the user starts
  /// editing again) and dismisses the navigation overlay immediately
  /// (the user has committed to the chat they landed on, so the
  /// browse-list shouldn't linger past the first keystroke).
  func persistIfNeeded() {
    deletedStack = []
    if navigationPreview != nil {
      navigationPreview = nil
      previewDismissTask?.cancel()
      previewDismissTask = nil
    }
    guard let id = currentID else { return }
    let snapshot = currentText
    let store = store
    Task { await store.update(id: id, text: snapshot) }
  }

  // MARK: - Private

  private func createBlankChat() async -> Bool {
    guard let chat = try? await store.create() else { return false }
    currentID = chat.id
    currentText = ""
    chats = await store.list()
    return true
  }

  private func announce(
    _ label: String,
    includingList: Bool = true,
    sticky: Bool = false,
    highlightedID: UUID? = nil
  ) {
    navigationPreview = NavigationPreview(
      actionLabel: label,
      chats: includingList ? chats : [],
      currentID: currentID,
      highlightedID: highlightedID
    )
    previewDismissTask?.cancel()
    previewDismissTask = nil
    if keepNavigationOpen { return }
    let delay = sticky ? Self.deletePreviewDelay : Self.previewDismissDelay
    scheduleDismiss(after: delay)
  }

  /// Pauses or resumes the auto-dismiss timer for the navigation
  /// overlay. Called by the window controller's `flagsChanged` monitor
  /// so that as long as the cycle modifier (e.g. ⌃) is held down, the
  /// list of files stays visible regardless of the timer.
  func setNavigationHeldOpen(_ held: Bool) {
    keepNavigationOpen = held
    if held {
      previewDismissTask?.cancel()
      previewDismissTask = nil
    } else if navigationPreview != nil {
      scheduleDismiss(after: Self.previewDismissDelay)
    }
  }

  private func scheduleDismiss(after delay: Duration) {
    previewDismissTask?.cancel()
    previewDismissTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      self?.navigationPreview = nil
    }
  }
}
