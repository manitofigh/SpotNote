import Foundation
import Testing

@testable import Spotlight

@Suite("TagParser")
struct TagParserTests {
  @Test(
    "extracts tag names from note text",
    arguments: [
      ("#work", ["work"]),
      ("todo #work today", ["work"]),
      ("line one\n#start of line", ["start"]),
      ("#proj/alpha and #proj/beta", ["proj/alpha", "proj/beta"]),
      ("unicode #café #日本語 #Ünï", ["café", "日本語", "ünï"]),
      ("mixed case #Work #WORK", ["work", "work"]),
      ("#2024-plan #v2 #snake_case", ["2024-plan", "v2", "snake_case"]),
      ("trailing punctuation #done. #next, #end!", ["done", "next", "end"]),
      ("trailing separators #work/ #dash-", ["work", "dash"]),
      ("(#paren) [#bracket] \"#quoted\"", ["paren", "bracket", "quoted"])
    ]
  )
  func extractsTags(text: String, expected: [String]) {
    #expect(TagParser.matches(in: text).map(\.name) == expected)
  }

  @Test(
    "ignores text that is not a tag",
    arguments: [
      "# heading",
      "## heading",
      "##double",
      "#123 issue ref",
      "#1-2/3",
      "see https://example.com/page#section",
      "see https://example.com/#top",
      "query ?a=1&#frag",
      "mid#word",
      "inline `#notatag` code",
      "```\n#insidefence\n```",
      "```swift\nlet x = 1 // #comment\n```",
      "#",
      "# "
    ]
  )
  func ignoresNonTags(text: String) {
    #expect(TagParser.matches(in: text).isEmpty)
  }

  @Test("match ranges are UTF-16 ranges covering the hash and body")
  func rangesAreUTF16() {
    let text = "😀 #tag"
    let match = TagParser.matches(in: text).first
    #expect(match?.range == NSRange(location: 3, length: 4))
    #expect((text as NSString).substring(with: match?.range ?? NSRange()) == "#tag")
  }

  @Test("tags outside code spans are still found next to code")
  func tagsBesideCode() {
    let text = "`#code` #real\n```\n#fenced\n```\n#after"
    #expect(TagParser.matches(in: text).map(\.name) == ["real", "after"])
  }

  @Test("tag set is unique and case-insensitive")
  func uniqueSet() {
    #expect(TagParser.tags(in: "#A #a #b") == ["a", "b"])
  }
}
