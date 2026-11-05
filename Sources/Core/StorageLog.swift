import os

/// Unified-logging channel for storage problems that are recovered from
/// (unreadable files, failed renames, fallback writes) rather than thrown.
enum StorageLog {
  static let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "storage")
}
