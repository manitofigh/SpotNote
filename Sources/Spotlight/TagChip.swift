import SwiftUI

/// Small tinted `#tag` pill used in the fuzzy palette, coloured like the
/// tag is in the editor (see `TagStyler`).
struct TagChip: View {
  let name: String
  let mode: Theme.Mode

  var body: some View {
    let colors = TagStyler.colors(for: TagColorStore.shared.color(for: name), mode: mode)
    Text("#\(name)")
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(Color(nsColor: colors.foreground))
      .lineLimit(1)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(Capsule().fill(Color(nsColor: colors.background)))
      .fixedSize()
  }

  /// Paints every `#tag` in `attributed` with its editor colours, so tags
  /// stand out in the palette preview too.
  /// - Complexity: O(n) in the text length.
  @MainActor
  static func colorTags(in attributed: inout AttributedString, text: String, mode: Theme.Mode) {
    for match in TagParser.matches(in: text) {
      guard let range = Range(match.range, in: text), let target = Range(range, in: attributed) else { continue }
      let colors = TagStyler.colors(for: TagColorStore.shared.color(for: match.name), mode: mode)
      attributed[target].foregroundColor = Color(nsColor: colors.foreground)
      attributed[target].backgroundColor = Color(nsColor: colors.background)
    }
  }
}
