import Core
import SwiftUI

/// Version browser rendered below the editor (⌘Y): versions on the left,
/// a preview of the selected one on the right with lines that differ
/// from the current note highlighted. ↑/↓ select, ⏎ restores, Esc closes.
struct HistoryPalette: View {
  @ObservedObject var controller: HistoryController
  let theme: Theme

  static let reservedHeight: CGFloat = 260
  private static let listWidth: CGFloat = 190

  private static let shape = UnevenRoundedRectangle(
    topLeadingRadius: 0,
    bottomLeadingRadius: 10,
    bottomTrailingRadius: 10,
    topTrailingRadius: 0,
    style: .continuous
  )

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
  }()

  private static let added = Color(red: 0.40, green: 0.78, blue: 0.50)
  private static let removed = Color(red: 0.95, green: 0.45, blue: 0.45)

  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider().background(theme.border).opacity(0.6)
      content
    }
    .background(Self.shape.fill(theme.background))
    .overlay(Self.shape.strokeBorder(theme.border, lineWidth: 1))
    .focusable()
    .focusEffectDisabled()
    .focused($focused)
    .onAppear { focused = true }
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
    .onKeyPress(.return) {
      controller.restoreSelected()
      return .handled
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "clock.arrow.circlepath")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(theme.placeholder)
      Text("Version history")
        .font(.system(size: 13))
        .foregroundStyle(theme.text)
      Spacer(minLength: 0)
      Text("↑↓ select  ⏎ restore")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(theme.placeholder)
      Text(controller.versions.isEmpty ? "" : "\(controller.versions.count)")
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

  @ViewBuilder
  private var content: some View {
    if controller.versions.isEmpty {
      Text(emptyMessage)
        .font(.system(size: 11))
        .foregroundStyle(theme.placeholder)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    } else {
      HStack(spacing: 0) {
        versionList
          .frame(width: Self.listWidth)
        Rectangle()
          .fill(theme.border.opacity(0.6))
          .frame(width: 1)
        previewPane
      }
    }
  }

  private var emptyMessage: String {
    if !controller.isEnabled { return "Version history is off. Turn it on in Settings › Editor." }
    if controller.isLoading { return "Loading…" }
    return "No earlier versions yet. Snapshots are saved as you write."
  }

  private var versionList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(controller.versions.enumerated()), id: \.element.id) { index, version in
            row(version, index: index)
              .id(version.id)
          }
        }
        .padding(.vertical, 4)
      }
      .onChange(of: controller.selectedIndex) { _, newIndex in
        if let version = controller.versions[safe: newIndex] {
          withAnimation(.easeOut(duration: 0.08)) { proxy.scrollTo(version.id, anchor: .center) }
        }
      }
    }
  }

  private func row(_ version: NoteVersion, index: Int) -> some View {
    let isSelected = index == controller.selectedIndex
    return HStack(spacing: 6) {
      Text(label(for: version, index: index))
        .font(.system(size: 12, weight: index == 0 ? .medium : .regular))
        .foregroundStyle(isSelected ? theme.text : theme.text.opacity(0.75))
        .lineLimit(1)
      Spacer(minLength: 0)
      if version.addedLines > 0 {
        Text("+\(version.addedLines)")
          .foregroundStyle(Self.added.opacity(isSelected ? 1 : 0.75))
      }
      if version.removedLines > 0 {
        Text("−\(version.removedLines)")
          .foregroundStyle(Self.removed.opacity(isSelected ? 1 : 0.75))
      }
    }
    .font(.system(size: 10, weight: .medium, design: .monospaced))
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(isSelected ? theme.text.opacity(0.08) : Color.clear)
        .padding(.horizontal, 6)
    )
    .contentShape(Rectangle())
    .onTapGesture(count: 2) {
      controller.select(index)
      controller.restoreSelected()
    }
    .onTapGesture { controller.select(index) }
    .help(version.date.formatted(date: .abbreviated, time: .standard))
  }

  private func label(for version: NoteVersion, index: Int) -> String {
    let relative = Self.relativeFormatter.localizedString(for: version.date, relativeTo: Date())
    return index == 0 ? "Latest · \(relative)" : relative
  }

  private var previewPane: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        if let preview = controller.preview {
          ForEach(preview.lines) { line in
            previewLine(line)
          }
          if preview.isTruncated {
            Text("…")
              .foregroundStyle(theme.placeholder)
              .padding(.horizontal, 10)
          }
        }
      }
      .font(.system(size: 11, design: .monospaced))
      .padding(.vertical, 6)
    }
  }

  private func previewLine(_ line: HistoryPreview.Line) -> some View {
    Text(line.text.isEmpty ? " " : line.text)
      .foregroundStyle(line.isChanged ? theme.text : theme.text.opacity(0.6))
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 10)
      .padding(.vertical, 1)
      .background(line.isChanged ? Self.added.opacity(theme.mode == .dark ? 0.16 : 0.22) : Color.clear)
  }
}
