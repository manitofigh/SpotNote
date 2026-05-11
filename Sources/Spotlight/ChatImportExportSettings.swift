import Core
import SwiftUI

@MainActor
final class ChatImportExportViewModel: ObservableObject {
  @Published private(set) var chats: [Chat] = []
  @Published var selectedIDs: Set<UUID> = []
  @Published private(set) var status: Status?
  @Published private(set) var isBusy = false

  struct Status: Equatable {
    let kind: ChatImportExportStatusKind
    let message: String
  }

  private let store: ChatStore
  private let onLibraryChanged: @MainActor () -> Void

  init(store: ChatStore, onLibraryChanged: @escaping @MainActor () -> Void) {
    self.store = store
    self.onLibraryChanged = onLibraryChanged
    refresh()
  }

  var selectedChats: [Chat] {
    chats.filter { selectedIDs.contains($0.id) }
  }

  var selectedCountLabel: String {
    switch selectedIDs.count {
    case 0: return "No notes selected"
    case 1: return "1 note selected"
    default: return "\(selectedIDs.count) notes selected"
    }
  }

  func refresh() {
    Task { await reloadChats() }
  }

  func toggleSelection(for chat: Chat) {
    if selectedIDs.contains(chat.id) {
      selectedIDs.remove(chat.id)
    } else {
      selectedIDs.insert(chat.id)
    }
  }

  func selectAll() {
    selectedIDs = Set(chats.map(\.id))
  }

  func clearSelection() {
    selectedIDs = []
  }

  func exportSelected() {
    export(chats: selectedChats)
  }

  func exportAll() {
    export(chats: chats)
  }

  func importArchives() {
    Task { await importArchivesTask() }
  }

  private func importArchivesTask() async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      let imported = try ChatTransferService.importWithOpenPanel()
      guard !imported.isEmpty else { return }
      let inserted = try await store.importChats(imported)
      await reloadChats()
      selectedIDs = Set(inserted.map(\.id))
      status = Status(kind: .success, message: "Imported \(noteCount(inserted.count)).")
      onLibraryChanged()
    } catch {
      status = Status(kind: .failure, message: error.localizedDescription)
    }
  }

  private func export(chats: [Chat]) {
    do {
      if let url = try ChatTransferService.exportWithSavePanel(chats: chats) {
        status = Status(kind: .success, message: "Exported \(noteCount(chats.count)) to \(url.lastPathComponent).")
      }
    } catch {
      status = Status(kind: .failure, message: error.localizedDescription)
    }
  }

  private func reloadChats() async {
    let latest = await store.list()
    chats = latest
    selectedIDs = selectedIDs.intersection(Set(latest.map(\.id)))
  }

  private func noteCount(_ count: Int) -> String {
    count == 1 ? "1 note" : "\(count) notes"
  }
}

enum ChatImportExportStatusKind: Equatable {
  case success
  case failure
}

struct ImportExportPane: View {
  @StateObject private var model: ChatImportExportViewModel

  init(store: ChatStore, onLibraryChanged: @escaping @MainActor () -> Void) {
    _model = StateObject(
      wrappedValue: ChatImportExportViewModel(
        store: store,
        onLibraryChanged: onLibraryChanged
      )
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      PaneHeader(title: "Import / Export")

      SettingsCard {
        ImportExportActionRow(
          icon: "square.and.arrow.down",
          title: "Import SpotNote chats",
          subtitle: "Choose one or more .sn files and add their notes to this library.",
          buttonTitle: "Import",
          isDisabled: model.isBusy,
          action: model.importArchives
        )

        SettingsDivider()

        ExportActionRow(
          selectedLabel: model.selectedCountLabel,
          exportSelected: model.exportSelected,
          exportAll: model.exportAll,
          disableSelected: model.selectedIDs.isEmpty,
          disableAll: model.chats.isEmpty
        )
      }

      chatPicker
      status
    }
    .onAppear { model.refresh() }
  }

  private var chatPicker: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Text("Saved Notes")
          .font(.system(.subheadline, weight: .semibold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
          .tracking(0.6)
        Spacer(minLength: 0)
        SettingsPillButton("Select all", action: model.selectAll)
          .disabled(model.chats.isEmpty)
        SettingsPillButton("Clear", action: model.clearSelection)
          .disabled(model.selectedIDs.isEmpty)
      }

      SettingsCard {
        if model.chats.isEmpty {
          EmptyExportList()
        } else {
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(Array(model.chats.enumerated()), id: \.element.id) { index, chat in
                if index > 0 { SettingsDivider() }
                ChatExportSelectionRow(
                  chat: chat,
                  isSelected: model.selectedIDs.contains(chat.id)
                ) {
                  model.toggleSelection(for: chat)
                }
              }
            }
          }
          .frame(maxHeight: 280)
        }
      }
    }
  }

  @ViewBuilder
  private var status: some View {
    if let status = model.status {
      Label(status.message, systemImage: status.kind == .success ? "checkmark.circle" : "exclamationmark.triangle")
        .font(.system(.subheadline, weight: .medium))
        .foregroundStyle(status.kind == .success ? Color.green.opacity(0.85) : Color.orange.opacity(0.9))
    }
  }
}

private struct ImportExportActionRow: View {
  let icon: String
  let title: String
  let subtitle: String
  let buttonTitle: String
  let isDisabled: Bool
  let action: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(.body, weight: .regular))
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      SettingsPillButton(buttonTitle, action: action)
        .disabled(isDisabled)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}

private struct ExportActionRow: View {
  let selectedLabel: String
  let exportSelected: () -> Void
  let exportAll: () -> Void
  let disableSelected: Bool
  let disableAll: Bool

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "square.and.arrow.up")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text("Export SpotNote chats")
          .font(.system(.body, weight: .regular))
        Text(selectedLabel)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      HStack(spacing: 8) {
        SettingsPillButton("Export selected", action: exportSelected)
          .disabled(disableSelected)
        SettingsPillButton("Export all", action: exportAll)
          .disabled(disableAll)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}

private struct ChatExportSelectionRow: View {
  let chat: Chat
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(.body, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(metadata)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        if chat.isPinned {
          Image(systemName: "pin.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.28))
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 9)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var title: String {
    let first =
      chat.text
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty }) ?? ""
    return first.isEmpty ? "(empty note)" : String(first.prefix(90))
  }

  private var metadata: String {
    chat.updatedAt.formatted(date: .abbreviated, time: .shortened)
  }
}

private struct EmptyExportList: View {
  var body: some View {
    Text("No saved notes")
      .font(.system(.subheadline, weight: .medium))
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.vertical, 22)
  }
}
