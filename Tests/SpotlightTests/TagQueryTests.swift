import Core
import Foundation
import Testing

@testable import Spotlight

@Suite("TagQuery")
struct TagQueryTests {
  @Test("splits completed tags, the tag being typed, and free text")
  func splitsTokens() {
    let query = TagQuery("#Work meeting #proj notes #al")
    #expect(query.tags == ["work", "proj"])
    #expect(query.typingPrefix == "al")
    #expect(query.remainder == "meeting notes")
  }

  @Test("a trailing space completes the final tag token")
  func trailingSpaceCompletes() {
    let query = TagQuery("#work ")
    #expect(query.tags == ["work"])
    #expect(query.typingPrefix == nil)
  }

  @Test("lone hash and non-tag tokens stay in the free-text remainder")
  func nonTagsStayText() {
    let query = TagQuery("# #123 #a.b word")
    #expect(!query.hasFilter)
    #expect(query.remainder == "# #123 #a.b word")
  }

  @Test("completed tags match exactly or as a parent of a nested tag")
  func completedMatching() {
    let query = TagQuery("#proj ")
    #expect(query.matches(["proj"]))
    #expect(query.matches(["proj/alpha"]))
    #expect(!query.matches(["project"]))
  }

  @Test("the tag being typed matches by prefix")
  func prefixMatching() {
    let query = TagQuery("#wo")
    #expect(query.matches(["work"]))
    #expect(!query.matches(["home"]))
  }

  @Test("every tag filter must match")
  func allFiltersRequired() {
    let query = TagQuery("#a #b ")
    #expect(query.matches(["a", "b", "c"]))
    #expect(!query.matches(["a"]))
  }
}

@Suite("FuzzyTagSearch")
struct FuzzyTagSearchTests {
  private static let base = Date(timeIntervalSince1970: 1_700_000_000)

  private static func chat(_ text: String) -> Chat {
    Chat(createdAt: base, updatedAt: base, text: text)
  }

  private static let corpus = [
    chat("groceries #home milk"),
    chat("standup notes #work #meeting"),
    chat("roadmap #work/q3 planning"),
    chat("plain note without tags")
  ]

  @Test("tag-only query keeps tagged notes in corpus order with corpus positions")
  func tagOnlyFilter() {
    let results = FuzzyTagSearch.rank(query: "#work ", in: Self.corpus, limit: 50, tagSets: [:])
    #expect(results.map(\.chat.id) == [Self.corpus[1].id, Self.corpus[2].id])
    #expect(results.map(\.position) == [2, 3])
  }

  @Test("remaining words are fuzzy-matched within the tag-filtered notes")
  func tagPlusText() {
    let results = FuzzyTagSearch.rank(query: "#work roadmap", in: Self.corpus, limit: 50, tagSets: [:])
    #expect(results.map(\.chat.id) == [Self.corpus[2].id])
  }

  @Test("precomputed tag sets are used instead of re-parsing")
  func usesTagSets() {
    let tagSets = [Self.corpus[3].id: Set(["work"])]
    let results = FuzzyTagSearch.rank(query: "#work without", in: Self.corpus, limit: 50, tagSets: tagSets)
    #expect(results.map(\.chat.id) == [Self.corpus[3].id])
  }

  @Test("queries without tags fall back to plain fuzzy ranking")
  func plainFallback() {
    let tagged = FuzzyTagSearch.rank(query: "milk", in: Self.corpus, limit: 50, tagSets: [:])
    let plain = FuzzyController.rank(query: "milk", in: Self.corpus, limit: 50)
    #expect(tagged == plain)
  }

  @Test("tag index re-parses a note only when its updatedAt changes")
  func indexInvalidation() async {
    let index = TagIndex()
    let original = Self.chat("#old")
    #expect(await index.tagSets(for: [original])[original.id] == ["old"])
    var stale = original
    stale.text = "#new"
    #expect(await index.tagSets(for: [stale])[original.id] == ["old"])
    var edited = stale
    edited.updatedAt = Self.base.addingTimeInterval(1)
    #expect(await index.tagSets(for: [edited])[original.id] == ["new"])
  }
}
