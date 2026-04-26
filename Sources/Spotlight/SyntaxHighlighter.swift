import Foundation

/// Category used by `CodeStyler` to pick a color for the token.
enum SyntaxCategory: Equatable, Sendable {
  case keyword
  case string
  case number
  case comment
}

struct SyntaxToken: Equatable, Sendable {
  let range: NSRange
  let category: SyntaxCategory
}

/// Language-aware, token-by-token scanner used for the code body inside
/// a fenced ` ``` ` block. ASCII-only: a code block with exotic Unicode
/// will still render, the keyword/number highlighting just won't fire on
/// those characters. Good enough for a notes app.
///
/// Strategy is single-pass: scan UTF-16 units, emit a token whenever we
/// enter a comment / string / number / identifier. Identifiers only get
/// the `.keyword` category when they match the active language's word
/// list (or the pan-language fallback set).
enum SyntaxHighlighter {
  static func tokens(in code: String, language: String?) -> [SyntaxToken] {
    let ns = code as NSString
    let length = ns.length
    var tokens: [SyntaxToken] = []
    let keywords = keywordSet(for: language)
    var idx = 0
    while idx < length {
      let unit = ns.character(at: idx)
      if let block = scanCommentBlock(ns, at: idx) {
        tokens.append(SyntaxToken(range: block, category: .comment))
        idx = block.location + block.length
        continue
      }
      if let line = scanLineComment(ns, at: idx, unit: unit) {
        tokens.append(SyntaxToken(range: line, category: .comment))
        idx = line.location + line.length
        continue
      }
      if let str = scanString(ns, at: idx, unit: unit) {
        tokens.append(SyntaxToken(range: str, category: .string))
        idx = str.location + str.length
        continue
      }
      if let num = scanNumber(ns, at: idx, unit: unit) {
        tokens.append(SyntaxToken(range: num, category: .number))
        idx = num.location + num.length
        continue
      }
      if let word = scanIdentifier(ns, at: idx, unit: unit) {
        let token = ns.substring(with: word)
        if keywords.contains(token) {
          tokens.append(SyntaxToken(range: word, category: .keyword))
        }
        idx = word.location + word.length
        continue
      }
      idx += 1
    }
    return tokens
  }

  // MARK: - Scanners

  private static func scanCommentBlock(_ ns: NSString, at idx: Int) -> NSRange? {
    guard idx + 1 < ns.length else { return nil }
    guard ns.character(at: idx) == 0x2F, ns.character(at: idx + 1) == 0x2A else { return nil }
    var end = idx + 2
    while end + 1 < ns.length {
      if ns.character(at: end) == 0x2A, ns.character(at: end + 1) == 0x2F {
        end += 2
        return NSRange(location: idx, length: end - idx)
      }
      end += 1
    }
    return NSRange(location: idx, length: ns.length - idx)
  }

  private static func scanLineComment(_ ns: NSString, at idx: Int, unit: unichar) -> NSRange? {
    let isDoubleSlash =
      unit == 0x2F && idx + 1 < ns.length && ns.character(at: idx + 1) == 0x2F
    let isHash = unit == 0x23
    guard isDoubleSlash || isHash else { return nil }
    var end = idx
    while end < ns.length, ns.character(at: end) != 0x0A { end += 1 }
    return NSRange(location: idx, length: end - idx)
  }

  private static func scanString(_ ns: NSString, at idx: Int, unit: unichar) -> NSRange? {
    guard unit == 0x22 || unit == 0x27 || unit == 0x60 else { return nil }
    let quote = unit
    var end = idx + 1
    while end < ns.length {
      let current = ns.character(at: end)
      if current == 0x5C, end + 1 < ns.length {
        end += 2
        continue
      }
      if current == quote {
        end += 1
        return NSRange(location: idx, length: end - idx)
      }
      if current == 0x0A { break }
      end += 1
    }
    return NSRange(location: idx, length: end - idx)
  }

  private static func scanNumber(_ ns: NSString, at idx: Int, unit: unichar) -> NSRange? {
    guard isAsciiDigit(unit) else { return nil }
    var end = idx
    while end < ns.length {
      let current = ns.character(at: end)
      guard isAsciiDigit(current) || current == 0x2E else { break }
      end += 1
    }
    return NSRange(location: idx, length: end - idx)
  }

  private static func scanIdentifier(_ ns: NSString, at idx: Int, unit: unichar) -> NSRange? {
    guard isIdentifierStart(unit) else { return nil }
    var end = idx + 1
    while end < ns.length, isIdentifierContinue(ns.character(at: end)) { end += 1 }
    return NSRange(location: idx, length: end - idx)
  }

  // MARK: - Character classes (ASCII only -- good enough)

  private static func isAsciiDigit(_ unit: unichar) -> Bool {
    unit >= 0x30 && unit <= 0x39
  }

