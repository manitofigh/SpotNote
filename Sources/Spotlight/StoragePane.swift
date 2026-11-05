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
            "Change…",
            isDisabled: storage.isBusy,
            action: { storage.chooseFolder(store: store, onLibraryChanged: onLibraryChanged) }
          ),
          StorageButton(
            "Use Built-in",
            isDisabled: storage.isBusy,
            action: { storage.switchToBuiltIn(store: store, onLibraryChanged: onLibraryChanged) }
          )
        ]
      )
    } else {
      StorageActionRow(
        icon: "internaldrive",
        title: "Built-in storage",
        subtitle: "Store notes as Markdown files in a folder you choose (iCloud Drive, Dropbox, an Obsidian vault…).",
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

  var body: some View {
    HStack(spacing: 14) {
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
          .lineLimit(2)
          .truncationMode(.middle)
      }
      Spacer(minLength: 0)
      HStack(spacing: 8) {
        ForEach(buttons.indices, id: \.self) { index in
          SettingsPillButton(buttons[index].label, action: buttons[index].action)
            .disabled(buttons[index].isDisabled)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
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
