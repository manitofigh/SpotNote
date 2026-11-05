import Core
import Foundation

/// Off-main cache of each note's tag set, keyed by note id and
/// invalidated by `updatedAt`. The fuzzy palette asks for the whole
/// corpus on every tag-filtered keystroke; only notes edited since the
/// previous call are re-parsed, the rest is dictionary lookups.
actor TagIndex {
  static let shared = TagIndex()

  private struct Entry {
    let updatedAt: Date
    let tags: Set<String>
  }

  private var entries: [UUID: Entry] = [:]

  /// Tag sets for `chats`. Entries for notes no longer in `chats` are
  /// dropped so the cache never outgrows the corpus.
  /// - Complexity: O(n) lookups plus O(length) parsing per changed note.
  func tagSets(for chats: [Chat]) -> [UUID: Set<String>] {
    var next: [UUID: Entry] = [:]
    next.reserveCapacity(chats.count)
    var result: [UUID: Set<String>] = [:]
    result.reserveCapacity(chats.count)
    for chat in chats {
      let entry: Entry
      if let cached = entries[chat.id], cached.updatedAt == chat.updatedAt {
        entry = cached
      } else {
        entry = Entry(updatedAt: chat.updatedAt, tags: TagParser.tags(in: chat.text))
      }
      next[chat.id] = entry
      result[chat.id] = entry.tags
    }
    entries = next
    return result
  }
}
