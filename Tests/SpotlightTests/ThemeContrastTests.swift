import AppKit
import SwiftUI
import Testing

@testable import Spotlight

@Suite("Theme contrast")
@MainActor
struct ThemeContrastTests {
  /// WCAG 2.x relative luminance of an opaque colour in sRGB.
  private static func luminance(_ color: NSColor) -> Double {
    guard let rgb = color.usingColorSpace(.sRGB) else {
      Issue.record("colour could not be converted to sRGB")
      return 0
    }
    func channel(_ value: CGFloat) -> Double {
      let encoded = Double(value)
      return encoded <= 0.040_45 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent)
      + 0.0722 * channel(rgb.blueComponent)
  }

  private static func contrast(_ lhs: NSColor, _ rhs: NSColor) -> Double {
    let first = luminance(lhs)
    let second = luminance(rhs)
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)
  }

  @Test("text on background meets WCAG AAA (7:1)", arguments: ThemeCatalog.all)
  func textContrast(theme: Theme) {
    let ratio = Self.contrast(NSColor(theme.text), NSColor(theme.background))
    #expect(ratio >= 7, "\(theme.name) text contrast is \(ratio)")
  }

  @Test("placeholder on background is at least 3:1", arguments: ThemeCatalog.all)
  func placeholderContrast(theme: Theme) {
    let ratio = Self.contrast(NSColor(theme.placeholder), NSColor(theme.background))
    #expect(ratio >= 3, "\(theme.name) placeholder contrast is \(ratio)")
  }

  @Test("default tag colour on background is at least 3:1", arguments: ThemeCatalog.all)
  func tagContrast(theme: Theme) {
    let tag = TagStyler.colors(for: nil, mode: theme.mode).foreground
    let ratio = Self.contrast(tag, NSColor(theme.background))
    #expect(ratio >= 3, "\(theme.name) tag contrast is \(ratio)")
  }
}
