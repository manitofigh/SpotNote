import Foundation

/// VSCode/Sublime/fzf-style fuzzy matcher. Each character of `query`
/// must appear in `candidate`, in order, case-insensitive. The scorer
/// searches for the best alignment instead of accepting the first
/// subsequence, rewarding word boundaries and consecutive chunks while
/// penalizing gaps so far-apart coincidences do not dominate results.
enum FuzzyMatch {
  struct Result: Equatable, Sendable {
    let score: Int
    /// Character offsets into the candidate where each query character
    /// landed. Useful for highlight overlays.
    let matches: [Int]
  }

  /// Returns `nil` when the query is not a subsequence of the
  /// candidate. An empty query is treated as a zero-score hit so the
  /// palette can render the full corpus while the user is still typing.
  static func score(query: String, in candidate: String) -> Result? {
    if query.isEmpty { return Result(score: 0, matches: []) }
    let negativeInfinity = Int.min / 4
    let input = PreparedInput(query: query, candidate: candidate)
    guard input.pattern.count <= input.original.count else { return nil }
    guard containsSubsequence(input.pattern, in: input.folded) else { return nil }
    let alignment = buildAlignment(for: input, negativeInfinity: negativeInfinity)
    guard let best = bestMatch(in: alignment.scores, candidateCount: input.original.count) else { return nil }
    guard best.score > minimumAcceptedScore(queryLength: input.pattern.count) else { return nil }
    let matches = backtrace(from: best.index, predecessors: alignment.predecessors)
    return Result(score: best.score, matches: matches)
  }

  private static let scoreMatch = 16
  private static let scoreGapStart = -3
  private static let scoreGapExtension = -1
  private static let bonusBoundary = 8
  private static let bonusConsecutive = 4
  private static let bonusCamelOrNumber = 7
  private static let bonusFirstCharacterMultiplier = 2

  private struct PreparedInput {
    let pattern: [String]
    let original: [String]
    let folded: [String]

    init(query: String, candidate: String) {
      self.pattern = Array(query).map { String($0).lowercased() }
      self.original = Array(candidate).map(String.init)
      self.folded = original.map { $0.lowercased() }
    }
  }

  private struct Alignment {
    let scores: [Int]
    let predecessors: [[Int]]
  }

  private struct BestMatch {
    let score: Int
    let index: Int
  }

  private struct RowContext {
    let queryIndex: Int
    let input: PreparedInput
    let previousScores: [Int]
    let negativeInfinity: Int
  }

  private static func buildAlignment(
    for input: PreparedInput,
    negativeInfinity: Int
  ) -> Alignment {
    var previousScores = Array(repeating: negativeInfinity, count: input.original.count)
    var predecessors = Array(
      repeating: Array(repeating: -1, count: input.original.count),
      count: input.pattern.count
    )
    for queryIndex in input.pattern.indices {
      previousScores = scoreRow(
        queryIndex: queryIndex,
        input: input,
        previousScores: previousScores,
        predecessors: &predecessors,
        negativeInfinity: negativeInfinity
      )
    }
    return Alignment(scores: previousScores, predecessors: predecessors)
  }

  private static func scoreRow(
    queryIndex: Int,
    input: PreparedInput,
    previousScores: [Int],
    predecessors: inout [[Int]],
    negativeInfinity: Int
  ) -> [Int] {
    var scores = Array(repeating: negativeInfinity, count: input.original.count)
    var bestGapScore = negativeInfinity
    var bestGapIndex = -1
    let context = RowContext(
      queryIndex: queryIndex,
      input: input,
      previousScores: previousScores,
      negativeInfinity: negativeInfinity
    )
    for candidateIndex in input.folded.indices {
      updateScore(
        context: context,
        candidateIndex: candidateIndex,
        scores: &scores,
        predecessors: &predecessors,
        gap: (score: bestGapScore, index: bestGapIndex)
      )
      updateGap(
        context: context,
        candidateIndex: candidateIndex,
        bestGapScore: &bestGapScore,
        bestGapIndex: &bestGapIndex
      )
    }
    return scores
  }

  private static func updateScore(
    context: RowContext,
    candidateIndex: Int,
    scores: inout [Int],
    predecessors: inout [[Int]],
    gap: (score: Int, index: Int)
  ) {
    let input = context.input
    let queryIndex = context.queryIndex
    guard input.folded[candidateIndex] == input.pattern[queryIndex] else { return }
    let bonus = positionBonus(in: input.original, at: candidateIndex)
    if queryIndex == input.pattern.startIndex {
      scores[candidateIndex] =
        scoreMatch + bonus * bonusFirstCharacterMultiplier - prefixPenalty(candidateIndex)
      return
    }
    let adjacent = adjacentScore(
      previousScores: context.previousScores,
      candidateIndex: candidateIndex,
      bonus: bonus,
      negativeInfinity: context.negativeInfinity
    )
    let gapped = gappedScore(
      bestGapScore: gap.score,
      bonus: bonus,
      negativeInfinity: context.negativeInfinity
    )
    if adjacent.score >= gapped.score {
      scores[candidateIndex] = adjacent.score
      predecessors[queryIndex][candidateIndex] = adjacent.predecessor
    } else {
      scores[candidateIndex] = gapped.score
      predecessors[queryIndex][candidateIndex] = gap.index
    }
  }