  private static func isAsciiLetter(_ unit: unichar) -> Bool {
    (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
  }

  private static func isIdentifierStart(_ unit: unichar) -> Bool {
    isAsciiLetter(unit) || unit == 0x5F  // '_'
  }

  private static func isIdentifierContinue(_ unit: unichar) -> Bool {
    isIdentifierStart(unit) || isAsciiDigit(unit)
  }
}

extension SyntaxHighlighter {
  /// Strips an optional `language` hint off the first line of the fence
  /// body. Returns `(language, bodyStartingAfterHint)`.
  static func splitLanguage(from body: String) -> (language: String?, code: String) {
    let ns = body as NSString
    let length = ns.length
    var idx = 0
    while idx < length, isSpaceTabOrNewlineBefore(ns.character(at: idx)) {
      if ns.character(at: idx) == 0x0A { break }
      idx += 1
    }
    let tagStart = idx
    while idx < length, SyntaxHighlighter.isIdentifierContinuePublic(ns.character(at: idx)) {
      idx += 1
    }
    let tagEnd = idx
    guard tagEnd > tagStart else { return (nil, body) }
    // Must be followed by newline (or end) to count as a language tag.
    if idx < length, ns.character(at: idx) != 0x0A { return (nil, body) }
    let lang = ns.substring(with: NSRange(location: tagStart, length: tagEnd - tagStart))
    let codeStart = min(idx + 1, length)
    let code = ns.substring(from: codeStart)
    return (lang.lowercased(), code)
  }

  private static func isSpaceTabOrNewlineBefore(_ unit: unichar) -> Bool {
    unit == 0x20 || unit == 0x09
  }

  static func isIdentifierContinuePublic(_ unit: unichar) -> Bool {
    isIdentifierContinue(unit)
  }
}

extension SyntaxHighlighter {
  static let fallbackKeywords: Set<String> = [
    "if", "else", "elif", "for", "while", "do", "return", "break", "continue",
    "class", "struct", "enum", "interface", "type", "func", "function", "def",
    "var", "let", "const", "fn", "import", "from", "export", "module",
    "public", "private", "internal", "static", "final", "abstract", "extends",
    "implements", "try", "catch", "except", "finally", "throw", "throws",
    "true", "false", "null", "nil", "None", "True", "False", "self", "this",
    "new", "delete", "void", "int", "float", "double", "bool", "string",
    "async", "await", "yield", "lambda", "in", "is", "as", "of", "with",
    "package", "use", "mod", "pub", "mut", "impl", "trait", "where",
    "switch", "case", "default", "break"
  ]

  // swiftlint:disable:next function_body_length
  static func keywordSet(for language: String?) -> Set<String> {
    guard let language = language?.lowercased() else { return fallbackKeywords }
    switch language {
    case "swift":
      return [
        "func", "let", "var", "struct", "class", "enum", "protocol", "extension",
        "if", "else", "for", "while", "return", "import", "guard", "self", "Self",
        "public", "private", "internal", "fileprivate", "open", "static", "init",
        "deinit", "switch", "case", "default", "break", "continue", "throws",
        "throw", "try", "catch", "do", "in", "as", "is", "async", "await",
        "true", "false", "nil", "where", "associatedtype", "typealias", "inout",
        "mutating", "nonmutating", "lazy", "final", "override"
      ]
    case "python", "py":
      return [
        "def", "class", "import", "from", "if", "elif", "else", "for", "while",
        "return", "yield", "lambda", "try", "except", "finally", "with", "as",
        "pass", "True", "False", "None", "and", "or", "not", "in", "is", "raise",
        "break", "continue", "global", "nonlocal", "assert", "async", "await"
      ]
    case "javascript", "js", "typescript", "ts":
      return [
        "function", "var", "let", "const", "class", "if", "else", "for", "while",
        "return", "import", "export", "from", "async", "await", "this", "null",
        "undefined", "true", "false", "new", "typeof", "instanceof", "in", "of",
        "try", "catch", "finally", "throw", "switch", "case", "default", "break",
        "continue", "interface", "type", "extends", "implements", "public",
        "private", "protected", "readonly", "static", "enum", "yield"
      ]
    case "go", "golang":
      return [
        "func", "var", "const", "type", "struct", "interface", "if", "else",
        "for", "range", "return", "package", "import", "chan", "go", "defer",
        "map", "switch", "case", "default", "break", "continue", "fallthrough",
        "select", "goto", "true", "false", "nil"
      ]
    case "rust", "rs":
      return [
        "fn", "let", "mut", "struct", "enum", "impl", "trait", "pub", "if",
        "else", "for", "while", "loop", "return", "use", "mod", "self", "Self",
        "as", "in", "match", "ref", "move", "where", "async", "await", "dyn",
        "unsafe", "extern", "crate", "super", "true", "false"
      ]
    case "bash", "sh", "shell", "zsh":
      return [
        "if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while",
        "until", "case", "esac", "function", "return", "exit", "break",
        "continue", "local", "export", "readonly", "declare", "echo"
      ]
    default:
      return fallbackKeywords
    }
  }
}
