import Foundation

enum NoteHistoryError: Error, Equatable {
  case corrupted
}

/// One stored version: either a full keyframe or a delta against the
/// version immediately before it.
struct HistoryEntry: Equatable, Sendable {
  enum Payload: Equatable, Sendable {
    case keyframe([UInt8])
    case delta(HistoryDelta)
  }

  let date: Date
  let payload: Payload
}

/// Binary on-disk layout for a note's history file (`<uuid>.snhist`):
///
///     file   := magic "SNH1" record*
///     record := u32le length · u8 flags · body[length - 1]
///     flags  := bit0 lzfse-compressed body · bit1 delta (else keyframe)
///     body   := f64le timestamp · payload
///     keyframe payload := raw UTF-8 bytes
///     delta payload    := varint hunkCount · (varint skip · varint remove ·
///                         varint insertLen · bytes)*
///
/// `skip` is relative to the end of the previous hunk, so offsets stay
/// one or two bytes each. Records are self-delimiting, so a new version
/// is a plain append; a torn final record (crash mid-append) is detected
/// by its length prefix and dropped on load.
enum HistoryCodec {
  static let magic: [UInt8] = Array("SNH1".utf8)
  /// Bodies smaller than this are left uncompressed -- lzfse's frame
  /// overhead outweighs any win on a few-byte delta.
  static let compressionThreshold = 96

  private static let compressedFlag: UInt8 = 1 << 0
  private static let deltaFlag: UInt8 = 1 << 1

  /// - Complexity: O(total payload bytes).
  static func encodeFile(_ entries: [HistoryEntry]) -> Data {
    var data = Data(magic)
    for entry in entries { data.append(encodeRecord(entry)) }
    return data
  }

  static func encodeRecord(_ entry: HistoryEntry) -> Data {
    var body: [UInt8] = []
    appendUInt64(&body, entry.date.timeIntervalSince1970.bitPattern)
    var flags: UInt8 = 0
    switch entry.payload {
    case .keyframe(let bytes):
      body.append(contentsOf: bytes)
    case .delta(let delta):
      flags |= deltaFlag
      encodeDelta(delta, into: &body)
    }
    var stored = Data(body)
    if body.count >= compressionThreshold, let packed = compress(stored), packed.count < stored.count {
      stored = packed
      flags |= compressedFlag
    }
    var record = Data()
    let length = UInt32(stored.count + 1).littleEndian
    withUnsafeBytes(of: length) { record.append(contentsOf: $0) }
    record.append(flags)
    record.append(stored)
    return record
  }

  /// Decodes every complete record. `isTruncated` reports a torn tail
  /// so the caller can rewrite the file before appending again.
  ///
  /// - Throws: `NoteHistoryError.corrupted` on a bad magic or an
  ///   undecodable record body.
  /// - Complexity: O(file bytes).
  static func decodeFile(_ data: Data) throws -> (entries: [HistoryEntry], isTruncated: Bool) {
    let bytes = [UInt8](data)
    guard bytes.starts(with: magic) else { throw NoteHistoryError.corrupted }
    var cursor = magic.count
    var entries: [HistoryEntry] = []
    while cursor < bytes.count {
      guard cursor + 5 <= bytes.count else { return (entries, true) }
      let length = Int(readUInt32(bytes, at: cursor))
      let end = cursor + 4 + length
      guard length >= 1, end <= bytes.count else { return (entries, true) }
      let flags = bytes[cursor + 4]
      entries.append(try decodeRecord(flags: flags, stored: bytes[(cursor + 5)..<end]))
      cursor = end
    }
    return (entries, false)
  }

  // MARK: - Private

  private static func decodeRecord(flags: UInt8, stored: ArraySlice<UInt8>) throws -> HistoryEntry {
    var body = Array(stored)
    if flags & compressedFlag != 0 {
      guard let unpacked = decompress(Data(body)) else { throw NoteHistoryError.corrupted }
      body = [UInt8](unpacked)
    }
    guard body.count >= 8 else { throw NoteHistoryError.corrupted }
    var reader = ByteReader(bytes: body, cursor: 8)
    let date = Date(timeIntervalSince1970: Double(bitPattern: readUInt64(body, at: 0)))
    if flags & deltaFlag == 0 {
      return HistoryEntry(date: date, payload: .keyframe(Array(body[8...])))
    }
    return HistoryEntry(date: date, payload: .delta(try decodeDelta(&reader)))
  }

  private static func encodeDelta(_ delta: HistoryDelta, into body: inout [UInt8]) {
    appendVarint(&body, delta.hunks.count)
    var previousEnd = 0
    for hunk in delta.hunks {
      appendVarint(&body, hunk.offset - previousEnd)
      appendVarint(&body, hunk.removeCount)
      appendVarint(&body, hunk.inserted.count)
      body.append(contentsOf: hunk.inserted)
      previousEnd = hunk.offset + hunk.removeCount
    }
  }

  private static func decodeDelta(_ reader: inout ByteReader) throws -> HistoryDelta {
    let count = try reader.varint()
    var hunks: [HistoryDelta.Hunk] = []
    hunks.reserveCapacity(min(count, 4096))
    var previousEnd = 0
    for _ in 0..<count {
      let offset = previousEnd + (try reader.varint())
      let remove = try reader.varint()
      let inserted = try reader.bytes(count: try reader.varint())
      hunks.append(HistoryDelta.Hunk(offset: offset, removeCount: remove, inserted: inserted))
      previousEnd = offset + remove
    }
    return HistoryDelta(hunks: hunks)
  }

  private static func compress(_ data: Data) -> Data? {
    try? (data as NSData).compressed(using: .lzfse) as Data
  }

  private static func decompress(_ data: Data) -> Data? {
    try? (data as NSData).decompressed(using: .lzfse) as Data
  }

  private static func appendVarint(_ bytes: inout [UInt8], _ value: Int) {
    var remaining = UInt64(max(0, value))
    while remaining >= 0x80 {
      bytes.append(UInt8(remaining & 0x7F) | 0x80)
      remaining >>= 7
    }
    bytes.append(UInt8(remaining))
  }

  private static func appendUInt64(_ bytes: inout [UInt8], _ value: UInt64) {
    withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
  }

  private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
  }

  private static func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
    (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << (8 * UInt64($1)) }
  }
}

private struct ByteReader {
  let bytes: [UInt8]
  var cursor: Int

  mutating func varint() throws -> Int {
    var result: UInt64 = 0
    var shift: UInt64 = 0
    while cursor < bytes.count, shift < 63 {
      let byte = bytes[cursor]
      cursor += 1
      result |= UInt64(byte & 0x7F) << shift
      if byte & 0x80 == 0 { return Int(truncatingIfNeeded: result) }
      shift += 7
    }
    throw NoteHistoryError.corrupted
  }

  mutating func bytes(count: Int) throws -> [UInt8] {
    guard count >= 0, cursor + count <= bytes.count else { throw NoteHistoryError.corrupted }
    defer { cursor += count }
    return Array(bytes[cursor..<(cursor + count)])
  }
}
