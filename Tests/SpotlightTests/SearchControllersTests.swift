import Core
import Foundation
import Testing

@testable import Spotlight

@MainActor
@Suite("FindController")
struct FindControllerTests {
  @Test("empty query yields no matches and a zero current index")
  func emptyQueryClears() {
    let controller = FindController()
    controller.search(in: "Some haystack of text")
    #expect(controller.matches.isEmpty)
    #expect(controller.currentIndex == 0)
  }

  @Test("search finds every case-insensitive substring occurrence")
  func findsAllOccurrences() {
    let controller = FindController()
    controller.query = "the"
    controller.search(in: "The quick brown fox jumps over the lazy dog. THE end.")
    #expect(controller.matches.count == 3)
    #expect(controller.currentIndex == 0)
  }

  @Test("next and previous wrap around the match list")
  func navigationWraps() {
    let controller = FindController()
    controller.query = "ab"
    controller.search(in: "ab cd ab ef ab")
    #expect(controller.matches.count == 3)
    controller.next()
    #expect(controller.currentIndex == 1)
    controller.next()
    controller.next()
    #expect(controller.currentIndex == 0)
    controller.previous()
    #expect(controller.currentIndex == 2)
  }

  @Test("close resets every piece of state")
  func closeResets() {
    let controller = FindController()
    controller.open()
    controller.query = "x"
    controller.search(in: "xxx")
    #expect(controller.isVisible)
    controller.close()
    #expect(!controller.isVisible)
    #expect(controller.query.isEmpty)
    #expect(controller.matches.isEmpty)
  }
}

@MainActor
@Suite("FuzzyController")
struct FuzzyControllerTests {
  private func makeChat(_ text: String) -> Chat {
    let now = Date()
    return Chat(id: UUID(), createdAt: now, updatedAt: now, text: text)
  }

  @Test("empty query returns the corpus prefix without ranking")
  func emptyQueryReturnsCorpus() {
    let chats = (0..<3).map { makeChat("note \($0)") }
    let ranked = FuzzyController.rank(query: "", in: chats, limit: 50)
    #expect(ranked.count == 3)
  }

  @Test("rank orders title hits above body hits and drops misses")
  func rankPrefersTitle() {
    let chats = [
      makeChat("Spotlight panel\nimplementation notes"),
      makeChat("Other\nspotlight is mentioned later"),
      makeChat("Completely unrelated text")
    ]
    let ranked = FuzzyController.rank(query: "spotlight", in: chats, limit: 50)
    #expect(ranked.count == 2, "the unrelated note is dropped")
    #expect(ranked.first?.chat.id == chats[0].id, "title hit ranks first")
  }

  @Test("rank caps results at the supplied limit")
  func rankRespectsLimit() {
    let chats = (0..<10).map { makeChat("note \($0) shared keyword") }
    let ranked = FuzzyController.rank(query: "shared", in: chats, limit: 3)
    #expect(ranked.count == 3)
  }

  @Test("rank scores near-misses lower than strong matches")
  func rankScoresFiltersNoise() {
    let chats = [
      makeChat("react hooks tutorial"),
      makeChat("racket macro notes")
    ]
    let ranked = FuzzyController.rank(query: "react", in: chats, limit: 10)
    #expect(ranked.first?.chat.id == chats[0].id, "exact word beats subsequence")
  }

  @Test("rank requires every query term to match")
  func rankRequiresEveryTerm() {
    let chats = [
      makeChat("alpha planning note"),
      makeChat("alpha gamma release note")
    ]
    let ranked = FuzzyController.rank(query: "alpha gamma", in: chats, limit: 10)
    #expect(ranked.map(\.chat.id) == [chats[1].id])
  }

  @Test("rank previews the line that produced a body hit")
  func rankUsesMatchedBodyLineAsPreview() throws {
    let chat = makeChat("Title\n\nimplementation details live here")
    let ranked = FuzzyController.rank(query: "details", in: [chat], limit: 10)
    let result = try #require(ranked.first)
    #expect(result.snippet == "implementation details live here")
    #expect(result.matchRanges == [TextRange(location: 22, length: 7)])
  }

  @Test("rank highlights literal query terms before fuzzy fragments")
  func rankPrefersLiteralHighlight() throws {
    let chat = makeChat("☐ this is some item\n☐ another item")
    let ranked = FuzzyController.rank(query: "this", in: [chat], limit: 10)
    let result = try #require(ranked.first)
    #expect(result.matchRanges == [TextRange(location: 2, length: 4)])
  }

