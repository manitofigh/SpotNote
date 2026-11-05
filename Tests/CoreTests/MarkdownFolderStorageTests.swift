import Foundation
import Testing

@testable import Core

@Suite("Markdown folder storage")
struct MarkdownFolderStorageTests {
  static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

  struct Env {
    let builtIn: URL
    let folder: URL

    var configuration: StorageConfiguration {
      StorageConfiguration(builtInDirectory: builtIn, markdownFolder: folder)
    }

    func store(at date: Date = t0, debounce: Duration = .milliseconds(10)) throws -> ChatStore {
      try ChatStore(configuration: configuration, debounce: debounce, now: { date })
    }

    func markdownFiles() throws -> [String] {
      try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".md") }.sorted()
    }

    func read(_ name: String) throws -> String {
      try String(contentsOf: folder.appending(path: name), encoding: .utf8)
    }

    /// Simulates another app (or device) writing a file.
    func writeExternally(_ name: String, _ text: String, modified: Date) throws {
      let url = folder.appending(path: name)
      try Data(text.utf8).write(to: url)
      try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }
  }

  func makeEnv() throws -> Env {
    Env(builtIn: try TempFolder.make(), folder: try TempFolder.make())
  }

  @Test("new notes are written as Markdown files and renamed when the first line changes")
  func createAndRename() async throws {
    let env = try makeEnv()
    let store = try env.store()
    let chat = try await store.create()
    let short = MarkdownFileName.shortID(chat.id)
    #expect(try env.markdownFiles() == ["Untitled \(short).md"])
    await store.update(id: chat.id, text: "Shopping list\n☐ milk")
    await store.flush()
    #expect(try env.markdownFiles() == ["Shopping list \(short).md"])
    let contents = try env.read("Shopping list \(short).md")
    #expect(contents.hasPrefix("---\nid: \(chat.id.uuidString)\ncreated: "))
    #expect(contents.hasSuffix("---\nShopping list\n[ ] milk"))
  }

  @Test("files the user named are never renamed")
  func userNamedFilesKeepTheirName() async throws {
    let env = try makeEnv()
    try env.writeExternally("My Note.md", "hello", modified: Self.t0)
    let store = try env.store()
    let chat = try #require(await store.list().first)
    await store.update(id: chat.id, text: "a completely different title")
    await store.flush()
    #expect(try env.markdownFiles() == ["My Note.md"])
    #expect(try env.read("My Note.md").contains("id: \(chat.id.uuidString)"))
  }

  @Test("a relaunch restores id, created, pinned, text and updatedAt from the folder")
  func relaunchRoundTrip() async throws {
    let env = try makeEnv()
    let first = try env.store()
    let chat = try await first.create()
    await first.update(id: chat.id, text: "Pinned idea")
    try await first.togglePin(id: chat.id)
    await first.flush()

    let reloaded = try #require(await env.store().get(chat.id))
    #expect(reloaded == Chat(id: chat.id, createdAt: Self.t0, updatedAt: Self.t0, text: "Pinned idea", isPinned: true))
  }

  @Test("enabling folder mode copies built-in notes without touching the originals")
  func portCopiesWithoutModifyingSource() async throws {
    let env = try makeEnv()
    let builtIn = try ChatStore(
      configuration: StorageConfiguration(builtInDirectory: env.builtIn),
      debounce: .milliseconds(10),
      now: { Self.t0 }
    )
    let one = try await builtIn.create()
    await builtIn.update(id: one.id, text: "Alpha")
    let two = try await builtIn.create()
    await builtIn.update(id: two.id, text: "Beta")
    await builtIn.flush()
    let occupied = "Alpha \(MarkdownFileName.shortID(one.id)).md"
    try env.writeExternally(occupied, "someone else's file", modified: Self.t0)
    let before = try snapshot(of: env.builtIn)

    let summary = try await builtIn.useMarkdownFolder(env.folder)

    #expect(summary == PortSummary(copied: 2, skipped: 0, conflictCopies: 0))
    #expect(try snapshot(of: env.builtIn) == before)
    #expect(try env.read(occupied) == "someone else's file")
    #expect(try env.markdownFiles().contains("Alpha \(MarkdownFileName.shortID(one.id)) 2.md"))
    #expect(try env.markdownFiles().count == 3)
    #expect(await builtIn.list().map(\.text).sorted() == ["Alpha", "Beta", "someone else's file"])
    #expect(await builtIn.isUsingMarkdownFolder)

    let again = try await builtIn.copyBuiltInNotesIntoFolder()
    #expect(again == PortSummary(copied: 0, skipped: 2, conflictCopies: 0))
  }

  @Test("re-porting after built-in edits keeps both versions as a conflict copy")
  func reportConflicts() async throws {
    let env = try makeEnv()
    let builtIn = try ChatStore(directory: env.builtIn, debounce: .milliseconds(10))
    let chat = try await builtIn.create()
    await builtIn.update(id: chat.id, text: "v1")
    _ = try await builtIn.useMarkdownFolder(env.folder)
    // A later session edited the built-in copy (e.g. while the folder was offline).
    var edited = chat
    edited.text = "v2 offline"
    edited.updatedAt = Date().addingTimeInterval(3600)
    try await ChatStore(directory: env.builtIn).restore(edited)

    let summary = try await env.store().copyBuiltInNotesIntoFolder()
    #expect(summary.conflictCopies == 1)
    #expect(try env.markdownFiles().contains { $0.contains("(conflict ") })
  }

  @Test("rescan picks up external additions, edits and deletions")
  func rescanExternalChanges() async throws {
    let env = try makeEnv()
    let store = try env.store()
    #expect(try await store.rescan() == false)

    try env.writeExternally("Added.md", "from another device", modified: Self.t0)
    #expect(try await store.rescan())
    let added = try #require(await store.list().first)
    #expect(added.text == "from another device")

    try env.writeExternally("Added.md", "edited in another editor", modified: Self.t0.addingTimeInterval(5))
    #expect(try await store.rescan())
    #expect(await store.get(added.id)?.text == "edited in another editor")
    #expect(await store.get(added.id)?.updatedAt == Self.t0.addingTimeInterval(5))

    try FileManager.default.removeItem(at: env.folder.appending(path: "Added.md"))
    #expect(try await store.rescan())
    #expect(await store.list().isEmpty)
  }

  @Test("rescan does not re-read files whose mtime and size are unchanged")
  func rescanIsIncremental() async throws {
    let env = try makeEnv()
    try env.writeExternally("Note.md", "aaaa", modified: Self.t0)
    let store = try env.store()
    // Same size, same mtime, different bytes: only a full re-read would notice.
    try env.writeExternally("Note.md", "bbbb", modified: Self.t0)
    #expect(try await store.rescan() == false)
    #expect(await store.list().map(\.text) == ["aaaa"])
  }

  @Test("an externally renamed file keeps its note identity")
  func externalRename() async throws {
    let env = try makeEnv()
    let store = try env.store()
    let chat = try await store.create()
    let name = try #require(try env.markdownFiles().first)
    try FileManager.default.moveItem(at: env.folder.appending(path: name), to: env.folder.appending(path: "Renamed.md"))
    #expect(try await store.rescan())
    #expect(await store.list().map(\.id) == [chat.id])
  }

  @Test("iCloud placeholders, hidden files, subfolders and other types are ignored")
  func ignoresJunk() async throws {
    let env = try makeEnv()
    try env.writeExternally(".Evicted.md.icloud", "bplist junk", modified: Self.t0)
    try env.writeExternally(".DS_Store", "junk", modified: Self.t0)
    try env.writeExternally("image.png", "junk", modified: Self.t0)
    try FileManager.default.createDirectory(at: env.folder.appending(path: "sub"), withIntermediateDirectories: true)
    try env.writeExternally("sub/Nested.md", "nested", modified: Self.t0)
    let store = try env.store()
    #expect(await store.list().isEmpty)
  }

  @Test("an external edit overwritten by a local save is kept as a conflict copy")
  func writeConflict() async throws {
    let env = try makeEnv()
    let store = try env.store()
    let chat = try await store.create()
    let name = try #require(try env.markdownFiles().first)
    try env.writeExternally(
      name,
      "---\nid: \(chat.id.uuidString)\n---\nremote edit",
      modified: Self.t0.addingTimeInterval(9)
    )
    await store.update(id: chat.id, text: "local edit")
    await store.flush()

    let texts = await store.list().map(\.text).sorted()
    #expect(texts == ["local edit", "remote edit"])
    #expect(await store.get(chat.id)?.text == "local edit")
    #expect(try env.markdownFiles().contains { $0.hasPrefix("remote edit (conflict ") })
  }

  @Test("rescan during an unsaved local edit keeps both versions")
  func rescanConflict() async throws {
    let env = try makeEnv()
    let store = try env.store(debounce: .seconds(3600))
    let chat = try await store.create()
    let name = try #require(try env.markdownFiles().first)
    await store.update(id: chat.id, text: "unsaved local")
    try env.writeExternally(
      name,
      "---\nid: \(chat.id.uuidString)\n---\nremote",
      modified: Self.t0.addingTimeInterval(9)
    )

    #expect(try await store.rescan())
    #expect(await store.get(chat.id)?.text == "unsaved local")
    #expect(await store.list().map(\.text).sorted() == ["remote", "unsaved local"])
  }

  func snapshot(of directory: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
    // The folder-sync ledger is bookkeeping next to the notes, not a note.
    while let url = enumerator?.nextObject() as? URL {
      var isDirectory: ObjCBool = false
      guard url.lastPathComponent != "folder-ports.plist",
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue
      else { continue }
      let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      result[url.path + "@\(modified?.timeIntervalSince1970 ?? 0)"] = try Data(contentsOf: url)
    }
    return result
  }
}

