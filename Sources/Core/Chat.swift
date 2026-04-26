import Foundation

/// A persisted note buffer keyed by `id`. Stored as one JSON file per
/// chat under the `ChatStore` directory.
public struct Chat: Sendable, Codable, Identifiable, Equatable {
  public let id: UUID
  public let createdAt: Date
  public var updatedAt: Date
  public var text: String
  public var isPinned: Bool

  public init(
    id: UUID = UUID(),
    createdAt: Date,
    updatedAt: Date,
    text: String,
    isPinned: Bool = false
  ) {
    self.id = id
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.text = text
    self.isPinned = isPinned
  }
}