  @Test("preview excerpt clamps large notes around the highlighted match")
  func previewExcerptClampsLargeNotes() throws {
    let prefix = String(repeating: "a", count: FuzzyPreviewExcerpt.characterLimit + 500)
    let text = prefix + "needle" + String(repeating: "b", count: FuzzyPreviewExcerpt.characterLimit)
    let range = TextRange(location: prefix.count, length: 6)

    let excerpt = FuzzyPreviewExcerpt.make(text: text, ranges: [range])
    let highlighted = try #require(excerpt.ranges.first)
    let start = excerpt.text.index(excerpt.text.startIndex, offsetBy: highlighted.location)
    let end = excerpt.text.index(start, offsetBy: highlighted.length)

    #expect(excerpt.text.count <= FuzzyPreviewExcerpt.characterLimit + 8)
    #expect(String(excerpt.text[start..<end]) == "needle")
  }

  @Test("previewLine returns the first non-empty line trimmed and clamped")
  func previewLineTrims() {
    let preview = FuzzyController.previewLine("\n\n  hello world  \nsecond line")
    #expect(preview == "hello world")
  }

  @Test("rank stamps each result with its 1-based corpus position")
  func rankPropagatesPosition() throws {
    let chats = [makeChat("alpha"), makeChat("beta"), makeChat("gamma")]
    let ranked = FuzzyController.rank(query: "", in: chats, limit: 50)
    #expect(ranked.map { $0.position } == [1, 2, 3])
  }

  @Test("moveSelection changes the selected fuzzy result without touching chats")
  func moveSelectionChangesSelectedResult() {
    let controller = FuzzyController()
    let chats = [makeChat("alpha"), makeChat("beta"), makeChat("gamma")]
    controller.open(corpus: chats)
    #expect(controller.selectedChat()?.id == chats[0].id)
    controller.moveSelection(by: 1)
    #expect(controller.selectedChat()?.id == chats[1].id)
    controller.moveSelection(by: -1)
    #expect(controller.selectedChat()?.id == chats[0].id)
  }

  @Test("⌃W word delete trims the trailing word and any trailing whitespace")
  func ctrlWStripsTrailingWord() {
    #expect(SearchTextEditing.deleteWordBackward("hello world") == "hello ")
    #expect(SearchTextEditing.deleteWordBackward("hello world  ") == "hello ")
    #expect(SearchTextEditing.deleteWordBackward("oneword").isEmpty)
    #expect(SearchTextEditing.deleteWordBackward("").isEmpty)
  }

  @Test("toggle opens and closes the palette")
  func toggleOpensCloses() {
    let controller = FuzzyController()
    controller.toggle(corpus: [makeChat("a")])
    #expect(controller.isVisible)
    controller.toggle(corpus: [])
    #expect(!controller.isVisible)
  }
}

@MainActor
@Suite("CommandController")
struct CommandControllerTests {
  private func makeDefaults() -> UserDefaults {
    let suite = "spotnote.command-controller.\(UUID().uuidString)"
    return UserDefaults(suiteName: suite) ?? .standard
  }

  @Test("shortcut rows expose executable actions while settings rows do not")
  func executableRows() throws {
    let defaults = makeDefaults()
    let controller = CommandController()
    controller.open(
      shortcuts: ShortcutStore(defaults: defaults),
      preferences: ThemePreferences(defaults: defaults)
    )

    let newChatIndex = try #require(controller.results.firstIndex { $0.id == "shortcut.newChat" })
    controller.selectedIndex = newChatIndex
    #expect(controller.selectedExecutableAction() == .newChat)

    let settingIndex = try #require(controller.results.firstIndex { $0.id == "setting.lineNumbers" })
    controller.selectedIndex = settingIndex
    #expect(controller.selectedExecutableAction() == nil)
  }

  @Test("opening and explicit refocus requests advance the focus token")
  func focusRequestsAdvance() {
    let defaults = makeDefaults()
    let controller = CommandController()
    controller.open(
      shortcuts: ShortcutStore(defaults: defaults),
      preferences: ThemePreferences(defaults: defaults)
    )
    let openedRequest = controller.focusRequest

    controller.requestFocus()

    #expect(openedRequest > 0)
    #expect(controller.focusRequest == openedRequest + 1)
  }
}
