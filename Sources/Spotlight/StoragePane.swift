import Core
import SwiftUI

/// Settings › Storage: built-in vs. Markdown-folder storage, plus a
/// one-off "import from folder" action.
struct StoragePane: View {
  @ObservedObject var storage: StorageLocationController
  let store: ChatStore
  let onLibraryChanged: @MainActor () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      PaneHeader(title: "Storage")

      if let issue = storage.issue {
        Label(issue, systemImage: "exclamationmark.triangle")
          .font(.system(.subheadline, weight: .medium))
          .foregroundStyle(Color.orange.opacity(0.9))
          .fixedSize(horizontal: false, vertical: true)
      }

      SettingsCard {
        locationRow
        SettingsDivider()
        StorageActionRow(
          icon: "folder.badge.plus",
          title: "Import from folder…",
          subtitle: "Adds .md, .markdown and .txt files as new notes. Notes already in SpotNote are skipped.",
          buttons: [
            StorageButton(
              "Import",
              isDisabled: storage.isBusy,
              action: { storage.importFolder(store: store, onLibraryChanged: onLibraryChanged) }
            )
          ]
        )
      }

      Text(
        "In folder mode each note is a plain Markdown file named after its first line, with a small front matter "
          + "block (id, created, pinned). Changes made by other apps or devices are picked up whenever SpotNote "
          + "becomes active; if both sides changed a note, the other version is kept as a “conflict” copy."
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if let status = storage.status {
        Label(status.message, systemImage: status.isError ? "exclamationmark.triangle" : "checkmark.circle")
          .font(.system(.subheadline, weight: .medium))
          .foregroundStyle(status.isError ? Color.orange.opacity(0.9) : Color.green.opacity(0.85))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private var locationRow: some View {
    if let folder = storage.activeFolder {
      StorageActionRow(
        icon: "folder",
        title: "Markdown folder: \(folder.lastPathComponent)",
        subtitle: (folder.path as NSString).abbreviatingWithTildeInPath,
        buttons: [
          StorageButton("Show in Finder", isDisabled: false, action: storage.revealActiveFolder),
          StorageButton(
            "Change Folder…",
            isDisabled: storage.isBusy,
            action: { storage.chooseFolder(store: store, onLibraryChanged: onLibraryChanged) }
          ),
          StorageButton(
            "Use App Storage",
            isDisabled: storage.isBusy,
            action: { storage.switchToBuiltIn(store: store, onLibraryChanged: onLibraryChanged) }
          )
        ]
      )
    } else {
      StorageActionRow(
        icon: "internaldrive",
        title: "App storage",
        subtitle: "Notes are saved in SpotNote's own data on this Mac. Choose a folder to keep them as Markdown "
          + "files instead (iCloud Drive, Dropbox, an Obsidian vault…).",
        buttons: builtInButtons
      )
    }
  }

  private var builtInButtons: [StorageButton] {
    var buttons: [StorageButton] = [
      StorageButton(
        "Choose Folder…",
        isDisabled: storage.isBusy,
        action: { storage.chooseFolder(store: store, onLibraryChanged: onLibraryChanged) }
      )
    ]
    if storage.hasUnavailableFolder {
      buttons.insert(
        StorageButton(
          "Retry Folder",
          isDisabled: storage.isBusy,
          action: { storage.retrySavedFolder(store: store, onLibraryChanged: onLibraryChanged) }
        ),
        at: 0
      )
    }
    return buttons
  }
}

private struct StorageActionRow: View {
  let icon: String
  let title: String
  let subtitle: String
  let buttons: [StorageButton]

  /// A single button sits on the trailing edge; several go on their own
  /// row under the text so neither the labels nor the path get squeezed.
  var body: some View {
    HStack(alignment: buttons.count > 1 ? .top : .center, spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(.body, weight: .regular))
          .lineLimit(1)
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .truncationMode(.middle)
          .fixedSize(horizontal: false, vertical: true)
        if buttons.count > 1 {
          buttonRow.padding(.top, 8)
        }
      }
      Spacer(minLength: 0)
      if buttons.count == 1 {
        buttonRow
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private var buttonRow: some View {
    HStack(spacing: 8) {
      ForEach(buttons.indices, id: \.self) { index in
        SettingsPillButton(buttons[index].label, action: buttons[index].action)
          .disabled(buttons[index].isDisabled)
      }
    }
  }
}

private struct StorageButton {
  let label: String
  let isDisabled: Bool
  let action: () -> Void

  init(_ label: String, isDisabled: Bool, action: @escaping () -> Void) {
    self.label = label
    self.isDisabled = isDisabled
    self.action = action
  }
}
