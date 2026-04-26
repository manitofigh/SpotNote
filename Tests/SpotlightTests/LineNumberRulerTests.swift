import AppKit
import Testing

@testable import Spotlight

@Suite("LineNumberRuler")
@MainActor
struct LineNumberRulerTests {
  // MARK: - synthesizedBaseline

  @Test("synthesizedBaseline places all extra vertical space above the baseline")
  func extraSpaceSitsAboveBaseline() {
    let font = NSFont.systemFont(ofSize: 16)
    let fragmentHeight: CGFloat = 22
    let baseline = LineNumberRuler.synthesizedBaseline(
      fragmentHeight: fragmentHeight,
      font: font
    )
    let fontHeight = font.ascender - font.descender
    let expected = (fragmentHeight - fontHeight) + font.ascender
    #expect(abs(baseline - expected) < 0.001)
  }

  @Test("synthesizedBaseline with a fragment exactly the font height gives ascender")
  func fragmentEqualsFontHeight() {
    let font = NSFont.systemFont(ofSize: 14)
    let fontHeight = font.ascender - font.descender
    let baseline = LineNumberRuler.synthesizedBaseline(
      fragmentHeight: fontHeight,
      font: font
    )
    #expect(abs(baseline - font.ascender) < 0.001)
  }

  @Test("synthesizedBaseline does not go negative when the fragment is smaller than the font")
  func clampsWhenFragmentIsSmall() {
    let font = NSFont.systemFont(ofSize: 16)
    let baseline = LineNumberRuler.synthesizedBaseline(fragmentHeight: 5, font: font)
    // With the clamp, extra-space is 0, so baseline == ascender.
    #expect(abs(baseline - font.ascender) < 0.001)
  }

  @Test("synthesizedBaseline grows 1:1 with fragment height beyond the font height")
  func baselineGrowsWithFragment() {
    let font = NSFont.systemFont(ofSize: 16)
    let small = LineNumberRuler.synthesizedBaseline(fragmentHeight: 22, font: font)
    let large = LineNumberRuler.synthesizedBaseline(fragmentHeight: 32, font: font)
    // 10pt of extra fragment height adds 10pt to the baseline.
    #expect(abs((large - small) - 10) < 0.001)
  }

  // MARK: - thickness(forLineCount:labelSize:)

  @Test("thickness is monotonically non-decreasing with line count")
  func thicknessMonotonic() {
    let single = LineNumberRuler.thickness(forLineCount: 1, labelSize: 15)
    let ten = LineNumberRuler.thickness(forLineCount: 10, labelSize: 15)
    let hundred = LineNumberRuler.thickness(forLineCount: 100, labelSize: 15)
    let thousand = LineNumberRuler.thickness(forLineCount: 1000, labelSize: 15)
    #expect(single < ten)
    #expect(ten < hundred)
    #expect(hundred < thousand)
  }

  @Test("thickness is identical within the same digit bucket")
  func thicknessBuckets() {
    let sizes = [1, 5, 9].map { LineNumberRuler.thickness(forLineCount: $0, labelSize: 15) }
    #expect(Set(sizes).count == 1, "all single-digit counts should share a thickness")

    let double = [10, 42, 99].map { LineNumberRuler.thickness(forLineCount: $0, labelSize: 15) }
    #expect(Set(double).count == 1, "all two-digit counts should share a thickness")
  }

  @Test("thickness fits the widest digit at the requested label size")
  func thicknessFitsDigit() {
    let labelSize: CGFloat = 15
    let font = NSFont.monospacedDigitSystemFont(ofSize: labelSize, weight: .regular)
    let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
    let thickness = LineNumberRuler.thickness(forLineCount: 1, labelSize: labelSize)
    #expect(thickness >= ceil(digitWidth))
    // And we add a small breathing-room inset beyond raw digit width.
    #expect(thickness > ceil(digitWidth))
  }

  @Test("thickness tracks label font size -- a bigger font yields a wider gutter")
  func thicknessScalesWithFont() {
    let small = LineNumberRuler.thickness(forLineCount: 10, labelSize: 11)
    let large = LineNumberRuler.thickness(forLineCount: 10, labelSize: 20)
    #expect(small < large)
  }

  @Test("zero or negative line counts do not produce a zero-width gutter")
  func thicknessFloor() {
    let zero = LineNumberRuler.thickness(forLineCount: 0, labelSize: 15)
    let negative = LineNumberRuler.thickness(forLineCount: -5, labelSize: 15)
    let one = LineNumberRuler.thickness(forLineCount: 1, labelSize: 15)
    #expect(zero == one)
    #expect(negative == one)
  }
}
