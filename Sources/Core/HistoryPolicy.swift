import Foundation

/// Why a snapshot is being offered to `NoteHistoryStore.record`.
public enum HistorySnapshotTrigger: Sendable, Equatable {
  /// A keystroke-level edit. Snapshots at most once per
  /// `HistoryConfiguration.editInterval` of continuous editing.
  case edit
  /// A natural pause -- HUD hidden, note switched, app quitting. Only
  /// snapshots notes edited since their last snapshot.
  case checkpoint
  /// Immediately around a destructive operation (restoring a version,
  /// deleting a note). Always snapshots unless the text is unchanged.
  case destructive
}

/// Tunables for snapshot cadence, storage layout, and retention.
public struct HistoryConfiguration: Sendable {
  /// Minimum spacing of `.edit`-triggered snapshots.
  var editInterval: TimeInterval = 5 * 60
  /// A full keyframe is written every `keyframeInterval` versions, so
  /// reconstructing any version applies at most `keyframeInterval - 1`
  /// deltas.
  var keyframeInterval = 50
  /// Hard cap on versions kept per note (oldest dropped first).
  var maxVersions = 200
  /// Per-note file budget; oldest versions are dropped past it.
  var maxBytes = 1 << 20
  /// Whitespace-only changes touching at most this many bytes are not
  /// worth a version on their own.
  var whitespaceTolerance = 8
  /// How long a deleted note's history is kept (for undo / recovery).
  var deletedRetention: TimeInterval = 30 * 24 * 60 * 60
  /// Number of per-note logs kept decoded in memory.
  var cacheLimit = 8

  public static let standard = HistoryConfiguration()
}

/// Pure coalescing rules, separated from the actor so they can be
/// tested without I/O.
enum HistoryCoalescer {
  /// Whether `trigger` should even consider a snapshot right now.
  /// - Parameter anchor: start of the current edit burst -- the later of
  ///   the last snapshot and the first unsnapshotted edit.
  static func isDue(
    _ trigger: HistorySnapshotTrigger,
    isDirty: Bool,
    anchor: Date?,
    now: Date,
    interval: TimeInterval
  ) -> Bool {
    switch trigger {
    case .edit:
      guard let anchor else { return false }
      return now.timeIntervalSince(anchor) >= interval
    case .checkpoint:
      return isDirty
    case .destructive:
      return true
    }
  }

  /// Identical text is never a new version; tiny whitespace-only edits
  /// are skipped unless a destructive operation demands a checkpoint.
  static func isMeaningful(
    _ delta: HistoryDelta,
    base: [UInt8],
    trigger: HistorySnapshotTrigger,
    whitespaceTolerance: Int
  ) -> Bool {
    guard !delta.isEmpty else { return false }
    if trigger == .destructive { return true }
    return !delta.isWhitespaceOnly(base: base, limit: whitespaceTolerance)
  }
}

/// Grandfather-father-son thinning of a note's versions.
///
/// - every version from the last 24 hours,
/// - the newest version per clock hour for the last 7 days,
/// - the newest per day for the last 30 days,
/// - the newest per week beyond that,
/// then capped to the newest `maxVersions`. The newest version is always
/// kept. Buckets are absolute (aligned to the Unix epoch), so a version
/// that survives thinning once keeps surviving as it ages within a tier.
enum HistoryRetention {
  private static let hour: TimeInterval = 3600
  private static let day: TimeInterval = 24 * hour
  private static let tiers: [(maxAge: TimeInterval, bucket: TimeInterval)] = [
    (day, 0),
    (7 * day, hour),
    (30 * day, day),
    (.infinity, 7 * day)
  ]

  /// - Parameter dates: version timestamps, oldest first.
  /// - Returns: indices to keep, ascending.
  /// - Complexity: O(n).
  static func keptIndices(dates: [Date], now: Date, maxVersions: Int) -> [Int] {
    var seen: Set<BucketKey> = []
    var kept: [Int] = []
    for index in dates.indices.reversed() {
      let age = now.timeIntervalSince(dates[index])
      let tier = tiers.firstIndex { age < $0.maxAge } ?? tiers.count - 1
      let bucketSize = tiers[tier].bucket
      if bucketSize > 0 {
        let key = BucketKey(tier: tier, bucket: Int((dates[index].timeIntervalSince1970 / bucketSize).rounded(.down)))
        guard seen.insert(key).inserted else { continue }
      }
      kept.append(index)
      if kept.count >= max(1, maxVersions) { break }
    }
    return kept.reversed()
  }

  private struct BucketKey: Hashable {
    let tier: Int
    let bucket: Int
  }
}
