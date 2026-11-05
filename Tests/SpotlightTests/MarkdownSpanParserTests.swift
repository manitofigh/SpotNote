import Foundation
import Testing

@testable import Spotlight

@Suite("MarkdownSpanParser")
struct MarkdownSpanParserTests {
  private func spans(_ text: String) -> [MarkdownSpan] {
    MarkdownSpanParser.spans(in: text as NSString)
  }

  private func substring(_ text: String, _ range: NSRange) -> String {
    (text as NSString).substring(with: range)
  }

  @Test("heading hides the hashes and following space", arguments: [1, 2, 3, 6])
  func heading(level: Int) throws {
    let text = String(repeating: "#", count: level) + " Title"
    let span = try #require(spans(text).first)
    #expect(span.kind == .heading(level: level))
    #expect(substring(text, span.content) == "Title")
    #expect(span.markers == [NSRange(location: 0, length: level + 1)])
  }

  @Test(
    "hash followed by a non-space character is a tag, not a heading",
    arguments: ["#tag", "##tag", "#", "####### seven"]
  )
  func tagIsNotHeading(text: String) {
    #expect(spans(text).isEmpty)
  }

  @Test("bold content is styled and both delimiters are hidden", arguments: ["**", "__"])
  func bold(delimiter: String) throws {
    let text = "a \(delimiter)strong\(delimiter) b"
    let span = try #require(spans(text).first)
    #expect(span.kind == .bold)
    #expect(substring(text, span.content) == "strong")
    #expect(span.markers == [NSRange(location: 2, length: 2), NSRange(location: 10, length: 2)])
  }

  @Test("italic accepts star and underscore delimiters", arguments: ["*", "_"])
  func italic(delimiter: String) throws {
    let text = "\(delimiter)soft\(delimiter)"
    let span = try #require(spans(text).first)
    #expect(span.kind == .italic)
    #expect(substring(text, span.content) == "soft")
  }

  @Test(
    "intraword and spaced delimiters stay literal",
    arguments: ["2*3*4", "snake_case_name", "a * b * c", "** x **"]
  )
  func conservativeEmphasis(text: String) {
    #expect(spans(text).isEmpty)
  }

  @Test("bold is not also parsed as italic")
  func boldIsNotItalic() {
    #expect(spans("**x**").map(\.kind) == [.bold])
  }

  @Test("strikethrough hides tildes")
  func strikethrough() throws {
    let span = try #require(spans("~~gone~~").first)
    #expect(span.kind == .strikethrough)
    #expect(span.content == NSRange(location: 2, length: 4))
  }

  @Test("link styles the label and hides bracket and URL syntax")
  func link() throws {
    let text = "see [docs](https://x.io/a) now"
    let span = try #require(spans(text).first)
    #expect(span.kind == .link(url: "https://x.io/a"))
    #expect(substring(text, span.content) == "docs")
    #expect(span.markers.map { substring(text, $0) } == ["[", "](https://x.io/a)"])
  }

  @Test("emphasis characters inside a link URL are not parsed")
  func urlIsClaimed() {
    #expect(spans("[a](http://x/*y*)").map(\.kind) == [.link(url: "http://x/*y*")])
  }

  @Test("image syntax is not treated as a link")
  func imageIgnored() {
    #expect(spans("![alt](pic.png)").isEmpty)
  }

  @Test("blockquote tints the marker and styles the body without hiding")
  func blockquote() {
    let result = spans("> quoted")
    #expect(result.map(\.kind) == [.blockMarker, .blockquote])
    #expect(result.allSatisfy { $0.markers.isEmpty })
  }

  @Test("list bullets are tinted, never hidden", arguments: ["- item", "* item", "+ item", "1. item", "  - nested"])
  func listBullet(text: String) throws {
    let span = try #require(spans(text).first)
    #expect(span.kind == .blockMarker)
    #expect(span.markers.isEmpty)
  }

  @Test("nothing inside inline code is styled")
  func inlineCodeExcluded() {
    #expect(spans("`**not bold**`").isEmpty)
  }

  @Test("nothing inside a fenced block is styled, including headings")
  func fenceExcluded() {
    let text = "```\n# not heading\n**not bold**\n```\n**bold**"
    #expect(spans(text).map(\.kind) == [.bold])
  }

  @Test("checklist markers are never part of a hidden range")
  func checklistUntouched() {
    let text = "☐ **task**"
    let markers = spans(text).flatMap(\.markers)
    #expect(markers.allSatisfy { !substring(text, $0).contains("☐") })
  }

  @Test("spans are reported in document order across lines")
  func sorted() {
    let result = spans("# H\n*i* and **b**")
    #expect(result.map(\.kind) == [.heading(level: 1), .italic, .bold])
  }
}

@Suite("Markdown preview helpers")
struct MarkdownPreviewHelperTests {
  @Test("scheme-less link targets resolve to https")
  func schemeLess() {
    #expect(MarkdownPreviewState.resolvedURL("example.com/a")?.absoluteString == "https://example.com/a")
    #expect(MarkdownPreviewState.resolvedURL("mailto:a@b.c")?.scheme == "mailto")
  }

  @Test("link lookup returns the URL only inside the label")
  func linkLookup() {
    var state = MarkdownPreviewState()
    state.links = [.init(label: NSRange(location: 1, length: 4), url: "https://a.b")]
    #expect(state.linkURL(at: 2)?.host == "a.b")
    #expect(state.linkURL(at: 5) == nil)
  }

  @Test("edits shift marker indices and drop replaced ones")
  func shiftOnEdit() {
    var visibility = MarkdownGlyphVisibility()
    visibility.markers = IndexSet([0, 1, 10, 11])
    visibility.hidden = IndexSet([10, 11])
    // Insert 3 characters at 5.
    visibility.shift(editedRange: NSRange(location: 5, length: 3), delta: 3)
    #expect(visibility.markers == IndexSet([0, 1, 13, 14]))
    #expect(visibility.hidden == IndexSet([13, 14]))
    // Delete the 2 characters at 0..<2.
    visibility.shift(editedRange: NSRange(location: 0, length: 0), delta: -2)
    #expect(visibility.markers == IndexSet([11, 12]))
  }
}
