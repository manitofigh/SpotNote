import AppKit

/// Named tag colours offered in the tag menu. Each has a light-theme
/// and a dark-theme variant tuned for legibility on the HUD themes in
/// `ThemeCatalog`. The raw value is the persisted id.
enum TagColor: String, CaseIterable, Sendable {
  case red, orange, yellow, green, teal, blue, purple, pink

  var title: String { rawValue.capitalized }

  func foreground(for mode: Theme.Mode) -> NSColor {
    let rgb = mode == .dark ? darkRGB : lightRGB
    return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
  }

  private struct RGB {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
      self.red = red
      self.green = green
      self.blue = blue
    }
  }

  private var darkRGB: RGB {
    switch self {
    case .red: return RGB(1.00, 0.47, 0.45)
    case .orange: return RGB(1.00, 0.63, 0.32)
    case .yellow: return RGB(0.95, 0.82, 0.35)
    case .green: return RGB(0.48, 0.84, 0.52)
    case .teal: return RGB(0.38, 0.82, 0.82)
    case .blue: return RGB(0.48, 0.67, 1.00)
    case .purple: return RGB(0.74, 0.58, 1.00)
    case .pink: return RGB(1.00, 0.52, 0.76)
    }
  }

  private var lightRGB: RGB {
    switch self {
    case .red: return RGB(0.78, 0.14, 0.14)
    case .orange: return RGB(0.78, 0.38, 0.00)
    case .yellow: return RGB(0.58, 0.45, 0.00)
    case .green: return RGB(0.10, 0.52, 0.22)
    case .teal: return RGB(0.00, 0.48, 0.50)
    case .blue: return RGB(0.10, 0.36, 0.82)
    case .purple: return RGB(0.47, 0.24, 0.78)
    case .pink: return RGB(0.78, 0.14, 0.48)
    }
  }
}

/// Global tag-name -> colour assignments, persisted as one small
/// `[String: String]` dictionary in `UserDefaults`. Tag names are
/// case-insensitive (normalized via `TagParser.normalize`). Tags with no
/// entry use the theme's default tag tint.
@MainActor
final class TagColorStore {
  static let shared = TagColorStore()

  private let defaults: UserDefaults
  private let storageKey: String
  private var assignments: [String: TagColor]

  init(defaults: UserDefaults = .standard, storageKey: String = "tags.colors.v1") {
    self.defaults = defaults
    self.storageKey = storageKey
    let raw = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    self.assignments = raw.compactMapValues(TagColor.init(rawValue:))
  }

  func color(for tag: String) -> TagColor? {
    assignments[TagParser.normalize(tag)]
  }

  /// Assigns `color` to `tag` in every note; `nil` restores the default.
  func setColor(_ color: TagColor?, for tag: String) {
    let key = TagParser.normalize(tag)
    guard assignments[key] != color else { return }
    assignments[key] = color
    defaults.set(assignments.mapValues(\.rawValue), forKey: storageKey)
  }
}
