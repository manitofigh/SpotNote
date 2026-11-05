import Foundation

/// Per-note version history, independent of how notes themselves are
/// stored. Lives in the app's own Application Support
/// (`SpotNote/History`, a sibling of `SpotNote/Chats`) -- never inside a
/// user-chosen notes folder.
///
/// Storage: one compact binary file per note (`<uuid>.snhist`, see
/// `HistoryCodec`) holding keyframes + line/byte deltas, lzfse
/// compressed per record. New versions are appended; thinning rewrites
/// the file atomically. Nothing is read at launch: a note's file is
/// decoded the first time that note is snapshotted or browsed, and only
/// `cacheLimit` decoded logs stay in memory.
///
/// Deleted notes: `markDeleted` snapshots nothing itself (callers send a
/// `.destructive` snapshot first) but records a tombstone in
/// `deleted.json`; `purgeExpiredDeletions` removes histories whose
/// tombstone is older than `deletedRetention` (30 days). Undoing the
/// delete clears the tombstone.
///
/// Every API takes `now` so tests drive time explicitly.
public actor NoteHistoryStore {
  private let directory: URL
  private let configuration: HistoryConfiguration
  private var cache: [UUID: NoteHistoryLog] = [:]
  private var recency: [UUID] = []
  /// Start of the current unsnapshotted edit burst per note.
  private var dirtySince: [UUID: Date] = [:]
  /// Notes whose file has a torn tail and must be rewritten, not appended.
  private var needsRewrite: Set<UUID> = []

  public init(directory: URL, configuration: HistoryConfiguration = .standard) {
    self.directory = directory
    self.configuration = configuration
  }

  /// Process-wide store at `defaultDirectory()`. `nil` only if
  /// Application Support cannot be resolved, in which case history is
  /// silently unavailable rather than blocking note editing.
  public static let shared: NoteHistoryStore? = (try? defaultDirectory()).map { NoteHistoryStore(directory: $0) }

  /// `UserDefaults` key of the user-facing on/off switch (default on).
  public static let enabledDefaultsKey = "history.enabled"

  public static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: enabledDefaultsKey) as? Bool ?? true
  }

  /// `.../Application Support/SpotNote/History`. Mirrors
  /// `ChatStore.defaultDirectory()`: unsandboxed debug builds prefer the
  /// sandbox container when it exists so both builds share one history.
  public static func defaultDirectory() throws -> URL {
    let container = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Containers", directoryHint: .isDirectory)
      .appending(path: AppInfo.bundleIdentifier, directoryHint: .isDirectory)
      .appending(path: "Data/Library/Application Support", directoryHint: .isDirectory)
    let appSupport =
      FileManager.default.fileExists(atPath: container.appending(path: "SpotNote").path)
      ? container
      : try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    return
      appSupport
      .appending(path: "SpotNote", directoryHint: .isDirectory)
      .appending(path: "History", directoryHint: .isDirectory)
  }

  // MARK: - Recording

  /// Offers `text` as a snapshot of note `id`. Whether a version is
  /// actually written depends on `trigger` (see `HistorySnapshotTrigger`)
  /// and on the text having changed meaningfully since the last version.
  ///
  /// - Parameter baseline: for `.edit`, the note's text *before* this
  ///   edit. Recorded as the first version when the note has no history
  ///   yet, so the pre-edit state is always recoverable.
  public func record(
    _ id: UUID,
    text: String,
    trigger: HistorySnapshotTrigger,
    baseline: String? = nil,
    now: Date = Date()
  ) {
    var log = loadLog(id)
    if trigger == .edit {
      if log.isEmpty, let baseline, !baseline.isEmpty {
        commit(id, &log, bytes: Array(baseline.utf8), now: now)
      }
      if dirtySince[id] == nil { dirtySince[id] = now }
    }
    let anchor = [log.lastDate, dirtySince[id]].compactMap { $0 }.max()
    let isDue = HistoryCoalescer.isDue(
      trigger,
      isDirty: dirtySince[id] != nil,
      anchor: anchor,
      now: now,
      interval: configuration.editInterval
    )
    guard isDue else { return }
    let bytes = Array(text.utf8)
    if log.isEmpty {
      if !bytes.isEmpty { commit(id, &log, bytes: bytes, now: now) }
      dirtySince[id] = nil
      return
    }
    let delta = HistoryDelta.between(log.latest, bytes)
    let tolerance = configuration.whitespaceTolerance
    if HistoryCoalescer.isMeaningful(delta, base: log.latest, trigger: trigger, whitespaceTolerance: tolerance) {
      commit(id, &log, bytes: bytes, delta: delta, now: now)
    }
    dirtySince[id] = nil
  }

  /// Records that note `id` was deleted at `now`; its history is purged
  /// after `deletedRetention` unless `markRestored` is called first.
  public func markDeleted(_ id: UUID, now: Date = Date()) {
    dirtySince[id] = nil
    var tombstones = loadTombstones()
    tombstones[id.uuidString] = now.timeIntervalSince1970
    saveTombstones(tombstones)
  }

  public func markRestored(_ id: UUID) {
    var tombstones = loadTombstones()
    guard tombstones.removeValue(forKey: id.uuidString) != nil else { return }
    saveTombstones(tombstones)
  }

  /// Deletes histories of notes deleted more than `deletedRetention`
  /// ago. Reads only the small tombstone index, never history files.
  public func purgeExpiredDeletions(now: Date = Date()) {
    var tombstones = loadTombstones()
    let cutoff = now.timeIntervalSince1970 - configuration.deletedRetention
    let expired = tombstones.filter { $0.value <= cutoff }.keys
    guard !expired.isEmpty else { return }
    for key in expired {
      tombstones[key] = nil
      guard let id = UUID(uuidString: key) else { continue }
      evict(id)
      try? FileManager.default.removeItem(at: fileURL(for: id))
    }
    saveTombstones(tombstones)
  }

  /// Removes every stored version of every note.
  public func clearAll() {
    cache = [:]
    recency = []
    dirtySince = [:]
    needsRewrite = []
    try? FileManager.default.removeItem(at: directory)
  }

  // MARK: - Browsing

  /// Stored versions of note `id`, newest first. Empty when none (or
  /// when the file is unreadable).
  public func versions(of id: UUID) -> [NoteVersion] {
    (try? loadLog(id).summaries()) ?? []
  }

  /// Full text of `version`, or `nil` if it no longer exists.
  /// - Complexity: O(K · text size), K = keyframe interval.
  public func text(of id: UUID, version: NoteVersion) -> String? {
    let log = loadLog(id)
    let index =
      log.entries.indices.contains(version.id) && log.entries[version.id].date == version.date
      ? version.id
      : log.entries.lastIndex { $0.date == version.date }
    guard let index, let bytes = try? log.bytes(at: index) else { return nil }
    return String(bytes: bytes, encoding: .utf8)
  }

  // MARK: - Private

  private func commit(
    _ id: UUID,
    _ log: inout NoteHistoryLog,
    bytes: [UInt8],
    delta: HistoryDelta? = nil,
    now: Date
  ) {
    let resolved = delta ?? (log.isEmpty ? nil : HistoryDelta.between(log.latest, bytes))
    let entry = log.append(bytes, delta: resolved, date: now, keyframeInterval: configuration.keyframeInterval)
    let kept = HistoryRetention.keptIndices(
      dates: log.entries.map(\.date),
      now: now,
      maxVersions: configuration.maxVersions
    )
    let interval = configuration.keyframeInterval
    if kept.count < log.entries.count, let thinned = try? log.compacted(keeping: kept, keyframeInterval: interval) {
      log = thinned
      rewrite(id, log: &log)
    } else if needsRewrite.contains(id) || log.entries.count == 1 {
      rewrite(id, log: &log)
    } else {
      append(id, entry: entry, log: &log)
    }
    store(id, log)
  }

  private func append(_ id: UUID, entry: HistoryEntry, log: inout NoteHistoryLog) {
    let url = fileURL(for: id)
    do {
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: HistoryCodec.encodeRecord(entry))
      if let size = try? handle.offset(), size > configuration.maxBytes { rewrite(id, log: &log) }
    } catch {
      rewrite(id, log: &log)
    }
  }

  /// Atomically replaces the file with `log`, first trimming the oldest
  /// versions until it fits `maxBytes`.
  private func rewrite(_ id: UUID, log: inout NoteHistoryLog) {
    var data = HistoryCodec.encodeFile(log.entries)
    while data.count > configuration.maxBytes, log.entries.count > 1 {
      let drop = max(1, log.entries.count / 4)
      let kept = Array(drop..<log.entries.count)
      guard let trimmed = try? log.compacted(keeping: kept, keyframeInterval: configuration.keyframeInterval) else {
        break
      }
      log = trimmed
      data = HistoryCodec.encodeFile(log.entries)
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: fileURL(for: id), options: .atomic)
      needsRewrite.remove(id)
    } catch {
      needsRewrite.insert(id)
    }
  }

  private func loadLog(_ id: UUID) -> NoteHistoryLog {
    if let cached = cache[id] {
      touch(id)
      return cached
    }
    var log = NoteHistoryLog()
    if let data = try? Data(contentsOf: fileURL(for: id)) {
      do {
        let decoded = try HistoryCodec.decodeFile(data)
        log = try NoteHistoryLog(entries: decoded.entries)
        if decoded.isTruncated { needsRewrite.insert(id) }
      } catch {
        // Unreadable history: start fresh and overwrite on next commit.
        needsRewrite.insert(id)
      }
    }
    store(id, log)
    return log
  }

  private func store(_ id: UUID, _ log: NoteHistoryLog) {
    cache[id] = log
    touch(id)
    while recency.count > configuration.cacheLimit {
      cache[recency.removeFirst()] = nil
    }
  }

  private func touch(_ id: UUID) {
    recency.removeAll { $0 == id }
    recency.append(id)
  }

  private func evict(_ id: UUID) {
    cache[id] = nil
    recency.removeAll { $0 == id }
    dirtySince[id] = nil
    needsRewrite.remove(id)
  }

  private func fileURL(for id: UUID) -> URL {
    directory.appending(path: "\(id.uuidString).snhist", directoryHint: .notDirectory)
  }

  private var tombstoneURL: URL {
    directory.appending(path: "deleted.json", directoryHint: .notDirectory)
  }

  private func loadTombstones() -> [String: Double] {
    guard let data = try? Data(contentsOf: tombstoneURL) else { return [:] }
    return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
  }

  private func saveTombstones(_ tombstones: [String: Double]) {
    guard let data = try? JSONEncoder().encode(tombstones) else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: tombstoneURL, options: .atomic)
  }
}
