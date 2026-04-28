import Foundation

enum MarkdownFormatCommand: CaseIterable {
  case bold
  case italic
  case link
  case heading
  case unorderedList
  case orderedList
  case quote
  case inlineCode
  case codeBlock
}

struct MarkdownFormatResult: Equatable {
  var text: String
  var selection: TextSelection
}

enum MarkdownFormatter {
  static func apply(
    _ command: MarkdownFormatCommand,
    to text: String,
    selection: TextSelection
  ) -> MarkdownFormatResult {
    switch command {
    case .bold:
      wrapInline(text: text, selection: selection, prefix: "**", suffix: "**", placeholder: "strong text")
    case .italic:
      wrapInline(text: text, selection: selection, prefix: "*", suffix: "*", placeholder: "emphasis")
    case .inlineCode:
      wrapInline(text: text, selection: selection, prefix: "`", suffix: "`", placeholder: "code")
    case .link:
      insertLink(text: text, selection: selection)
    case .heading:
      prefixLines(text: text, selection: selection, prefix: "# ", placeholder: "# Heading")
    case .unorderedList:
      prefixLines(text: text, selection: selection, prefix: "- ", placeholder: "- List item")
    case .orderedList:
      prefixNumberedLines(text: text, selection: selection)
    case .quote:
      prefixLines(text: text, selection: selection, prefix: "> ", placeholder: "> Quote")
    case .codeBlock:
      wrapCodeBlock(text: text, selection: selection)
    }
  }

  private static func wrapInline(
    text: String,
    selection: TextSelection,
    prefix: String,
    suffix: String,
    placeholder: String
  ) -> MarkdownFormatResult {
    let nsText = text as NSString
    let range = selection.clamped(to: nsText.length).nsRange
    let selected = nsText.substring(with: range)
    let body = selected.isEmpty ? placeholder : selected
    let replacement = "\(prefix)\(body)\(suffix)"
    let output = nsText.replacingCharacters(in: range, with: replacement)
    let selectedLocation = range.location + (prefix as NSString).length
    let selectedLength = (body as NSString).length
    return MarkdownFormatResult(
      text: output,
      selection: TextSelection(location: selectedLocation, length: selected.isEmpty ? selectedLength : 0)
    )
  }

  private static func insertLink(text: String, selection: TextSelection) -> MarkdownFormatResult {
    let nsText = text as NSString
    let range = selection.clamped(to: nsText.length).nsRange
    let selected = nsText.substring(with: range)
    let label = selected.isEmpty ? "link text" : selected
    let replacement = "[\(label)](url)"
    let output = nsText.replacingCharacters(in: range, with: replacement)
    let urlLocation = range.location + (replacement as NSString).length - 4
    return MarkdownFormatResult(text: output, selection: TextSelection(location: urlLocation, length: 3))
  }

  private static func wrapCodeBlock(text: String, selection: TextSelection) -> MarkdownFormatResult {
    let nsText = text as NSString
    let range = selection.clamped(to: nsText.length).nsRange
    let selected = nsText.substring(with: range)
    let body = selected.isEmpty ? "code" : selected
    let replacement = "```\n\(body)\n```"
    let output = nsText.replacingCharacters(in: range, with: replacement)
    let selectedLocation = range.location + 4
    let selectedLength = (body as NSString).length
    return MarkdownFormatResult(
      text: output,
      selection: TextSelection(location: selectedLocation, length: selected.isEmpty ? selectedLength : 0)
    )
  }

  private static func prefixLines(
    text: String,
    selection: TextSelection,
    prefix: String,
    placeholder: String
  ) -> MarkdownFormatResult {
    let nsText = text as NSString
    let range = selection.clamped(to: nsText.length).nsRange
    guard range.length > 0 else {
      let output = nsText.replacingCharacters(in: range, with: placeholder)
      let placeholderLength = (placeholder as NSString).length
      return MarkdownFormatResult(
        text: output,
        selection: TextSelection(location: range.location + placeholderLength, length: 0)
      )
    }

    let lineRange = nsText.lineRange(for: range)
    let selectedLines = nsText.substring(with: lineRange)
    let replacement = selectedLines
      .split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
      .map { index, line -> String in
        let isTrailingEmpty = index == selectedLines.split(separator: "\n", omittingEmptySubsequences: false).count - 1
          && selectedLines.hasSuffix("\n")
          && line.isEmpty
        return isTrailingEmpty ? "" : prefix + line
      }
      .joined(separator: "\n")
    let output = nsText.replacingCharacters(in: lineRange, with: replacement)
    return MarkdownFormatResult(
      text: output,
      selection: TextSelection(location: lineRange.location, length: (replacement as NSString).length)
    )
  }

  private static func prefixNumberedLines(text: String, selection: TextSelection) -> MarkdownFormatResult {
    let nsText = text as NSString
    let range = selection.clamped(to: nsText.length).nsRange
    guard range.length > 0 else {
      let replacement = "1. List item"
      let output = nsText.replacingCharacters(in: range, with: replacement)
      return MarkdownFormatResult(
        text: output,
        selection: TextSelection(location: range.location + (replacement as NSString).length, length: 0)
      )
    }

    let lineRange = nsText.lineRange(for: range)
    let selectedLines = nsText.substring(with: lineRange)
    let lines = selectedLines.split(separator: "\n", omittingEmptySubsequences: false)
    var number = 1
    let replacement = lines.enumerated().map { index, line -> String in
      let isTrailingEmpty = index == lines.count - 1 && selectedLines.hasSuffix("\n") && line.isEmpty
      guard !isTrailingEmpty else { return "" }
      defer { number += 1 }
      return "\(number). \(line)"
    }.joined(separator: "\n")
    let output = nsText.replacingCharacters(in: lineRange, with: replacement)
    return MarkdownFormatResult(
      text: output,
      selection: TextSelection(location: lineRange.location, length: (replacement as NSString).length)
    )
  }
}

