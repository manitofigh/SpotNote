import Foundation

/// Pure string logic for `☐` / `☑` checklist items -- continuation on
/// Return, indentation, parent auto-checking and pasteboard round-trips.
/// Kept free of AppKit so it can be unit tested directly. All offsets are
/// UTF-16 (`NSString`) to match `NSTextView`.
enum ChecklistText {
  static let unchecked: unichar = 0x2610  // ☐
  static let checked: unichar = 0x2611  // ☑
  static let uncheckedString = "☐"
  static let checkedString = "☑"
  /// One indentation level for nested checklist items.
  static let indentUnit = "\t"
  /// Columns a tab counts for when comparing indentation depth.
  static let tabWidth = 4

  static func isMarker(_ unit: unichar) -> Bool {
    unit == unchecked || unit == checked
  }

  /// A line whose first non-blank character is a checklist marker.
  struct Item: Equatable {
    /// Leading whitespace length (UTF-16).
    let indentLength: Int
    /// Indentation depth in columns (tab = `tabWidth`).
    let depth: Int
    /// Offset of the marker within the line.
    var markerOffset: Int { indentLength }
    let isChecked: Bool
    /// Offset just past the marker and (at most) one following space.
    let contentOffset: Int
    /// `true` when nothing but whitespace follows the marker.
    let isEmpty: Bool
  }

  /// Parses `line` (without its trailing newline) as a checklist item.
  static func item(in line: NSString) -> Item? {
    var index = 0
    var depth = 0
    while index < line.length {
      let unit = line.character(at: index)
      if unit == 0x20 {
        depth += 1
      } else if unit == 0x09 {
        depth += tabWidth
      } else {
        break
      }
      index += 1
    }
    guard index < line.length, isMarker(line.character(at: index)) else { return nil }
    let isChecked = line.character(at: index) == checked
    var content = index + 1
    if content < line.length, line.character(at: content) == 0x20 { content += 1 }
    let rest = line.substring(from: content)
    let isEmpty = rest.allSatisfy { $0 == " " || $0 == "\t" }
    return Item(
      indentLength: index,
      depth: depth,
      isChecked: isChecked,
      contentOffset: content,
      isEmpty: isEmpty
    )
  }

  static func item(in line: String) -> Item? { item(in: line as NSString) }

  /// Text inserted on Return from a checklist line: newline, the same
  /// indentation, and a fresh unchecked marker.
  static func continuation(forLine line: NSString, item: Item) -> String {
    "\n" + line.substring(to: item.indentLength) + uncheckedString + " "
  }

  // MARK: - Parent propagation

  /// After the item on `changedLine` was toggled, walks up the indentation
  /// tree and returns `[lineIndex: isChecked]` for every ancestor whose
  /// state must change: a parent is checked exactly when all of its direct
  /// checklist children are checked.
  static func parentUpdates(lines: [String], changedLine: Int) -> [Int: Bool] {
    var states: [Int: Bool] = [:]
    let items = lines.map { item(in: $0) }
    func isChecked(_ index: Int) -> Bool { states[index] ?? items[index]?.isChecked ?? false }

    var current = changedLine
    while let parent = parentIndex(of: current, items: items, lines: lines) {
      let children = directChildren(of: parent, items: items, lines: lines)
      guard !children.isEmpty else { break }
      let allChecked = children.allSatisfy { isChecked($0) }
      // An unchanged parent means no ancestor above it can change either.
      guard allChecked != isChecked(parent) else { break }
      states[parent] = allChecked
      current = parent
    }
    return states
  }

  /// Nearest preceding checklist line with a smaller depth, stopping at
  /// blank lines and non-checklist text at or below the child's depth.
  private static func parentIndex(of index: Int, items: [Item?], lines: [String]) -> Int? {
    guard index > 0, let child = items[index] else { return nil }
    var cursor = index - 1
    while cursor >= 0 {
      if let candidate = items[cursor] {
        if candidate.depth < child.depth { return cursor }
      } else {
        let line = lines[cursor]
        if line.allSatisfy({ $0 == " " || $0 == "\t" }) { return nil }
        // Plain wrapped/continuation text that is indented deeper than
        // the child belongs to a sibling; anything else ends the list.
        if leadingDepth(line) <= child.depth { return nil }
      }
      cursor -= 1
    }
    return nil
  }

  /// Checklist items below `parent` (until the indented run ends) whose
  /// nearest shallower ancestor is `parent`.
  private static func directChildren(of parent: Int, items: [Item?], lines: [String]) -> [Int] {
    guard let parentItem = items[parent] else { return [] }
    var children: [Int] = []
    var cursor = parent + 1
    while cursor < items.count {
      if let candidate = items[cursor] {
        guard candidate.depth > parentItem.depth else { break }
        if parentIndex(of: cursor, items: items, lines: lines) == parent { children.append(cursor) }
      } else if endsRun(lines[cursor], belowDepth: parentItem.depth) {
        break
      }
      cursor += 1
    }
    return children
  }

  /// A plain line ends a parent's child run when it's blank or no deeper
  /// than the parent.
  private static func endsRun(_ line: String, belowDepth depth: Int) -> Bool {
    leadingDepth(line) <= depth || line.allSatisfy { $0 == " " || $0 == "\t" }
  }

  private static func leadingDepth(_ line: String) -> Int {
    var depth = 0
    for character in line {
      if character == " " {
        depth += 1
      } else if character == "\t" {
        depth += tabWidth
      } else {
        break
      }
    }
    return depth
  }

  // MARK: - Pasteboard

  /// Markers become portable markdown (`[ ]` / `[x]`) for other apps.
  static func exportForPasteboard(_ raw: String) -> String {
    raw
      .replacingOccurrences(of: "☐ ", with: "[ ] ")
      .replacingOccurrences(of: "☑ ", with: "[x] ")
      .replacingOccurrences(of: "☐", with: "[ ]")
      .replacingOccurrences(of: "☑", with: "[x]")
  }

  private static let importRegex: NSRegularExpression? = try? NSRegularExpression(
    pattern: #"^([ \t]*)(?:[-*] )?\[([ xX])\](?= |$)"#,
    options: [.anchorsMatchLines]
  )

  /// Restores markers for `[ ]` / `[x]` (optionally after a `- ` bullet)
  /// at the start of a line, at any indentation.
  static func importFromPasteboard(_ text: String) -> String {
    guard let regex = importRegex else { return text }
    let ns = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
    guard !matches.isEmpty else { return text }
    let result = NSMutableString(string: text)
    for match in matches.reversed() {
      let indent = ns.substring(with: match.range(at: 1))
      let state = ns.substring(with: match.range(at: 2))
      let marker = state == " " ? uncheckedString : checkedString
      result.replaceCharacters(in: match.range, with: indent + marker)
    }
    return result as String
  }
}
