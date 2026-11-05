import Foundation
import Testing

@testable import Spotlight

@Suite("MathSuggester unit conversion")
struct MathConversionTests {
  @Test(
    "length conversions",
    arguments: [
      ("5 km in mi", "3.106856 mi"),
      ("1 mi to km", "1.609344 km"),
      ("12 in in ft", "1 ft"),
      ("3 ft to in", "36 in"),
      ("100 cm in m", "1 m"),
      ("1 yd in cm", "91.44 cm"),
      ("5m in ft", "16.404199 ft"),
      ("2.5 km to m", "2500 m"),
      ("1 mm in mi", "0.000000621371 mi"),
      ("10 meters in feet", "32.808399 feet")
    ]
  )
  func length(line: String, expected: String) {
    #expect(MathSuggester.suggestionForLine(line)?.answer == expected)
  }

  @Test(
    "mass conversions",
    arguments: [
      ("1 kg in lb", "2.204623 lb"),
      ("16 oz to lb", "1 lb"),
      ("500 g in kg", "0.5 kg"),
      ("2 lbs in g", "907.18474 g")
    ]
  )
  func mass(line: String, expected: String) {
    #expect(MathSuggester.suggestionForLine(line)?.answer == expected)
  }

  @Test(
    "time conversions, including compound quantities",
    arguments: [
      ("90 min in h", "1.5 h"),
      ("2 hr to min", "120 min"),
      ("1 day in s", "86400 s"),
      ("1 week in day", "7 day"),
      ("1500 ms to sec", "1.5 sec"),
      ("3h 20m in min", "200 min"),
      ("3h 20min in min", "200 min"),
      ("1h 30m 15s in s", "5415 s"),
      ("90m in h", "1.5 h")
    ]
  )
  func time(line: String, expected: String) {
    #expect(MathSuggester.suggestionForLine(line)?.answer == expected)
  }

  @Test(
    "data conversions use decimal KB..TB and binary KiB..TiB",
    arguments: [
      ("2.5 GB to MB", "2500 MB"),
      ("1 GiB in MB", "1073.741824 MB"),
      ("1024 KiB to MiB", "1 MiB"),
      ("1 TB in GB", "1000 GB"),
      ("4096 B in KiB", "4 KiB"),
      ("1 tb in gb", "1000 gb")
    ]
  )
  func data(line: String, expected: String) {
    #expect(MathSuggester.suggestionForLine(line)?.answer == expected)
  }

  @Test(
    "temperature conversions",
    arguments: [
      ("100 F in C", "37.777778 C"),
      ("32 F to C", "0 C"),
      ("100 C in F", "212 F"),
      ("-40 C in F", "-40 F"),
      ("0 C in K", "273.15 K"),
      ("300 K to C", "26.85 C"),
      ("98.6 °F in °C", "37 °C")
    ]
  )
  func temperature(line: String, expected: String) {
    #expect(MathSuggester.suggestionForLine(line)?.answer == expected)
  }

  @Test("the consumed count covers only the conversion, not preceding prose")
  func consumedCount() throws {
    let result = try #require(MathSuggester.suggestionForLine("trip: 5 km in mi"))
    #expect(result.consumed == 10)
  }

  @Test("conversion is found at the cursor's line in a multiline note")
  func multilineConversion() {
    let text = "notes\n2 GB to MB"
    let result = MathSuggester.suggestion(text: text, cursorOffset: (text as NSString).length)
    #expect(result?.answer == "2000 MB")
  }

  @Test(
    "mismatched, unknown, or incomplete conversions produce no suggestion",
    arguments: [
      "5 kg in mi",
      "5 km in",
      "km in mi",
      "5 parsecs in km",
      "5 km in lightyears",
      "abc5 km in mi",
      "5 km into mi"
    ]
  )
  func invalidConversions(line: String) {
    #expect(MathSuggester.suggestionForLine(line) == nil)
  }

  @Test(
    "prose using 'in' or 'to' does not trigger",
    arguments: [
      "I live 5 km in town",
      "go to bed",
      "add 2 cups to bowl",
      "from 5 to 10",
      "meet in 5 min",
      "talk to me in 5"
    ]
  )
  func proseRejected(line: String) {
    #expect(MathSuggester.suggestionForLine(line) == nil)
  }

  @Test("unit names resolve case-insensitively and 'm' is metre or minute")
  func unitLookup() {
    #expect(MathUnit.units(named: "KM").map(\.dimension) == [.length])
    #expect(MathUnit.units(named: "m").map(\.dimension) == [.length, .time])
    #expect(MathUnit.units(named: "parsec").isEmpty)
  }
}
