import Core
import SwiftUI

/// Spotlight-style overlay rendered below the editor while the fuzzy
/// "open any note" palette is active. A search field at the top, a
/// scrollable result list below, ⌘P-style keyboard navigation
/// throughout. ↑/↓ move the selection; ⏎ opens it; Esc closes.
struct FuzzyPalette: View {
  @ObservedObject var controller: FuzzyController
  let theme: Theme
  let onPick: (Chat) -> Void

  static let reservedHeight: CGFloat = 220

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
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(theme.placeholder)

      TextField(
        "Search all notes…",
        text: Binding(
          get: { controller.query },
          set: { controller.setQuery($0) }
        )
      )
      .textFieldStyle(.plain)
      .font(.system(size: 13))
      .foregroundStyle(theme.text)
      .focused($focused)
      .onSubmit { commit() }
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
            ForEach(Array(controller.results.enumerated()), id: \.element.id) { index, result in
              row(result, index: index)
                .id(result.id)
            }
          }
        }
        .padding(.vertical, 4)
      }
      .onChange(of: controller.selectedIndex) { _, newIndex in
        if let result = controller.results[safe: newIndex] {
          withAnimation(.easeOut(duration: 0.08)) { proxy.scrollTo(result.id, anchor: .center) }
        }
      }
    }
  }

  private var emptyState: some View {
    Text(controller.query.isEmpty ? "Start typing to search…" : "No matches")
      .font(.system(size: 11))
      .foregroundStyle(theme.placeholder)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.vertical, 18)
  }

  private func row(_ result: FuzzyResult, index: Int) -> some View {
    let isSelected = index == controller.selectedIndex
    return HStack(spacing: 8) {
      Image(systemName: "doc.text")
        .font(.system(size: 11))
        .foregroundStyle(isSelected ? theme.text : theme.placeholder)
        .frame(width: 14)
      if result.chat.isPinned {
        Text("★")
          .font(.system(size: 9))
          .foregroundStyle(Color(red: 0.95, green: 0.75, blue: 0.25))
      }
      Text("#\(result.position)")
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(theme.placeholder)
        .frame(minWidth: 24, alignment: .leading)
      Text(result.snippet.isEmpty ? "(empty note)" : result.snippet)
        .font(.system(size: 12))
        .foregroundStyle(isSelected ? theme.text : theme.text.opacity(0.7))
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(isSelected ? theme.text.opacity(0.08) : Color.clear)
        .padding(.horizontal, 6)
    )
    .contentShape(Rectangle())
    .onTapGesture {
      controller.selectedIndex = index
      commit()
    }
  }

  private var countLabel: String {
    if controller.query.isEmpty && controller.results.isEmpty { return "" }
    return "\(controller.results.count)"
  }

  private func commit() {
    if let chat = controller.selectedChat() {
      onPick(chat)
      controller.close()
    }
  }
}

extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
