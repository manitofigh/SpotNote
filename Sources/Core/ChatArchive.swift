import Foundation

/// Portable SpotNote chat archive written with the `.sn` extension.
/// Archives can hold one chat for quick sharing or many chats for
/// Settings-driven bulk export.
public struct ChatArchive: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public let version: Int
  public let exportedAt: Date
  public let chats: [Chat]

  public init(
    version: Int = Self.currentVersion,
    exportedAt: Date = Date(),
    chats: [Chat]
  ) {
    self.version = version
    self.exportedAt = exportedAt
    self.chats = chats
  }

  public func encodedData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }

  public static func decode(_ data: Data) throws -> ChatArchive {
    try JSONDecoder().decode(ChatArchive.self, from: data)
  }
}
