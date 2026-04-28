import Foundation

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

  static func calculate(text: String, selection: TextSelection) -> DocumentStats {
    let nsText = text as NSString
    let caret = min(max(0, selection.location), nsText.length)
    let prefix = nsText.substring(with: NSRange(location: 0, length: caret))
    let lineParts = prefix.components(separatedBy: .newlines)

    return DocumentStats(
      wordCount: text.split(whereSeparator: { $0.isWhitespace }).count,
      characterCount: text.count,
      line: max(1, lineParts.count),
      column: max(1, ((lineParts.last ?? "") as NSString).length + 1)
    )
  }
}
