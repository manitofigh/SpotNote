import Testing

@testable import Spotlight

@Suite("EditorMetrics")
struct EditorMetricsTests {
  @Test("empty string is one logical line")
  func emptyIsOneLine() {
    #expect(EditorMetrics.lineCount(in: "") == 1)
  }

  @Test("single line with no newline is one line")
  func singleLine() {
    #expect(EditorMetrics.lineCount(in: "hello") == 1)
  }

  @Test("n newlines produce n+1 logical lines")
  func newlineCount() {
    #expect(EditorMetrics.lineCount(in: "a\nb") == 2)
    #expect(EditorMetrics.lineCount(in: "a\nb\nc") == 3)
    #expect(EditorMetrics.lineCount(in: "a\nb\nc\nd") == 4)
  }

  @Test("trailing newline counts as starting a new line")
  func trailingNewline() {
    #expect(EditorMetrics.lineCount(in: "a\n") == 2)
  }

  @Test("panelHeight is monotonically non-decreasing within the clamp range")
  func panelHeightMonotonic() {
    let one = EditorMetrics.panelHeight(forLines: 1, maxLines: 3)
    let two = EditorMetrics.panelHeight(forLines: 2, maxLines: 3)
    let three = EditorMetrics.panelHeight(forLines: 3, maxLines: 3)
    #expect(one < two)
    #expect(two < three)
  }

  @Test("panelHeight clamps at the supplied maxLines")
  func panelHeightClamps() {
    let three = EditorMetrics.panelHeight(forLines: 3, maxLines: 3)
    let seven = EditorMetrics.panelHeight(forLines: 7, maxLines: 3)
    let hundred = EditorMetrics.panelHeight(forLines: 100, maxLines: 3)
    #expect(three == seven)
    #expect(three == hundred)
  }

  @Test("panelHeight grows with a larger maxLines")
  func panelHeightHonoursLargerMax() {
    let capped = EditorMetrics.panelHeight(forLines: 10, maxLines: 3)
    let expanded = EditorMetrics.panelHeight(forLines: 10, maxLines: 10)
    let wayBigger = EditorMetrics.panelHeight(forLines: 10, maxLines: 30)
    #expect(expanded > capped)
    #expect(wayBigger == expanded, "row-count hits the ceiling at 10 when maxLines >= 10")
  }

  @Test("panelHeight treats zero and negative line counts as one line")
  func panelHeightFloor() {
    let one = EditorMetrics.panelHeight(forLines: 1, maxLines: 3)
    #expect(EditorMetrics.panelHeight(forLines: 0, maxLines: 3) == one)
    #expect(EditorMetrics.panelHeight(forLines: -3, maxLines: 3) == one)
  }

  @Test("panelHeight treats zero maxLines as one line")
  func panelHeightMaxFloor() {
    let one = EditorMetrics.panelHeight(forLines: 5, maxLines: 1)
    #expect(EditorMetrics.panelHeight(forLines: 5, maxLines: 0) == one)
    #expect(EditorMetrics.panelHeight(forLines: 5, maxLines: -7) == one)
  }
}
