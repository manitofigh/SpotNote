// swiftlint:disable function_body_length
import AppKit
import Testing

@testable import Spotlight

@Suite("Line height consistency")
struct LineHeightConsistencyTests {

  private struct LineInfo {
    let height: CGFloat
    let glyphY: CGFloat
    let baseline: CGFloat
  }

  private func layoutLines(
    for text: String,
    font: NSFont = .systemFont(ofSize: EditorMetrics.fontSize),
    useFixedLayoutManager: Bool = true
  ) -> [LineInfo] {
    let paraStyle = NSMutableParagraphStyle()
    paraStyle.minimumLineHeight = EditorMetrics.lineHeight
    paraStyle.maximumLineHeight = EditorMetrics.lineHeight
    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .paragraphStyle: paraStyle
    ]
    let storage = NSTextStorage(string: text, attributes: attrs)
    let layoutManager: NSLayoutManager
    if useFixedLayoutManager {
      let fixed = FixedLineHeightLayoutManager()
      fixed.fixedLineHeight = EditorMetrics.lineHeight
      layoutManager = fixed
    } else {
      layoutManager = NSLayoutManager()
    }
    let container = NSTextContainer(
      size: NSSize(width: CGFloat(EditorMetrics.panelWidth), height: CGFloat.greatestFiniteMagnitude)
    )
    container.lineFragmentPadding = 0
    layoutManager.addTextContainer(container)
    storage.addLayoutManager(layoutManager)
    layoutManager.ensureLayout(for: container)

    var lines: [LineInfo] = []
    var glyphIndex = 0
    while glyphIndex < layoutManager.numberOfGlyphs {
      var range = NSRange()
      let rect = layoutManager.lineFragmentRect(
        forGlyphAt: glyphIndex,
        effectiveRange: &range
      )
      let loc = layoutManager.location(forGlyphAt: glyphIndex)
      lines.append(
        LineInfo(
          height: rect.height,
          glyphY: loc.y,
          baseline: rect.minY + loc.y
        )
      )
      glyphIndex = NSMaxRange(range)
    }
    return lines
  }

  @Test("all line fragment heights are exactly EditorMetrics.lineHeight")
  func uniformFragmentHeights() {
    let lines = layoutLines(for: "Hello\n\nWorld\nLine4\n")
    #expect(!lines.isEmpty)
    for (i, line) in lines.enumerated() {
      #expect(
        line.height == EditorMetrics.lineHeight,
        "line \(i) height \(line.height) != \(EditorMetrics.lineHeight)"
      )
    }
  }

  @Test("all baseline gaps are identical, including across empty lines")
  func uniformBaselineGaps() {
    let lines = layoutLines(for: "text line\nsecond line\n\nafter empty\nlast line\n")
    #expect(lines.count >= 4)
    var gaps: [CGFloat] = []
    for i in 1..<lines.count {
      gaps.append(lines[i].baseline - lines[i - 1].baseline)
    }
    let unique = Set(gaps.map { ($0 * 100).rounded() / 100 })
    #expect(unique.count == 1, "baseline gaps should be uniform, got \(gaps)")
  }

  @Test("empty lines have the same glyph Y offset as text lines")
  func emptyLineGlyphYMatchesTextLines() {
    let lines = layoutLines(for: "text\n\n\nmore\n")
    let glyphYs = Set(lines.map { ($0.glyphY * 100).rounded() / 100 })
    #expect(glyphYs.count == 1, "all glyphY values should match, got \(lines.map(\.glyphY))")
  }

  @Test("default NSLayoutManager produces uneven baselines on empty lines (the bug)")
  func defaultLayoutManagerHasUnevenBaselines() {
    let lines = layoutLines(
      for: "text\nsecond\n\nafter empty\n",
      useFixedLayoutManager: false
    )
    #expect(lines.count == 4)
    let gap12 = lines[2].baseline - lines[1].baseline
    let gap23 = lines[3].baseline - lines[2].baseline
    #expect(
      gap12 != gap23,
      "default layout manager should produce uneven gaps around empty lines"
    )
  }

  @Test("FixedLineHeightLayoutManager fixes the uneven baselines")
  func fixedLayoutManagerEvensBaselines() {
    let lines = layoutLines(
      for: "text\nsecond\n\nafter empty\n",
      useFixedLayoutManager: true
    )
    #expect(lines.count == 4)
    let gap12 = (lines[2].baseline - lines[1].baseline * 100).rounded() / 100
    let gap23 = (lines[3].baseline - lines[2].baseline * 100).rounded() / 100
    // Use the actual computed gaps, not the intermediate expression
    let realGap12 = lines[2].baseline - lines[1].baseline
    let realGap23 = lines[3].baseline - lines[2].baseline
    #expect(
      (realGap12 * 100).rounded() == (realGap23 * 100).rounded(),
      "fixed layout manager gaps should be equal: \(realGap12) vs \(realGap23)"
    )
  }

  @Test("multiple consecutive empty lines all have uniform spacing")
  func multipleEmptyLines() {
    let lines = layoutLines(for: "A\n\n\n\nB\n")
    #expect(lines.count == 5)
    var gaps: [CGFloat] = []
    for i in 1..<lines.count {
      gaps.append((lines[i].baseline - lines[i - 1].baseline * 100).rounded() / 100)
    }
    let realGaps = (1..<lines.count).map {
      lines[$0].baseline - lines[$0 - 1].baseline
    }
    let rounded = realGaps.map { ($0 * 100).rounded() }
    let unique = Set(rounded)
    #expect(unique.count == 1, "all gaps should be equal, got \(realGaps)")
  }
}
