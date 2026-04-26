import SwiftUI

/// Inline find-in-note strip rendered above the editor card while
/// `FindController.isVisible` is true. Captures focus on appear, runs
/// the search live as the user types, and reports the current/total
/// match count alongside step-prev/step-next/close affordances.
struct FindBar: View {
  @ObservedObject var controller: FindController
  let theme: Theme
  let editorText: String

  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(theme.placeholder)

      TextField(
        "Find in note",
        text: Binding(
          get: { controller.query },
          set: {
            controller.query = $0
            controller.search(in: editorText)
          }
        )
      )
      .textFieldStyle(.plain)
      .font(.system(size: 12))
      .foregroundStyle(theme.text)
      .focused($focused)
      .onSubmit { controller.next() }
      .onKeyPress(.escape) {
        controller.close()
        return .handled
      }
      .onKeyPress(.upArrow) {
        controller.previous()
        return .handled
      }
      .onKeyPress(.downArrow) {
        controller.next()
        return .handled
      }
      .onKeyPress(.init("w"), phases: .down) { press in
        guard press.modifiers.contains(.control) else { return .ignored }
        controller.query = SearchTextEditing.deleteWordBackward(controller.query)
        controller.search(in: editorText)
        return .handled
      }

      Text(matchLabel)
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(theme.placeholder)
        .frame(minWidth: 36, alignment: .trailing)

      iconButton(systemName: "chevron.up", help: "Previous match (⇧⏎)") {
        controller.previous()
      }
      iconButton(systemName: "chevron.down", help: "Next match (⏎)") {
        controller.next()
      }
      iconButton(systemName: "xmark", help: "Close (Esc)") {
        controller.close()
      }
    }
    .padding(.horizontal, 10)
    .frame(height: EditorMetrics.findBarHeight)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(theme.background)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(theme.border, lineWidth: 1)
    )
    .padding(.horizontal, EditorMetrics.outerPadding)
    .onAppear {
      focused = true
      if !controller.query.isEmpty { controller.search(in: editorText) }
    }
  }

  private var matchLabel: String {
    if controller.query.isEmpty { return "" }
    if controller.matches.isEmpty { return "0/0" }
    return "\(controller.currentIndex + 1)/\(controller.matches.count)"
  }

  private func iconButton(
    systemName: String,
    help: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(theme.text.opacity(0.7))
        .padding(4)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}
