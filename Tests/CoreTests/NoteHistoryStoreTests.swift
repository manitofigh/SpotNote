import Foundation
import Testing

@testable import Core

@Suite("NoteHistoryStore")
struct NoteHistoryStoreTests {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)
  private let minute: TimeInterval = 60
  private let day: TimeInterval = 86_400

  private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(
      path: "spotnote-history-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
  }

  private func texts(_ store: NoteHistoryStore, _ id: UUID) async -> [String] {
    var result: [String] = []
    for version in await store.versions(of: id) {
      result.append(await store.text(of: id, version: version) ?? "<missing>")
    }
    return result
  }

  // MARK: - Coalescing

  @Test("the first edit records the pre-edit baseline, then edits coalesce for five minutes")
  func editsCoalesce() async {
    let store = NoteHistoryStore(directory: makeDirectory())
    let id = UUID()
    await store.record(id, text: "hello!", trigger: .edit, baseline: "hello", now: start)
    for second in 1...200 {
      let text = "hello! " + String(repeating: "x", count: second)
      await store.record(id, text: text, trigger: .edit, now: start + Double(second))
    }
    #expect(await texts(store, id) == ["hello"])
    let later = "hello! after five minutes"
    await store.record(id, text: later, trigger: .edit, now: start + 5 * minute)
    #expect(await texts(store, id) == [later, "hello"])
  }

  @Test("a checkpoint snapshots edited notes and ignores untouched ones")
  func checkpointNeedsEdit() async {
    let store = NoteHistoryStore(directory: makeDirectory())
    let untouched = UUID()
    await store.record(untouched, text: "browsed only", trigger: .checkpoint, now: start)
    #expect(await store.versions(of: untouched).isEmpty)

    let edited = UUID()
    await store.record(edited, text: "draft 2", trigger: .edit, baseline: "draft", now: start)
    await store.record(edited, text: "draft 2", trigger: .checkpoint, now: start + 1)
    #expect(await texts(store, edited) == ["draft 2", "draft"])
    // Not dirty any more: a second checkpoint adds nothing.
    await store.record(edited, text: "draft 2", trigger: .checkpoint, now: start + 2)
    #expect(await store.versions(of: edited).count == 2)
  }

  @Test("identical text and tiny whitespace-only changes are skipped")
  func skipsTrivialChanges() async {
    let store = NoteHistoryStore(directory: makeDirectory())
    let id = UUID()
    await store.record(id, text: "body", trigger: .destructive, now: start)
    await store.record(id, text: "body", trigger: .destructive, now: start + 1)
    await store.record(id, text: "body ", trigger: .edit, now: start + 2)
    await store.record(id, text: "body ", trigger: .checkpoint, now: start + 3)
    #expect(await store.versions(of: id).count == 1)
    await store.record(id, text: "body ", trigger: .destructive, now: start + 4)
    #expect(await store.versions(of: id).count == 2)
  }

  @Test("versions report added and removed line counts")
  func lineCounts() async {
    let store = NoteHistoryStore(directory: makeDirectory())
    let id = UUID()
    await store.record(id, text: "a\nb\n", trigger: .destructive, now: start)
    await store.record(id, text: "a\nc\nd\n", trigger: .destructive, now: start + 1)
    let newest = await store.versions(of: id).first
    #expect(newest?.addedLines == 2)
    #expect(newest?.removedLines == 1)
  }

  // MARK: - Persistence & keyframes

  @Test("history survives a new store instance and restores every version via keyframes")
  func keyframeRestore() async throws {
    let directory = makeDirectory()
    var config = HistoryConfiguration.standard
    config.keyframeInterval = 4
    let id = UUID()
    var expected: [String] = []
    do {
      let store = NoteHistoryStore(directory: directory, configuration: config)
      var text = "line one\nline two\n"
      for step in 0..<11 {
        text += "step \(step) ✨\n"
        expected.append(text)
        await store.record(id, text: text, trigger: .destructive, now: start + Double(step))
      }
    }
    let reopened = NoteHistoryStore(directory: directory, configuration: config)
    #expect(await texts(reopened, id) == expected.reversed())

    let data = try Data(contentsOf: directory.appending(path: "\(id.uuidString).snhist"))
    let entries = try HistoryCodec.decodeFile(data).entries
    let keyframes = entries.indices.filter { index in
      if case .keyframe = entries[index].payload { return true }
      return false
    }
    #expect(keyframes == [0, 4, 8])
  }

  @Test("a torn trailing record is ignored and the file is repaired on the next write")
  func repairsTornFile() async throws {
    let directory = makeDirectory()
    let id = UUID()
    let url = directory.appending(path: "\(id.uuidString).snhist")
    do {
      let store = NoteHistoryStore(directory: directory)
      await store.record(id, text: "first", trigger: .destructive, now: start)
      await store.record(id, text: "second", trigger: .destructive, now: start + 1)
    }
    let data = try Data(contentsOf: url)
    try data.dropLast(3).write(to: url)
    let store = NoteHistoryStore(directory: directory)
    #expect(await texts(store, id) == ["first"])
    await store.record(id, text: "third", trigger: .destructive, now: start + 2)
    let reopened = NoteHistoryStore(directory: directory)
    #expect(await texts(reopened, id) == ["third", "first"])
  }

  // MARK: - Retention

  @Test("retention keeps everything from the last day and thins older versions")
  func retentionThins() {
    let now = start + 60 * day
    var dates: [Date] = []
    // Two versions per hour for the last 3 days.
    for halfHour in stride(from: 3 * 48, to: 0, by: -1) {
      dates.append(now - Double(halfHour) * 30 * minute)
    }
    let kept = HistoryRetention.keptIndices(dates: dates, now: now, maxVersions: 1_000)
    let keptDates = kept.map { dates[$0] }
    let recent = dates.filter { now.timeIntervalSince($0) < day }
    #expect(recent.allSatisfy(keptDates.contains), "everything from the last 24h is kept")
    let older = keptDates.filter { now.timeIntervalSince($0) >= day }
    let hours = Set(older.map { Int($0.timeIntervalSince1970 / 3600) })
    #expect(older.count == hours.count, "one version per hour beyond 24h")
    #expect(kept.last == dates.count - 1)
  }

  @Test("retention keeps one per day within a month and one per week beyond")
  func retentionLongTail() {
    let now = start + 400 * day
    let dates = stride(from: 300, through: 2, by: -1).map { now - Double($0) * day / 4 }
    let kept = HistoryRetention.keptIndices(dates: dates, now: now, maxVersions: 1_000).map { dates[$0] }
    let daily = kept.filter { now.timeIntervalSince($0) >= 7 * day && now.timeIntervalSince($0) < 30 * day }
    #expect(daily.count == Set(daily.map { Int($0.timeIntervalSince1970 / day) }).count)
    let weekly = kept.filter { now.timeIntervalSince($0) >= 30 * day }
    #expect(weekly.count == Set(weekly.map { Int($0.timeIntervalSince1970 / (7 * day)) }).count)
    #expect(weekly.count <= 7)
  }

  @Test("the per-note version cap drops the oldest versions")
  func versionCap() async {
    var config = HistoryConfiguration.standard
    config.maxVersions = 5
    let store = NoteHistoryStore(directory: makeDirectory(), configuration: config)
    let id = UUID()
    for step in 0..<9 {
      await store.record(id, text: "v\(step)", trigger: .destructive, now: start + Double(step))
    }
    #expect(await texts(store, id) == ["v8", "v7", "v6", "v5", "v4"])
  }

  @Test("the per-note byte budget drops the oldest versions")
  func byteBudget() async throws {
    var config = HistoryConfiguration.standard
    config.maxBytes = 4_096
    let directory = makeDirectory()
    let store = NoteHistoryStore(directory: directory, configuration: config)
    let id = UUID()
    var generator = SeededGenerator(seed: 7)
    for step in 0..<40 {
      // Incompressible, fully replaced text forces a keyframe each time.
      let text = (0..<200).map { _ in String(UInt32.random(in: 0...UInt32.max, using: &generator), radix: 36) }
        .joined()
      await store.record(id, text: "\(step) \(text)", trigger: .destructive, now: start + Double(step))
    }
    let size =
      try FileManager.default.attributesOfItem(
        atPath: directory.appending(path: "\(id.uuidString).snhist").path
      )[.size] as? Int
    #expect((size ?? .max) <= 4_096)
    #expect(await texts(store, id).first?.hasPrefix("39 ") == true)
  }

  // MARK: - Deleted notes

  @Test("a deleted note's history survives until its retention window expires")
  func deletedRetention() async {
    let store = NoteHistoryStore(directory: makeDirectory())
    let id = UUID()
    await store.record(id, text: "keep me", trigger: .destructive, now: start)
    await store.markDeleted(id, now: start)
    await store.purgeExpiredDeletions(now: start + 29 * day)
    #expect(await store.versions(of: id).count == 1)
    await store.purgeExpiredDeletions(now: start + 31 * day)
    #expect(await store.versions(of: id).isEmpty)
  }

  @Test("undoing a delete cancels the pending purge")
  func undeleteKeepsHistory() async {
    let store = NoteHistoryStore(directory: makeDirectory())
    let id = UUID()
    await store.record(id, text: "back again", trigger: .destructive, now: start)
    await store.markDeleted(id, now: start)
    await store.markRestored(id)
    await store.purgeExpiredDeletions(now: start + 90 * day)
    #expect(await texts(store, id) == ["back again"])
  }

  @Test("clearAll removes every note's history")
  func clearAll() async {
    let store = NoteHistoryStore(directory: makeDirectory())
    let id = UUID()
    await store.record(id, text: "gone", trigger: .destructive, now: start)
    await store.clearAll()
    #expect(await store.versions(of: id).isEmpty)
  }

  // MARK: - Size benchmark

  @Test("500 snapshots of a 20KB note with small edits stay compact")
  func sizeBenchmark() async throws {
    var config = HistoryConfiguration.standard
    config.maxVersions = 1_000
    config.maxBytes = .max
    let directory = makeDirectory()
    let store = NoteHistoryStore(directory: directory, configuration: config)
    let id = UUID()
    var generator = SeededGenerator(seed: 42)
    let words = ["note", "meeting", "todo", "idea", "fix", "ship", "review", "draft", "plan", "call"]
    var lines = (0..<470).map { index in
      "\(index): "
        + (0..<7).map { _ in words[Int.random(in: 0..<words.count, using: &generator)] }.joined(separator: " ")
    }
    let initialSize = lines.joined(separator: "\n").utf8.count
    for step in 0..<500 {
      let target = Int.random(in: 0..<lines.count, using: &generator)
      lines[target] += " edit\(step)"
      if step % 7 == 0 { lines.insert("new line \(step)", at: Int.random(in: 0..<lines.count, using: &generator)) }
      await store.record(id, text: lines.joined(separator: "\n"), trigger: .destructive, now: start + Double(step))
    }
    let url = directory.appending(path: "\(id.uuidString).snhist")
    let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
    let rawTotal = initialSize * 500
    print("history benchmark: 500 versions of a \(initialSize)-byte note -> \(size) bytes on disk (raw \(rawTotal))")
    #expect(initialSize >= 20_000)
    #expect(size < 150_000, "500 versions should cost well under 150KB, got \(size)")
    #expect(await store.versions(of: id).count == 500)
    #expect(await texts(store, id).first == lines.joined(separator: "\n"))
  }
}

/// Deterministic SplitMix64 so the benchmark corpus is stable.
private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}