extension MarkdownFolderStorageTests {
  @Test("importing the same folder twice adds its notes only once")
  func importDedupe() async throws {
    let env = try makeEnv()
    let source = try TempFolder.make()
    try FileManager.default.createDirectory(at: source.appending(path: "sub"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: source.appending(path: ".obsidian"), withIntermediateDirectories: true)
    try Data("# One\n- [x] done".utf8).write(to: source.appending(path: "one.md"))
    try Data("two\r\n".utf8).write(to: source.appending(path: "two.txt"))
    try Data("---\ntags: [a]\n---\nthree".utf8).write(to: source.appending(path: "sub/three.markdown"))
    try Data("config".utf8).write(to: source.appending(path: ".obsidian/app.md"))
    try Data("one copy".utf8).write(to: source.appending(path: ".one.md.icloud"))
    let before = try snapshot(of: source)
    let store = try ChatStore(directory: env.builtIn)

    let scan = try await MarkdownFolderImporter.scan(source)
    #expect(scan.unavailable == 1)
    let first = try await store.importNewChats(scan.chats)
    #expect(first.inserted.map(\.text).sorted() == ["# One\n- ☑ done", "---\ntags: [a]\n---\nthree", "two\n"])
    let second = try await store.importNewChats(try await MarkdownFolderImporter.scan(source).chats)
    #expect(second.inserted.isEmpty)
    #expect(second.duplicates == 3)
    #expect(try snapshot(of: source) == before)
  }

  @Test("an unavailable folder fails loudly and edits fall back to built-in storage")
  func unavailableFolder() async throws {
    let env = try makeEnv()
    let store = try env.store()
    let chat = try await store.create()
    try FileManager.default.removeItem(at: env.folder)

    await #expect(throws: (any Error).self) { try await store.rescan() }
    #expect(await store.get(chat.id) != nil)
    await store.update(id: chat.id, text: "typed while offline")
    await store.flush()
    #expect(await store.takeFallbackWrites())
    #expect(await store.takeFallbackWrites() == false)
    let backup = try ChatStore(directory: env.builtIn)
    #expect(await backup.get(chat.id)?.text == "typed while offline")
    #expect(throws: MarkdownFolderError.folderUnavailable(env.folder)) { try env.store() }
  }

  @Test("switching back to built-in storage can copy folder notes")
  func switchBack() async throws {
    let env = try makeEnv()
    try env.writeExternally("Folder only.md", "folder only", modified: Self.t0)
    let store = try env.store()
    let copied = try await store.useBuiltInStorage(copyingFolderNotes: true)
    #expect(copied == 1)
    #expect(await store.isUsingMarkdownFolder == false)
    #expect(await store.list().map(\.text) == ["folder only"])
    #expect(try env.markdownFiles() == ["Folder only.md"])
    #expect(try await store.useBuiltInStorage(copyingFolderNotes: true) == 0)
  }

  @Test("deleting a note removes its file")
  func deleteRemovesFile() async throws {
    let env = try makeEnv()
    let store = try env.store()
    let chat = try await store.create()
    try await store.delete(id: chat.id)
    #expect(try env.markdownFiles().isEmpty)
  }
}
