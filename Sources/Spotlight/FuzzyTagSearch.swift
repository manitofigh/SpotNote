import Core
import Foundation

/// Tag-aware front end for `FuzzyController.rank`. `#tag` tokens in the
/// query filter the corpus (see `TagQuery`); the remaining words are
/// fuzzy-ranked exactly as before over the surviving notes.
enum FuzzyTagSearch {
  /// Async entry used by the palette's background search task. Tag sets
  /// come from the shared `TagIndex` cache, so a keystroke never
  /// re-parses unchanged notes.
  static func rank(query: String, in chats: [Chat], limit: Int) async -> [FuzzyResult] {
    guard TagQuery(query).hasFilter else {
      return FuzzyController.rank(query: query, in: chats, limit: limit)
    }
    let tagSets = await TagIndex.shared.tagSets(for: chats)
    return rank(query: query, in: chats, limit: limit, tagSets: tagSets)
  }

  /// Pure, synchronous variant. Notes missing from `tagSets` are parsed
  /// on the fly. Result `position`s still refer to the full corpus.
  /// - Complexity: O(n) filtering plus `FuzzyController.rank` over the survivors.
  static func rank(
    query: String,
    in chats: [Chat],
    limit: Int,
    tagSets: [UUID: Set<String>]
  ) -> [FuzzyResult] {
    let tagQuery = TagQuery(query)
    guard tagQuery.hasFilter else {
      return FuzzyController.rank(query: query, in: chats, limit: limit)
    }
    var positions: [UUID: Int] = [:]
    var filtered: [Chat] = []
    for (index, chat) in chats.enumerated() {
      let tags = tagSets[chat.id] ?? TagParser.tags(in: chat.text)
      guard tagQuery.matches(tags) else { continue }
      positions[chat.id] = index + 1
      filtered.append(chat)
    }
    return FuzzyController.rank(query: tagQuery.remainder, in: filtered, limit: limit).map { result in
      FuzzyResult(
        chat: result.chat,
        score: result.score,
        snippet: result.snippet,
        matchRanges: result.matchRanges,
        position: positions[result.chat.id] ?? result.position
      )
    }
  }
}
