import AppKit
import Core
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ChatTransferService {
  enum TransferError: LocalizedError {
    case emptySelection
    case unsupportedArchive(URL)

    var errorDescription: String? {
      switch self {
      case .emptySelection:
        return "Select at least one note to export."
      case .unsupportedArchive(let url):
        return "\(url.lastPathComponent) is not a supported SpotNote archive."
      }
    }
  }

  static let archiveContentType =
    UTType(filenameExtension: "sn")
    ?? UTType(exportedAs: "com.spotnote.chat-archive", conformingTo: .json)

  @discardableResult
  static func exportWithSavePanel(chats: [Chat]) throws -> URL? {
    guard !chats.isEmpty else { throw TransferError.emptySelection }
    let panel = NSSavePanel()
    panel.title = "Export SpotNote Chat"
    panel.allowedContentTypes = [archiveContentType]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = suggestedFileName(for: chats)
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return try writeArchive(chats: chats, to: url)
  }

  static func importWithOpenPanel() throws -> [Chat] {
    let panel = NSOpenPanel()
    panel.title = "Import SpotNote Chats"
    panel.allowedContentTypes = [archiveContentType]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    guard panel.runModal() == .OK else { return [] }
    return try panel.urls.flatMap(readArchive)
  }

  static func share(chats: [Chat], from view: NSView) throws {
    guard !chats.isEmpty else { throw TransferError.emptySelection }
    let url = try writeTemporaryArchive(chats: chats)
    let picker = NSSharingServicePicker(items: [url])
    picker.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
  }

  @discardableResult
  static func writeArchive(chats: [Chat], to url: URL) throws -> URL {
    guard !chats.isEmpty else { throw TransferError.emptySelection }
    let output = url.pathExtension.lowercased() == "sn" ? url : url.appendingPathExtension("sn")
    let archive = ChatArchive(chats: chats)
    let data = try archive.encodedData()
    let scoped = output.startAccessingSecurityScopedResource()
    defer {
      if scoped { output.stopAccessingSecurityScopedResource() }
    }
    try data.write(to: output, options: .atomic)
    return output
  }

  static func readArchive(from url: URL) throws -> [Chat] {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }
    let archive = try ChatArchive.decode(Data(contentsOf: url))
    guard archive.version <= ChatArchive.currentVersion else {
      throw TransferError.unsupportedArchive(url)
    }
    return archive.chats
  }

  static func suggestedFileName(for chats: [Chat]) -> String {
    if chats.count == 1, let chat = chats.first {
      let title = sanitizedTitle(from: chat.text)
      return "\(title.isEmpty ? "SpotNote Chat" : title).sn"
    }
    return "SpotNote Chats \(dateStamp()).sn"
  }

  private static func writeTemporaryArchive(chats: [Chat]) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "SpotNote-Share-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: suggestedFileName(for: chats), directoryHint: .notDirectory)
    return try writeArchive(chats: chats, to: url)
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

  private static func dateStamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
  }
}
