import Foundation

/// The parts of the status bar that depend only on the text. Measured once per text change, in a
/// single pass, so moving the caret costs a binary search rather than a rescan of the document.
struct DocumentTextMetrics: Equatable {
  var wordCount: Int
  var characterCount: Int
  /// UTF-16 offset at which each line starts; the first is always 0. CRLF counts as one break.
  var lineStarts: [Int]

  static let empty = DocumentTextMetrics(wordCount: 0, characterCount: 0, lineStarts: [0])

  init(wordCount: Int, characterCount: Int, lineStarts: [Int]) {
    self.wordCount = wordCount
    self.characterCount = characterCount
    self.lineStarts = lineStarts
  }

  init(text: String) {
    var words = 0
    var characters = 0
    var inWord = false
    var offset = 0
    var starts = [0]

    for character in text {
      characters += 1
      offset += character.utf16.count

      if Self.isLineBreak(character) {
        starts.append(offset)
        inWord = false
      } else if character.isWhitespace || Self.isCJKPunctuation(character) {
        inWord = false
      } else if Self.isCJKWordCharacter(character) {
        // Chinese and Japanese aren't written with spaces between words; count each ideograph or
        // kana as a word rather than a whole sentence as one.
        words += 1
        inWord = false
      } else if !inWord {
        words += 1
        inWord = true
      }
    }

    self.init(wordCount: words, characterCount: characters, lineStarts: starts)
  }

  /// 1-based line and column of a UTF-16 caret offset. The column counts user-perceived
  /// characters, so an emoji or an accented letter is one column.
  func position(of caret: Int, in text: String) -> (line: Int, column: Int) {
    let nsText = text as NSString
    let caret = min(max(0, caret), nsText.length)

    var low = 0
    var high = lineStarts.count - 1
    while low < high {
      let mid = (low + high + 1) / 2
      if lineStarts[mid] <= caret { low = mid } else { high = mid - 1 }
    }
    let lineStart = min(lineStarts[low], caret)
    let column = nsText.substring(with: NSRange(location: lineStart, length: caret - lineStart)).count + 1
    return (low + 1, column)
  }

  private static func isLineBreak(_ character: Character) -> Bool {
    switch character {
    case "\n", "\r", "\r\n", "\u{85}", "\u{2028}", "\u{2029}": return true
    default: return false
    }
  }

  private static func isCJKWordCharacter(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first else { return false }
    switch scalar.value {
    case 0x3040...0x309F,   // Hiragana
         0x30A0...0x30FF,   // Katakana
         0x31F0...0x31FF,   // Katakana phonetic extensions
         0x3400...0x4DBF,   // CJK extension A
         0x4E00...0x9FFF,   // CJK unified ideographs
         0xF900...0xFAFF,   // CJK compatibility ideographs
         0xFF66...0xFF9F,   // Half-width katakana
         0x20000...0x323AF: // CJK extensions B and later
      return true
    default:
      return false
    }
  }

  private static func isCJKPunctuation(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first else { return false }
    return (0x3000...0x303F).contains(scalar.value)
  }
}

struct DocumentStats: Equatable {
  var wordCount: Int
  var characterCount: Int
  var line: Int
  var column: Int

  var readingTimeMinutes: Int {
    max(1, Int((Double(wordCount) / 220.0).rounded(.up)))
  }

  var readingTimeLabel: String {
    wordCount == 0 ? "—" : "\(readingTimeMinutes) min read"
  }

  init(wordCount: Int, characterCount: Int, line: Int, column: Int) {
    self.wordCount = wordCount
    self.characterCount = characterCount
    self.line = line
    self.column = column
  }

  init(metrics: DocumentTextMetrics, text: String, selection: TextSelection) {
    let position = metrics.position(of: selection.location, in: text)
    self.init(
      wordCount: metrics.wordCount,
      characterCount: metrics.characterCount,
      line: position.line,
      column: position.column
    )
  }

  static func calculate(text: String, selection: TextSelection) -> DocumentStats {
    DocumentStats(metrics: DocumentTextMetrics(text: text), text: text, selection: selection)
  }
}
