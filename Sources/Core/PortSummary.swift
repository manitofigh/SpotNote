import Foundation

/// Outcome of copying notes into a Markdown folder.
public struct PortSummary: Sendable, Equatable {
  /// Notes written as new files.
  public var copied = 0
  /// Notes already present in the folder (same id) and not newer.
  public var skipped = 0
  /// Notes present in the folder with different text but edited more
  /// recently in the source; written as separate conflict copies.
  public var conflictCopies = 0

  public var changedFolder: Bool { copied + conflictCopies > 0 }
}

/// Outcome of `importNewChats`.
public struct ImportSummary: Sendable, Equatable {
  public var inserted: [Chat] = []
  /// Incoming notes skipped because the library already had the same
  /// text (or they were empty).
  public var duplicates = 0
}
