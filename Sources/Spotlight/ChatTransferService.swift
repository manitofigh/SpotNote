import AppKit
import Core
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ChatTransferService {
  struct ExportResult {
    let urls: [URL]
    let destinationName: String
  }

  enum TransferError: LocalizedError {
    case emptySelection
    case unsupportedMarkdown(URL)

    var errorDescription: String? {
      switch self {
      case .emptySelection:
        return "Select at least one note to export."
      case .unsupportedMarkdown(let url):
        return "\(url.lastPathComponent) is not a Markdown file."
      }
    }
  }

  static let markdownContentType = UTType(filenameExtension: "md") ?? .plainText

  @discardableResult
  static func exportWithSavePanel(chats: [Chat]) throws -> ExportResult? {
    guard !chats.isEmpty else { throw TransferError.emptySelection }
    if chats.count > 1 {
      return try exportMultipleWithDirectoryPanel(chats: chats)
    }
    guard let chat = chats.first else { throw TransferError.emptySelection }
    let panel = NSSavePanel()
    panel.title = "Export SpotNote Note"
    panel.allowedContentTypes = [markdownContentType]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = suggestedFileName(for: chat)
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    let output = try writeMarkdown(chat: chat, to: url)
    return ExportResult(urls: [output], destinationName: output.lastPathComponent)
  }

  static func importWithOpenPanel() throws -> [Chat] {
    let panel = NSOpenPanel()
    panel.title = "Import Markdown Notes"
    panel.allowedContentTypes = [markdownContentType]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    guard panel.runModal() == .OK else { return [] }
    return try panel.urls.map(readMarkdown)
  }

  static func share(chats: [Chat], from view: NSView) throws {
    guard !chats.isEmpty else { throw TransferError.emptySelection }
    let urls = try writeTemporaryMarkdown(chats: chats)
    let picker = NSSharingServicePicker(items: urls)
    picker.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
  }

  @discardableResult
  static func writeMarkdown(chat: Chat, to url: URL) throws -> URL {
    let output = url.pathExtension.lowercased() == "md" ? url : url.appendingPathExtension("md")
    let scoped = output.startAccessingSecurityScopedResource()
    defer {
      if scoped { output.stopAccessingSecurityScopedResource() }
    }
    try MarkdownNoteCodec.encode(chat.text).write(to: output, atomically: true, encoding: .utf8)
    return output
  }

  static func readMarkdown(from url: URL) throws -> Chat {
    guard url.pathExtension.lowercased() == "md" else {
      throw TransferError.unsupportedMarkdown(url)
    }
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    let text = try String(contentsOf: url, encoding: .utf8)
    let modifiedAt =
      (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      ?? Date()
    return Chat(
      createdAt: modifiedAt,
      updatedAt: modifiedAt,
      text: MarkdownNoteCodec.decode(text)
    )
  }

  static func suggestedFileName(for chat: Chat) -> String {
    let title = sanitizedTitle(from: chat.text)
    return "\(title.isEmpty ? "SpotNote Note" : title).md"
  }

  private static func exportMultipleWithDirectoryPanel(chats: [Chat]) throws -> ExportResult? {
    let panel = NSOpenPanel()
    panel.title = "Choose Export Folder"
    panel.prompt = "Export"
    panel.message = "SpotNote will write one Markdown file per selected note."
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let directory = panel.url else { return nil }
    let urls = try writeMarkdownFiles(chats: chats, to: directory)
    return ExportResult(urls: urls, destinationName: directory.lastPathComponent)
  }

  private static func writeTemporaryMarkdown(chats: [Chat]) throws -> [URL] {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "SpotNote-Share-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try writeMarkdownFiles(chats: chats, to: directory)
  }

  private static func writeMarkdownFiles(chats: [Chat], to directory: URL) throws -> [URL] {
    let scoped = directory.startAccessingSecurityScopedResource()
    defer {
      if scoped { directory.stopAccessingSecurityScopedResource() }
    }
    var reservedNames: Set<String> = []
    return try chats.map { chat in
      let output = uniqueOutputURL(
        suggestedFileName: suggestedFileName(for: chat),
        directory: directory,
        reservedNames: &reservedNames
      )
      try MarkdownNoteCodec.encode(chat.text).write(to: output, atomically: true, encoding: .utf8)
      return output
    }
  }

  private static func uniqueOutputURL(
    suggestedFileName: String,
    directory: URL,
    reservedNames: inout Set<String>
  ) -> URL {
    let baseName = (suggestedFileName as NSString).deletingPathExtension
    var counter = 1
    while true {
      let suffix = counter == 1 ? "" : " \(counter)"
      let fileName = "\(baseName)\(suffix).md"
      let candidate = directory.appending(path: fileName, directoryHint: .notDirectory)
      if !reservedNames.contains(fileName), !FileManager.default.fileExists(atPath: candidate.path) {
        reservedNames.insert(fileName)
        return candidate
      }
      counter += 1
    }
  }

  private static func sanitizedTitle(from text: String) -> String {
    let firstLine =
      text
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty }) ?? ""
    let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
    let scalars = firstLine.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? String(scalar) : "-"
    }
    let collapsed = scalars.joined()
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
    return String(collapsed.prefix(54))
  }

}

enum MarkdownNoteCodec {
  static func encode(_ text: String) -> String {
    text
      .replacingOccurrences(of: "☐", with: "[ ]")
      .replacingOccurrences(of: "☑", with: "[x]")
  }

  static func decode(_ markdown: String) -> String {
    markdown
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "[x]", with: "☑", options: .caseInsensitive)
      .replacingOccurrences(of: "[ ]", with: "☐")
  }
}
