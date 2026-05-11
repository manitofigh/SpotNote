import AppKit
import Core
import SwiftUI

final class FuzzyPreviewPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

struct FuzzyPreviewCard: View {
  @ObservedObject var controller: FuzzyController
  @ObservedObject var preferences: ThemePreferences

  static let preferredWidth: CGFloat = 360
  static let minimumWidth: CGFloat = 260
  static let gap: CGFloat = 12

  private var theme: Theme { preferences.activeTheme }

  var body: some View {
    if let result = controller.selectedResult() {
      VStack(alignment: .leading, spacing: 8) {
        header(result)
        Divider().background(theme.border).opacity(0.6)
        ScrollView {
          Text(highlightedText(for: result))
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(theme.text.opacity(0.86))
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 2)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(theme.background)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(theme.border, lineWidth: 1)
      )
      .colorScheme(theme.mode == .dark ? .dark : .light)
    }
  }

  private func header(_ result: FuzzyResult) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(theme.placeholder)
      Text("#\(result.position)")
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(theme.placeholder)
      if result.chat.isPinned {
        Text("★")
          .font(.system(size: 10))
          .foregroundStyle(Color(red: 0.95, green: 0.75, blue: 0.25))
      }
      Text(result.snippet.isEmpty ? "(empty note)" : result.snippet)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(theme.text)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 0)
    }
  }

  private func highlightedText(for result: FuzzyResult) -> AttributedString {
    let excerpt = FuzzyPreviewExcerpt.make(for: result)
    let text = excerpt.text
    var attributed = AttributedString(text)
    guard !excerpt.ranges.isEmpty else { return attributed }
    let highlight = Color(red: 0.95, green: 0.78, blue: 0.28).opacity(theme.mode == .dark ? 0.26 : 0.34)
    for range in excerpt.ranges {
      guard range.location >= 0, range.length > 0 else { continue }
      guard range.location + range.length <= text.count else { continue }
      let start = attributed.index(attributed.startIndex, offsetByCharacters: range.location)
      let end = attributed.index(start, offsetByCharacters: range.length)
      attributed[start..<end].backgroundColor = highlight
      attributed[start..<end].foregroundColor = theme.text
    }
    return attributed
  }
}

struct FuzzyPreviewExcerpt: Equatable, Sendable {
  static let characterLimit = 6_000

  let text: String
  let ranges: [TextRange]

  static func make(for result: FuzzyResult) -> FuzzyPreviewExcerpt {
    make(text: result.chat.text, ranges: result.matchRanges)
  }

  static func make(text rawText: String, ranges: [TextRange]) -> FuzzyPreviewExcerpt {
    guard !rawText.isEmpty else {
      return FuzzyPreviewExcerpt(text: "(empty note)", ranges: [])
    }
    if rawText.prefix(characterLimit + 1).count <= characterLimit {
      return FuzzyPreviewExcerpt(text: rawText, ranges: ranges)
    }

    let anchor = ranges.first?.location ?? 0
    let requestedStartOffset = max(0, anchor - characterLimit / 4)
    let startIndex: String.Index
    let startOffset: Int
    if let index = rawText.index(
      rawText.startIndex,
      offsetBy: requestedStartOffset,
      limitedBy: rawText.endIndex
    ) {
      startIndex = index
      startOffset = requestedStartOffset
    } else {
      startIndex = rawText.startIndex
      startOffset = 0
    }

    let endIndex =
      rawText.index(startIndex, offsetBy: characterLimit, limitedBy: rawText.endIndex)
      ?? rawText.endIndex
    let visibleText = String(rawText[startIndex..<endIndex])
    let prefix = startIndex > rawText.startIndex ? "...\n" : ""
    let suffix = endIndex < rawText.endIndex ? "\n..." : ""
    let adjusted = adjustedRanges(
      ranges,
      startOffset: startOffset,
      visibleLength: visibleText.count,
      prefixLength: prefix.count
    )
    return FuzzyPreviewExcerpt(
      text: prefix + visibleText + suffix,
      ranges: adjusted
    )
  }

  private static func adjustedRanges(
    _ ranges: [TextRange],
    startOffset: Int,
    visibleLength: Int,
    prefixLength: Int
  ) -> [TextRange] {
    let endOffset = startOffset + visibleLength
    return ranges.compactMap { range in
      let lower = max(range.location, startOffset)
      let upper = min(range.location + range.length, endOffset)
      guard lower < upper else { return nil }
      return TextRange(
        location: lower - startOffset + prefixLength,
        length: upper - lower
      )
    }
  }
}
