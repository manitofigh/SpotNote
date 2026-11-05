/// Line-level longest-common-subsequence matcher used to split a note
/// edit into the smallest set of changed regions. Lines are compared by
/// interned integer ids, so equality checks are O(1).
enum LineDiff {
  /// One aligned pair of identical lines: `old` indexes the base, `new`
  /// the target.
  struct Match: Equatable {
    let old: Int
    let new: Int
  }

  /// Myers' O((N+M)·D) shortest-edit-script search. Returns the matched
  /// line pairs in ascending order, or `nil` when more than `maxEdits`
  /// insertions + deletions would be needed (the caller then falls back
  /// to a single replacement hunk, which is still correct, just larger).
  ///
  /// - Complexity: O((N+M)·D) time, O(D²) memory, where D ≤ `maxEdits`.
  static func matches(_ old: [Int], _ new: [Int], maxEdits: Int) -> [Match]? {
    let total = old.count + new.count
    guard total > 0 else { return [] }
    var frontier = Frontier(maxD: total)
    var trace: [[Int]] = []
    for depth in 0...min(total, maxEdits) {
      trace.append(frontier.window(depth))
      if frontier.advance(depth: depth, old: old, new: new) {
        return backtrack(trace: trace, oldCount: old.count, newCount: new.count)
      }
    }
    return nil
  }

  /// Interns each distinct line slice to a dense integer id so the diff
  /// works on `[Int]`.
  ///
  /// - Complexity: O(total bytes) expected (hashing).
  static func intern(_ oldLines: [ArraySlice<UInt8>], _ newLines: [ArraySlice<UInt8>]) -> ([Int], [Int]) {
    var table: [ArraySlice<UInt8>: Int] = [:]
    func id(_ line: ArraySlice<UInt8>) -> Int {
      if let existing = table[line] { return existing }
      let next = table.count
      table[line] = next
      return next
    }
    return (oldLines.map(id), newLines.map(id))
  }

  private static func backtrack(trace: [[Int]], oldCount: Int, newCount: Int) -> [Match] {
    var x = oldCount
    var y = newCount
    var result: [Match] = []
    for depth in stride(from: trace.count - 1, through: 0, by: -1) {
      let row = trace[depth]
      let k = x - y
      let prevK = Frontier.choosesDown(k: k, depth: depth, row: row) ? k + 1 : k - 1
      let prevX = Frontier.read(row, depth: depth, k: prevK)
      let prevY = prevX - prevK
      while x > prevX, y > prevY {
        x -= 1
        y -= 1
        result.append(Match(old: x, new: y))
      }
      if depth > 0 {
        x = prevX
        y = prevY
      }
    }
    return result.reversed()
  }

  /// The `V` array of Myers' algorithm, indexed by diagonal `k`.
  private struct Frontier {
    private var values: [Int]
    private let offset: Int

    init(maxD: Int) {
      offset = maxD + 1
      values = [Int](repeating: 0, count: 2 * maxD + 3)
    }

    /// Copy of the diagonals `-(depth+1)...(depth+1)` -- the only ones
    /// the next step (and the backtrack) will read.
    func window(_ depth: Int) -> [Int] {
      Array(values[(offset - depth - 1)...(offset + depth + 1)])
    }

    static func read(_ row: [Int], depth: Int, k: Int) -> Int {
      row[k + depth + 1]
    }

    static func choosesDown(k: Int, depth: Int, row: [Int]) -> Bool {
      k == -depth || (k != depth && read(row, depth: depth, k: k - 1) < read(row, depth: depth, k: k + 1))
    }

    /// Extends every reachable diagonal by one edit plus its snake.
    /// Returns `true` once the bottom-right corner is reached.
    mutating func advance(depth: Int, old: [Int], new: [Int]) -> Bool {
      for k in stride(from: -depth, through: depth, by: 2) {
        let down = k == -depth || (k != depth && values[offset + k - 1] < values[offset + k + 1])
        var x = down ? values[offset + k + 1] : values[offset + k - 1] + 1
        var y = x - k
        while x < old.count, y < new.count, old[x] == new[y] {
          x += 1
          y += 1
        }
        values[offset + k] = x
        if x >= old.count, y >= new.count { return true }
      }
      return false
    }
  }
}
