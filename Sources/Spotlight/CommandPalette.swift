import SwiftUI

struct CommandPalette: View {
  @ObservedObject var controller: CommandController
  let theme: Theme

  static let reservedHeight: CGFloat = 260

  private static let shape = UnevenRoundedRectangle(
    topLeadingRadius: 0,
    bottomLeadingRadius: 10,
    bottomTrailingRadius: 10,
    topTrailingRadius: 0,
    style: .continuous
  )

  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      searchField
      Divider().background(theme.border).opacity(0.6)
      resultList
    }
    .background(Self.shape.fill(theme.background))
    .overlay(Self.shape.strokeBorder(theme.border, lineWidth: 1))
    .onAppear { focused = true }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "command")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(theme.placeholder)

      TextField(
        "Search settings & shortcuts…",
        text: Binding(
          get: { controller.query },
          set: { controller.setQuery($0) }
        )
      )
      .textFieldStyle(.plain)
      .font(.system(size: 13))
      .foregroundStyle(theme.text)
      .focused($focused)
      .onSubmit {}
      .onKeyPress(.escape) {
        controller.close()
        return .handled
      }
      .onKeyPress(.upArrow) {
        controller.moveSelection(by: -1)
        return .handled
      }
      .onKeyPress(.downArrow) {
        controller.moveSelection(by: +1)
        return .handled
      }
      .onKeyPress(.init("w"), phases: .down) { press in
        guard press.modifiers.contains(.control) else { return .ignored }
        controller.setQuery(SearchTextEditing.deleteWordBackward(controller.query))
        return .handled
      }

      Text(countLabel)
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(theme.placeholder)

      Button(action: controller.close) {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(theme.text.opacity(0.7))
          .padding(4)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Close (Esc)")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private var resultList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          if controller.results.isEmpty {
            emptyState
          } else {
            ForEach(Array(controller.results.enumerated()), id: \.element.id) { index, item in
              row(item, index: index)
                .id(item.id)
            }
          }
        }
        .padding(.vertical, 4)
      }
      .onChange(of: controller.selectedIndex) { _, newIndex in
        if let item = controller.results[safe: newIndex] {
          withAnimation(.easeOut(duration: 0.08)) { proxy.scrollTo(item.id, anchor: .center) }
        }
      }
    }
  }

  private var emptyState: some View {
    Text("No matches")
      .font(.system(size: 11))
      .foregroundStyle(theme.placeholder)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.vertical, 18)
  }

  private func row(_ item: CommandItem, index: Int) -> some View {
    let isSelected = index == controller.selectedIndex
    return HStack(spacing: 8) {
      Image(systemName: item.icon)
        .font(.system(size: 11))
        .foregroundStyle(isSelected ? theme.text : theme.placeholder)
        .frame(width: 14)
      Text(item.title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(isSelected ? theme.text : theme.text.opacity(0.85))
      Text(item.category)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(theme.placeholder.opacity(0.8))
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(theme.text.opacity(0.06))
        )
      Spacer(minLength: 0)
      shortcutCaps(for: item)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(isSelected ? theme.text.opacity(0.08) : Color.clear)
        .padding(.horizontal, 6)
    )
  }

  @ViewBuilder
  private func shortcutCaps(for item: CommandItem) -> some View {
    if let chord = item.chord, !chord.isEmpty {
      KeyCap.row(for: chord, theme: theme, size: .compact)
    }
  }

  private var countLabel: String {
    controller.results.isEmpty ? "" : "\(controller.results.count)"
  }

}
