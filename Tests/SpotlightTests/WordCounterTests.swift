import Testing

@testable import Spotlight

@Suite("WordCounter")
struct WordCounterTests {
  @Test("empty and whitespace-only text has no words")
  func emptyAndWhitespace() {
    #expect(WordCounter.count(in: "") == 0)
    #expect(WordCounter.count(in: " \n\t\n  ") == 0)
  }

  @Test("spaces and newlines separate words without counting themselves")
  func whitespaceSeparatesWords() {
    #expect(WordCounter.count(in: "one  two\nthree\t four") == 4)
  }

  @Test("attached punctuation stays inside one word")
  func attachedPunctuation() {
    #expect(WordCounter.count(in: "hello,world well-being don't https://example.com") == 4)
  }

  @Test("numbers and Unicode letters count as words")
  func numbersAndUnicodeLetters() {
    #expect(WordCounter.count(in: "42 3.14 déjà 東京") == 4)
  }

  @Test("standalone punctuation and emoji do not count as words")
  func symbolsDoNotCount() {
    #expect(WordCounter.count(in: "— … 🙂 !!!") == 0)
    #expect(WordCounter.count(in: "word 🙂") == 1)
  }
}