  private static func updateGap(
    context: RowContext,
    candidateIndex: Int,
    bestGapScore: inout Int,
    bestGapIndex: inout Int
  ) {
    guard context.queryIndex > 0 else { return }
    if bestGapScore > context.negativeInfinity / 2 {
      bestGapScore += scoreGapExtension
    }
    guard context.previousScores[candidateIndex] > context.negativeInfinity / 2 else { return }
    let startGapScore = context.previousScores[candidateIndex] + scoreGapStart
    if startGapScore > bestGapScore {
      bestGapScore = startGapScore
      bestGapIndex = candidateIndex
    }
  }

  private static func bestMatch(in scores: [Int], candidateCount: Int) -> BestMatch? {
    var bestScore = Int.min / 4
    var bestIndex = -1
    for candidateIndex in scores.indices {
      let score = scores[candidateIndex] - suffixPenalty(candidateCount - candidateIndex - 1)
      if score > bestScore {
        bestScore = score
        bestIndex = candidateIndex
      }
    }
    return bestIndex >= 0 ? BestMatch(score: bestScore, index: bestIndex) : nil
  }

  private static func backtrace(from index: Int, predecessors: [[Int]]) -> [Int] {
    var matches: [Int] = []
    matches.reserveCapacity(predecessors.count)
    var cursor = index
    for queryIndex in stride(from: predecessors.count - 1, through: 0, by: -1) {
      matches.append(cursor)
      cursor = predecessors[queryIndex][cursor]
    }
    return Array(matches.reversed())
  }

  private static func containsSubsequence(_ pattern: [String], in folded: [String]) -> Bool {
    var queryIndex = 0
    for character in folded where queryIndex < pattern.count && character == pattern[queryIndex] {
      queryIndex += 1
    }
    return queryIndex == pattern.count
  }

  private static func adjacentScore(
    previousScores: [Int],
    candidateIndex: Int,
    bonus: Int,
    negativeInfinity: Int
  ) -> (score: Int, predecessor: Int) {
    guard candidateIndex > 0 else { return (negativeInfinity, -1) }
    let predecessor = candidateIndex - 1
    guard previousScores[predecessor] > negativeInfinity / 2 else {
      return (negativeInfinity, -1)
    }
    return (
      previousScores[predecessor] + scoreMatch + max(bonusConsecutive, bonus),
      predecessor
    )
  }

  private static func gappedScore(
    bestGapScore: Int,
    bonus: Int,
    negativeInfinity: Int
  ) -> (score: Int, predecessor: Int) {
    guard bestGapScore > negativeInfinity / 2 else { return (negativeInfinity, -1) }
    return (bestGapScore + scoreMatch + bonus, -1)
  }

  private static func positionBonus(in characters: [String], at index: Int) -> Int {
    guard index > 0 else { return bonusBoundary + 2 }
    let previous = characterClass(characters[index - 1])
    let current = characterClass(characters[index])
    if current.isWordLike, previous == .whitespace { return bonusBoundary + 2 }
    if current.isWordLike, previous == .delimiter { return bonusBoundary + 1 }
    if current.isWordLike, previous == .other { return bonusBoundary }
    if previous == .lowercase, current == .uppercase { return bonusCamelOrNumber }
    if previous != .number, current == .number { return bonusCamelOrNumber }
    return 0
  }

  private static func prefixPenalty(_ skipped: Int) -> Int {
    min(skipped, 48)
  }

  private static func suffixPenalty(_ skipped: Int) -> Int {
    min(skipped / 8, 12)
  }

  private static func minimumAcceptedScore(queryLength: Int) -> Int {
    max(1, queryLength * 6)
  }

  private enum CharacterClass {
    case lowercase
    case uppercase
    case number
    case whitespace
    case delimiter
    case other

    var isWordLike: Bool {
      switch self {
      case .lowercase, .uppercase, .number: return true
      case .whitespace, .delimiter, .other: return false
      }
    }
  }

  private static func characterClass(_ character: String) -> CharacterClass {
    guard let scalar = character.unicodeScalars.first else { return .other }
    switch scalar.value {
    case 0x61...0x7A: return .lowercase
    case 0x41...0x5A: return .uppercase
    case 0x30...0x39: return .number
    case 0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: return .whitespace
    case 0x2D, 0x2E, 0x2F, 0x3A, 0x5F: return .delimiter
    default: return .other
    }
  }
}
