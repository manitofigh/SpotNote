import SwiftUI

/// Tinted themes with a clear hue of their own, so they read as visibly
/// different from the neutral originals. Every background keeps text at
/// >= 7:1 and placeholder at >= 3:1 (WCAG relative luminance), and leaves
/// enough headroom for the mode-fixed link, tag, and code colours.
extension ThemeCatalog {
  // MARK: Dark

  /// Cold slate-blue, like deep water under an overcast sky.
  static let fjord = Theme(
    id: "fjord",
    name: "Fjord",
    mode: .dark,
    background: Color(red: 0.106, green: 0.149, blue: 0.220),
    border: Color(red: 0.298, green: 0.416, blue: 0.580).opacity(0.45),
    text: Color(red: 0.890, green: 0.918, blue: 0.957),
    placeholder: Color(red: 0.541, green: 0.612, blue: 0.722)
  )

  /// Warm roasted brown with cream text.
  static let espresso = Theme(
    id: "espresso",
    name: "Espresso",
    mode: .dark,
    background: Color(red: 0.141, green: 0.102, blue: 0.078),
    border: Color(red: 0.420, green: 0.290, blue: 0.200).opacity(0.60),
    text: Color(red: 0.949, green: 0.902, blue: 0.847),
    placeholder: Color(red: 0.659, green: 0.569, blue: 0.478)
  )

  /// Deep forest green with a pale mint foreground.
  static let evergreen = Theme(
    id: "evergreen",
    name: "Evergreen",
    mode: .dark,
    background: Color(red: 0.075, green: 0.133, blue: 0.102),
    border: Color(red: 0.243, green: 0.420, blue: 0.310).opacity(0.55),
    text: Color(red: 0.863, green: 0.937, blue: 0.882),
    placeholder: Color(red: 0.498, green: 0.639, blue: 0.545)
  )

  /// Twilight violet with lavender text.
  static let dusk = Theme(
    id: "dusk",
    name: "Dusk",
    mode: .dark,
    background: Color(red: 0.118, green: 0.098, blue: 0.188),
    border: Color(red: 0.416, green: 0.333, blue: 0.627).opacity(0.50),
    text: Color(red: 0.925, green: 0.898, blue: 0.980),
    placeholder: Color(red: 0.612, green: 0.561, blue: 0.749)
  )

  /// True black, pure white text, vivid cyan accent.
  static let eclipse = Theme(
    id: "eclipse",
    name: "Eclipse",
    mode: .dark,
    background: Color.black,
    border: Color(red: 0.184, green: 0.851, blue: 0.812).opacity(0.45),
    text: Color.white,
    placeholder: Color(red: 0.184, green: 0.851, blue: 0.812)
  )

  // MARK: Light

  /// Aged warm paper with brown ink.
  static let sepia = Theme(
    id: "sepia",
    name: "Sepia",
    mode: .light,
    background: Color(red: 0.949, green: 0.910, blue: 0.824),
    border: Color(red: 0.498, green: 0.396, blue: 0.282).opacity(0.25),
    text: Color(red: 0.227, green: 0.157, blue: 0.090),
    placeholder: Color(red: 0.498, green: 0.396, blue: 0.282)
  )

  /// Cool ice-blue wash with navy text.
  static let glacier = Theme(
    id: "glacier",
    name: "Glacier",
    mode: .light,
    background: Color(red: 0.898, green: 0.933, blue: 0.976),
    border: Color(red: 0.239, green: 0.435, blue: 0.690).opacity(0.25),
    text: Color(red: 0.063, green: 0.137, blue: 0.239),
    placeholder: Color(red: 0.337, green: 0.439, blue: 0.561)
  )

  /// Soft mint-sage with deep green text.
  static let sage = Theme(
    id: "sage",
    name: "Sage",
    mode: .light,
    background: Color(red: 0.886, green: 0.941, blue: 0.898),
    border: Color(red: 0.247, green: 0.478, blue: 0.322).opacity(0.25),
    text: Color(red: 0.078, green: 0.188, blue: 0.118),
    placeholder: Color(red: 0.333, green: 0.478, blue: 0.376)
  )

  /// Pale rose with dark plum text.
  static let blush = Theme(
    id: "blush",
    name: "Blush",
    mode: .light,
    background: Color(red: 0.976, green: 0.898, blue: 0.918),
    border: Color(red: 0.710, green: 0.337, blue: 0.431).opacity(0.25),
    text: Color(red: 0.243, green: 0.094, blue: 0.137),
    placeholder: Color(red: 0.557, green: 0.353, blue: 0.404)
  )

  /// Pure white, pure black text, electric-blue accent.
  static let lumen = Theme(
    id: "lumen",
    name: "Lumen",
    mode: .light,
    background: Color.white,
    border: Color(red: 0.208, green: 0.329, blue: 0.820).opacity(0.45),
    text: Color.black,
    placeholder: Color(red: 0.208, green: 0.329, blue: 0.820)
  )
}
