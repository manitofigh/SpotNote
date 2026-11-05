import Foundation
import Testing

@testable import Core

@Suite("HistoryDelta")
struct HistoryDeltaTests {
  struct Pair: Sendable, CustomTestStringConvertible {
    let name: String
    let old: String
    let new: String
    var testDescription: String { name }
  }

  static let pairs: [Pair] = [
    Pair(name: "both empty", old: "", new: ""),
    Pair(name: "from empty", old: "", new: "hello\nworld"),
    Pair(name: "to empty", old: "hello\nworld\n", new: ""),
    Pair(name: "identical", old: "same\ntext", new: "same\ntext"),
    Pair(name: "full replacement", old: "alpha\nbeta\ngamma", new: "one\ntwo\nthree\nfour"),
    Pair(name: "single char inside a line", old: "the quick brown fox", new: "the quick brawn fox"),
    Pair(name: "edits at top and bottom", old: "a\nb\nc\nd\ne\nf\n", new: "A\nb\nc\nd\ne\nF\n"),
    Pair(name: "inserted lines", old: "a\nc\n", new: "a\nb\nb2\nc\n"),
    Pair(name: "removed lines", old: "a\nb\nc\nd\n", new: "a\nd\n"),
    Pair(name: "no trailing newline change", old: "a\nb", new: "a\nb\n"),
    Pair(name: "emoji and combining marks", old: "café 👋🏽 naïve\n日本語", new: "cafe\u{301} 👋🏿 naïve\n日本人"),
    Pair(name: "multi-byte boundary", old: "ÅÅÅ", new: "ÅÄÅ"),
    Pair(name: "CRLF lines", old: "one\r\ntwo\r\n", new: "one\r\n2\r\ntwo\r\n")
  ]

  @Test("applying the delta reproduces the target exactly", arguments: pairs)
  func roundTrips(pair: Pair) throws {
    let old = Array(pair.old.utf8)
    let new = Array(pair.new.utf8)
    let delta = HistoryDelta.between(old, new)
    let rebuilt = try delta.apply(to: old)
    #expect(rebuilt == new)
    #expect(String(bytes: rebuilt, encoding: .utf8) == pair.new)
  }

  @Test("a one-character edit in a large note stores only a few bytes")
  func smallEditStaysSmall() {
    let lines = (0..<500).map { "line \($0) with some filler text to make it long" }
    let old = lines.joined(separator: "\n")
    var edited = lines
    edited[250] = "line 250 with some filler text to make it lung"
    edited[10] = "line 10 with some filler text to make it long!"
    let delta = HistoryDelta.between(Array(old.utf8), Array(edited.joined(separator: "\n").utf8))
    #expect(delta.hunks.count == 2)
    #expect(delta.insertedByteCount <= 4)
  }

  @Test("identical text produces an empty delta")
  func identicalIsEmpty() {
    let bytes = Array("unchanged".utf8)
    #expect(HistoryDelta.between(bytes, bytes).isEmpty)
  }

  @Test("whitespace-only edits are recognised up to the tolerance")
  func whitespaceOnly() {
    let base = Array("hello world".utf8)
    let spaced = HistoryDelta.between(base, Array("hello  world ".utf8))
    #expect(spaced.isWhitespaceOnly(base: base, limit: 8))
    let worded = HistoryDelta.between(base, Array("hello there".utf8))
    #expect(!worded.isWhitespaceOnly(base: base, limit: 8))
    let large = HistoryDelta.between(base, Array("hello world\n\n\n\n\n\n\n\n\n\n".utf8))
    #expect(!large.isWhitespaceOnly(base: base, limit: 8))
  }

  @Test("line stats count added and removed lines")
  func lineStats() {
    let stats = HistoryDelta.lineStats(from: Array("a\nb\nc\n".utf8), to: Array("a\nc\nd\ne\n".utf8))
    #expect(stats.added == 2)
    #expect(stats.removed == 1)
    let inline = HistoryDelta.lineStats(from: Array("one two".utf8), to: Array("one too".utf8))
    #expect(inline == (1, 1))
    let grown = HistoryDelta.lineStats(from: Array("x".utf8), to: Array("yx".utf8))
    #expect(grown == (1, 1))
  }

  @Test("a delta pointing outside its base is rejected as corrupted")
  func rejectsOutOfBounds() {
    let delta = HistoryDelta(hunks: [.init(offset: 10, removeCount: 5, inserted: [])])
    #expect(throws: NoteHistoryError.corrupted) { try delta.apply(to: [1, 2, 3]) }
  }

  @Test("the line diff finds the longest common subsequence")
  func lineDiffMatches() {
    let matches = LineDiff.matches([1, 2, 3, 4, 5], [1, 3, 4, 6, 5], maxEdits: 100)
    #expect(matches?.map(\.old) == [0, 2, 3, 4])
    #expect(matches?.map(\.new) == [0, 1, 2, 4])
  }

  @Test("the line diff gives up beyond its edit budget")
  func lineDiffBudget() {
    #expect(LineDiff.matches(Array(0..<50), Array(100..<150), maxEdits: 10) == nil)
  }
}

@Suite("HistoryCodec")
struct HistoryCodecTests {
  @Test("records round-trip through the binary file format, compressed or not")
  func fileRoundTrip() throws {
    let big = Array(String(repeating: "compressible text ", count: 200).utf8)
    let delta = HistoryDelta(hunks: [.init(offset: 3, removeCount: 2, inserted: Array("é!".utf8))])
    let entries = [
      HistoryEntry(date: Date(timeIntervalSince1970: 1_000), payload: .keyframe(big)),
      HistoryEntry(date: Date(timeIntervalSince1970: 2_000.5), payload: .delta(delta)),
      HistoryEntry(date: Date(timeIntervalSince1970: 3_000), payload: .keyframe([]))
    ]
    let data = HistoryCodec.encodeFile(entries)
    #expect(data.count < big.count / 4, "keyframe should be lzfse-compressed")
    let decoded = try HistoryCodec.decodeFile(data)
    #expect(decoded.entries == entries)
    #expect(!decoded.isTruncated)
  }

  @Test("a torn trailing record is dropped and reported")
  func tornTail() throws {
    let entries = [
      HistoryEntry(date: Date(timeIntervalSince1970: 1), payload: .keyframe(Array("one".utf8))),
      HistoryEntry(date: Date(timeIntervalSince1970: 2), payload: .keyframe(Array("two".utf8)))
    ]
    let data = HistoryCodec.encodeFile(entries)
    let decoded = try HistoryCodec.decodeFile(data.dropLast(2))
    #expect(decoded.entries == [entries[0]])
    #expect(decoded.isTruncated)
  }

  @Test("a file without the magic header is rejected")
  func badMagic() {
    #expect(throws: NoteHistoryError.corrupted) { try HistoryCodec.decodeFile(Data("nope".utf8)) }
  }
}
