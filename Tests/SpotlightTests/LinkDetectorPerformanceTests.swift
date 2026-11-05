import Foundation
import XCTest

@testable import Spotlight

/// Timing baselines for link detection on a large note (~10k lines,
/// ~900 KB). The incremental case models a keystroke: one line changed,
/// every other line served from `LinkLineCache`.
@MainActor
final class LinkDetectorPerformanceTests: XCTestCase {
  private let document: String = {
    // Unique lines so the cold pass can't dedupe identical ones.
    (0..<5_000).map { "todo \($0) with https://example.com/\($0) and me@example.org\nplain prose line \($0)\n" }
      .joined()
  }()

  func testColdScanOfLargeNote() {
    let text = document as NSString
    measure {
      var cache = LinkLineCache()
      _ = LinkDetector.spans(in: text, cache: &cache)
    }
  }

  func testIncrementalScanAfterSingleLineEdit() {
    var cache = LinkLineCache()
    _ = LinkDetector.spans(in: document as NSString, cache: &cache)
    var edit = 0
    measure {
      edit += 1
      let edited = "edited line \(edit) www.apple.com\n" + document
      _ = LinkDetector.spans(in: edited as NSString, cache: &cache)
    }
  }
}
