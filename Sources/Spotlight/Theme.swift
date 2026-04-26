import SwiftUI

/// Visual skin applied to the HUD panel.
public struct Theme: Equatable, Identifiable, Sendable {
  public enum Mode: String, Codable, Sendable { case light, dark }

  public let id: String
  let name: String
  let mode: Mode
  let background: Color
  let border: Color
  let text: Color
  let placeholder: Color
}

/// Ten curated themes -- five dark, five light.
enum ThemeCatalog {
  // MARK: Dark

  static let obsidian = Theme(
    id: "obsidian",
    name: "Obsidian",
    mode: .dark,
    background: Color(red: 0.055, green: 0.055, blue: 0.065),
    border: Color.white.opacity(0.06),
    text: Color(red: 0.910, green: 0.910, blue: 0.929),
    placeholder: Color(red: 0.604, green: 0.604, blue: 0.627)
  )

  static let ink = Theme(
    id: "ink",
    name: "Ink",
    mode: .dark,
    background: Color(red: 0.071, green: 0.078, blue: 0.102),
    border: Color(red: 0.290, green: 0.333, blue: 0.408).opacity(0.25),
    text: Color(red: 0.886, green: 0.910, blue: 0.941),
    placeholder: Color(red: 0.443, green: 0.502, blue: 0.588)
  )

  static let graphite = Theme(
    id: "graphite",
    name: "Graphite",
    mode: .dark,
    background: Color(red: 0.102, green: 0.102, blue: 0.102),
    border: Color.white.opacity(0.10),
    text: Color(red: 0.831, green: 0.831, blue: 0.831),
    placeholder: Color(red: 0.502, green: 0.502, blue: 0.502)
  )

  static let midnight = Theme(
    id: "midnight",
    name: "Midnight",
    mode: .dark,
    background: Color(red: 0.059, green: 0.078, blue: 0.098),
    border: Color(red: 0.118, green: 0.165, blue: 0.220).opacity(0.80),
    text: Color(red: 0.839, green: 0.871, blue: 0.922),
    placeholder: Color(red: 0.373, green: 0.494, blue: 0.592)
  )

  static let charcoal = Theme(
    id: "charcoal",
    name: "Charcoal",
    mode: .dark,
    background: Color(red: 0.110, green: 0.110, blue: 0.118),
    border: Color.white.opacity(0.08),
    text: Color(red: 0.922, green: 0.922, blue: 0.941),
    placeholder: Color(red: 0.557, green: 0.557, blue: 0.576)
  )

  // MARK: Light

  static let parchment = Theme(
    id: "parchment",
    name: "Parchment",
    mode: .light,
    background: Color(red: 0.969, green: 0.961, blue: 0.937),
    border: Color.black.opacity(0.08),
    text: Color(red: 0.165, green: 0.165, blue: 0.165),
    placeholder: Color(red: 0.557, green: 0.541, blue: 0.510)
  )

  static let mist = Theme(
    id: "mist",
    name: "Mist",
    mode: .light,
    background: Color(red: 0.965, green: 0.969, blue: 0.976),
    border: Color.black.opacity(0.06),
    text: Color(red: 0.122, green: 0.161, blue: 0.216),
    placeholder: Color(red: 0.612, green: 0.639, blue: 0.686)
  )

  static let bone = Theme(
    id: "bone",
    name: "Bone",
    mode: .light,
    background: Color(red: 0.980, green: 0.980, blue: 0.973),
    border: Color.black.opacity(0.05),
    text: Color(red: 0.149, green: 0.149, blue: 0.149),
    placeholder: Color(red: 0.549, green: 0.549, blue: 0.549)
  )

  static let linen = Theme(
    id: "linen",
    name: "Linen",
    mode: .light,
    background: Color(red: 0.961, green: 0.941, blue: 0.910),
    border: Color.black.opacity(0.07),
    text: Color(red: 0.239, green: 0.184, blue: 0.122),
    placeholder: Color(red: 0.612, green: 0.557, blue: 0.478)
  )

  static let porcelain = Theme(
    id: "porcelain",
    name: "Porcelain",
    mode: .light,
    background: Color.white,
    border: Color.black.opacity(0.07),
    text: Color(red: 0.102, green: 0.102, blue: 0.102),
    placeholder: Color(red: 0.557, green: 0.557, blue: 0.576)
  )

  static let darkThemes: [Theme] = [obsidian, ink, graphite, midnight, charcoal]
  static let lightThemes: [Theme] = [parchment, mist, bone, linen, porcelain]
  static let all: [Theme] = darkThemes + lightThemes

  /// Default theme applied on first launch.
  static let defaultID = obsidian.id

  /// Looks up a theme by id, falling back to the default.
  static func theme(withID id: String) -> Theme {
    all.first { $0.id == id } ?? obsidian
  }
}
