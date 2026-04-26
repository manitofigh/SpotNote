import Foundation
import Testing

@testable import Spotlight

@Suite("FuzzyMatch")
struct FuzzyMatchTests {
  @Test("empty query is a free zero-score hit so the palette renders")
  func emptyQueryHits() {
    let result = FuzzyMatch.score(query: "", in: "anything at all")
    #expect(result?.score == 0)
    #expect(result?.matches.isEmpty == true)
  }

  @Test("query is matched as a subsequence, in order, case-insensitive")
  func subsequenceCaseInsensitive() {
    let result = FuzzyMatch.score(query: "SPN", in: "Spotlight Panel")
    #expect(result != nil)
    let absent = FuzzyMatch.score(query: "spz", in: "spotlight")
    #expect(absent == nil)
  }

  @Test("characters that don't appear in order return nil")
  func outOfOrderMisses() {
    #expect(FuzzyMatch.score(query: "tn", in: "note") == nil)
  }

  @Test("consecutive matches outscore the same characters scattered apart")
  func consecutiveBeatsScattered() throws {
    // Word-start bonuses are worth more than consecutive bonuses on
    // purpose, so the comparison uses scattered hits buried mid-word
    // (no word-start credit) against a single consecutive run.
    let consecutive = try #require(FuzzyMatch.score(query: "bcd", in: "abcde"))
    let scattered = try #require(FuzzyMatch.score(query: "bcd", in: "axbxcxd"))
    #expect(consecutive.score > scattered.score)
  }

  @Test("matches at word starts outscore matches mid-word")
  func wordStartBonus() throws {
    let atStart = try #require(FuzzyMatch.score(query: "ip", in: "internet protocol"))
    let midWord = try #require(FuzzyMatch.score(query: "ip", in: "tipping"))
    #expect(atStart.score > midWord.score)
  }

  @Test("matches array records every byte position the query landed on")
  func recordsMatchPositions() {
    let result = FuzzyMatch.score(query: "abc", in: "axbxcx")
    #expect(result?.matches == [0, 2, 4])
  }
}
