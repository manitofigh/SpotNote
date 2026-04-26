import SwiftUI

/// Small "physical" key cap modeled on Flowbite's `kbd` styling, with an
/// extra 1.5pt lip below the face so the chiclet shape stays legible at
/// the tutorial bar's small font size.
///
/// `accent == .red` paints the cap in the Tailwind `red-50 / red-700 /
/// red-600/10` palette (dark-mode analogue uses `red-950 / red-300 /
/// red-500/20`), which is how destructive chords like delete are marked.
struct KeyCap: View {
  enum Accent { case red }
  enum Size { case regular, compact }

  let label: String
  let theme: Theme
  var accent: Accent?
  var size: Size = .regular

  init(_ label: String, theme: Theme, accent: Accent? = nil, size: Size = .regular) {
    self.label = label
    self.theme = theme
    self.accent = accent
    self.size = size
  }

  var body: some View {
    let isDark = theme.mode == .dark
    let palette = Palette(accent: accent, isDark: isDark, theme: theme)
    let metrics = Metrics(size: size)

    ZStack {
      RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
        .fill(palette.side)
        .padding(.top, metrics.lip)
      RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
        .fill(palette.face)
        .padding(.bottom, metrics.lip)
      RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
        .strokeBorder(palette.stroke, lineWidth: 0.8)
        .padding(.bottom, metrics.lip)
      Text(label)
        .font(.system(size: metrics.fontSize, weight: .semibold, design: .rounded))
        .foregroundStyle(palette.text)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.bottom, metrics.lip)
    }
    .frame(minWidth: metrics.minWidth, minHeight: metrics.minHeight)
    .fixedSize()
  }

  private struct Metrics {
    let corner: CGFloat
    let fontSize: CGFloat
    let horizontalPadding: CGFloat
    let minWidth: CGFloat
    let minHeight: CGFloat
    let lip: CGFloat

    init(size: Size) {
      switch size {
      case .regular:
        self.corner = 4
        self.fontSize = 9.5
        self.horizontalPadding = 4
        self.minWidth = 18
        self.minHeight = 18
        self.lip = 1.5
      case .compact:
        self.corner = 4
        self.fontSize = 9.5
        self.horizontalPadding = 3.5
        self.minWidth = 17
        self.minHeight = 17
        self.lip = 1.3
      }
    }
  }

  /// All fill/stroke/text colors for the cap, resolved up-front so the
  /// `body` stays trivial and the accent/dark-mode branching is in one
  /// place.
  private struct Palette {
    let face: LinearGradient
    let side: Color
    let stroke: Color
    let text: Color

    init(face: LinearGradient, side: Color, stroke: Color, text: Color) {
      self.face = face
      self.side = side
      self.stroke = stroke
      self.text = text
    }

    init(accent: Accent?, isDark: Bool, theme: Theme) {
      if accent == .red {
        self = Self.red(isDark: isDark)
      } else {
        self = Self.neutral(isDark: isDark, theme: theme)
      }
    }

    /// Tailwind palette: light = bg red-50 -> red-100, ring red-600/10,
    /// text red-700; dark = bg red-950, ring red-500/20, text red-300.
    private static func red(isDark: Bool) -> Palette {
      if isDark {
        let top = Color(red: 0.271, green: 0.039, blue: 0.039)
        let bottom = Color(red: 0.180, green: 0.020, blue: 0.020)
        let red500 = Color(red: 0.937, green: 0.267, blue: 0.267)
        return Palette(
          face: LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom),
          side: red500.opacity(0.40),
          stroke: red500.opacity(0.20),
          text: Color(red: 0.988, green: 0.647, blue: 0.647)
        )
      }
      let top = Color(red: 0.996, green: 0.949, blue: 0.949)
      let bottom = Color(red: 0.996, green: 0.886, blue: 0.886)
      let red600 = Color(red: 0.863, green: 0.149, blue: 0.149)
      return Palette(
        face: LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom),
        side: red600.opacity(0.20),
        stroke: red600.opacity(0.10),
        text: Color(red: 0.725, green: 0.110, blue: 0.110)
      )
    }

    private static func neutral(isDark: Bool, theme: Theme) -> Palette {
      if isDark {
        return Palette(
          face: LinearGradient(
            colors: [Color.white.opacity(0.22), Color.white.opacity(0.10)],
            startPoint: .top,
            endPoint: .bottom
          ),
          side: Color.black.opacity(0.65),
          stroke: Color.white.opacity(0.22),
          text: theme.text.opacity(0.95)
        )
      }
      return Palette(
        face: LinearGradient(
          colors: [Color.white, Color(white: 0.92)],
          startPoint: .top,
          endPoint: .bottom
        ),
        side: Color.black.opacity(0.22),
        stroke: Color.black.opacity(0.20),
        text: theme.text.opacity(0.85)
      )
    }
  }
}

extension KeyCap {
  /// Splits a chord like "⌘⇧Space" into ["⌘", "⇧", "Space"]. Non-ASCII
  /// glyphs (modifier symbols) are always their own cap; consecutive
  /// ASCII characters group into one cap (so "Space", "N", ",", "/"
  /// stay intact).
  static func split(chord: String) -> [String] {
    var keys: [String] = []
    var current = ""
    for ch in chord {
      if ch.isASCII {
        current.append(ch)
      } else {
        if !current.isEmpty {
          keys.append(current)
          current = ""
        }
        keys.append(String(ch))
      }
    }
    if !current.isEmpty { keys.append(current) }
    return keys
  }

  /// Convenience: renders a full chord string ("⌘⇧Space") as a
  /// horizontal row of small caps.
  @ViewBuilder
  static func row(
    for chord: String,
    theme: Theme,
    accent: Accent? = nil,
    size: Size = .regular
  ) -> some View {
    HStack(spacing: 2) {
      ForEach(Array(split(chord: chord).enumerated()), id: \.offset) { _, key in
        KeyCap(key, theme: theme, accent: accent, size: size)
      }
    }
  }
}
