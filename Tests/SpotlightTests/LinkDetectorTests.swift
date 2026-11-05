import AppKit
import Foundation
import Testing

@testable import Spotlight

@Suite("LinkDetector")
@MainActor
struct LinkDetectorTests {
  private func literals(_ text: String) -> [String] {
    let nsText = text as NSString
    return LinkDetector.spans(in: nsText).map { nsText.substring(with: $0.range) }
  }

  private func kinds(_ text: String) -> [LinkKind] {
    LinkDetector.spans(in: text as NSString).map(\.kind)
  }

  @Test(
    "detects each supported kind",
    arguments: [
      ("see https://example.com/a?b=1 now", "https://example.com/a?b=1", LinkKind.web),
      ("visit www.apple.com today", "www.apple.com", .web),
      ("mail me@example.org please", "me@example.org", .email),
      ("open /usr/bin please", "/usr/bin", .filePath),
      ("notes in ~/Documents/notes.txt here", "~/Documents/notes.txt", .filePath)
    ]
  )
  func detectsKinds(text: String, literal: String, kind: LinkKind) {
    let nsText = text as NSString
    let spans = LinkDetector.spans(in: nsText)
    let match = spans.first { nsText.substring(with: $0.range) == literal }
    #expect(match?.kind == kind)
  }

  @Test("detects an explicit calendar date")
  func detectsDate() {
    #expect(kinds("meeting on March 3, 2027 at the office").contains(.date))
  }

  @Test("strips trailing sentence punctuation from file paths")
  func trimsPathPunctuation() {
    #expect(literals("look in /tmp/build.") == ["/tmp/build"])
  }

  @Test(
    "ignores slash-separated words and comment markers",
    arguments: ["either and/or works", "// just a comment", "ratio 3/4 here", "a lone / slash"]
  )
  func ignoresNonPaths(text: String) {
    #expect(kinds(text).isEmpty)
  }

  @Test("does not report a URL path as a separate file path")
  func urlPathIsNotFilePath() {
    #expect(kinds("go to https://example.com/usr/bin") == [.web])
  }

  @Test("skips links inside inline code spans")
  func skipsInlineCode() {
    #expect(literals("run `curl https://example.com` then visit https://apple.com") == ["https://apple.com"])
  }

  @Test("skips links inside fenced code blocks")
  func skipsFencedCode() {
    let text = "before https://a.com\n```\nlet u = \"https://b.com\"\n```\nafter https://c.com"
    #expect(literals(text) == ["https://a.com", "https://c.com"])
  }

  @Test("reports ranges in document coordinates across lines")
  func documentRanges() {
    let text = "first line\nsecond https://example.com" as NSString
    let span = LinkDetector.spans(in: text).first
    #expect(span?.range == NSRange(location: 18, length: 19))
  }

  @Test("cached pass matches an uncached pass after an edit")
  func cacheMatchesUncached() {
    var cache = LinkLineCache()
    let original = "a https://one.com\nb www.two.com\nc me@x.org" as NSString
    _ = LinkDetector.spans(in: original, cache: &cache)
    let edited = "a https://one.com\nb www.two.com and /usr/bin\nc me@x.org" as NSString
    let cached = LinkDetector.spans(in: edited, cache: &cache)
    #expect(cached == LinkDetector.spans(in: edited))
  }

  @Test("cache holds only the current document's lines")
  func cacheDropsStaleLines() {
    var cache = LinkLineCache()
    _ = LinkDetector.spans(in: "old https://a.com\nkeep" as NSString, cache: &cache)
    _ = LinkDetector.spans(in: "new https://b.com\nkeep" as NSString, cache: &cache)
    #expect(Set(cache.entries.keys) == ["new https://b.com", "keep"])
  }

  @Test("bare www domains resolve to an http URL")
  func resolvesBareDomain() {
    guard case .url(let url) = LinkDetector.target(for: "www.apple.com", kind: .web) else {
      Issue.record("expected a URL target")
      return
    }
    #expect(url.absoluteString == "http://www.apple.com")
  }

  @Test("emails resolve to a mailto URL")
  func resolvesEmail() {
    guard case .url(let url) = LinkDetector.target(for: "me@example.org", kind: .email) else {
      Issue.record("expected a URL target")
      return
    }
    #expect(url.scheme == "mailto")
  }

  @Test("tilde paths expand to the home directory")
  func resolvesTildePath() {
    let target = LinkDetector.target(for: "~/Documents", kind: .filePath)
    let expected = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
    #expect(target == .file(expected))
  }

  @Test("dates resolve to a date target")
  func resolvesDate() {
    guard case .date = LinkDetector.target(for: "March 3, 2027", kind: .date) else {
      Issue.record("expected a date target")
      return
    }
  }

  @Test("large documents are scanned and cached without dropping spans")
  func largeDocument() {
    let block = "todo item with https://example.com/page and more text\nplain prose line here\n"
    let text = String(repeating: block, count: 5_000) as NSString
    var cache = LinkLineCache()
    let cold = LinkDetector.spans(in: text, cache: &cache)
    let warm = LinkDetector.spans(in: text, cache: &cache)
    #expect(cold.count == 5_000)
    #expect(warm == cold)
  }
}

@Suite("LinkStyler")
@MainActor
struct LinkStylerTests {
  private func styledTextView(_ text: String) -> NSTextView {
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    textView.string = text
    restyle(textView)
    return textView
  }

  private func restyle(_ textView: NSTextView) {
    CodeStyler.apply(to: textView, theme: ThemeCatalog.obsidian)
    guard let layoutManager = textView.layoutManager else { return }
    LinkStyler.apply(to: layoutManager, text: textView.string as NSString, theme: ThemeCatalog.obsidian)
  }

  private func linkAttribute(in textView: NSTextView, at index: Int) -> Any? {
    textView.layoutManager?.temporaryAttribute(.spotNoteLink, atCharacterIndex: index, effectiveRange: nil)
  }

  @Test("tags links with the link kind and an underline")
  func tagsLinks() {
    let textView = styledTextView("go https://example.com now")
    #expect(linkAttribute(in: textView, at: 5) as? String == LinkKind.web.rawValue)
    let underline = textView.layoutManager?.temporaryAttribute(
      .underlineStyle,
      atCharacterIndex: 5,
      effectiveRange: nil
    )
    #expect(underline as? Int == NSUnderlineStyle.single.rawValue)
    #expect(linkAttribute(in: textView, at: 0) == nil)
  }

  @Test("removes styling once the link text is gone")
  func clearsStaleStyling() {
    let textView = styledTextView("go https://example.com now")
    textView.string = "go plain words here now"
    restyle(textView)
    #expect(linkAttribute(in: textView, at: 5) == nil)
    let underline = textView.layoutManager?.temporaryAttribute(
      .underlineStyle,
      atCharacterIndex: 5,
      effectiveRange: nil
    )
    #expect(underline == nil)
  }

  @Test("styles only file paths that exist on disk")
  func stylesExistingPathsOnly() {
    let textView = styledTextView("/usr/bin and /definitely/not/here")
    #expect(linkAttribute(in: textView, at: 1) != nil)
    #expect(linkAttribute(in: textView, at: 15) == nil)
  }
}
