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

/// The smallest single replacement that turns one string into another, in UTF-16 offsets of the
/// original. The editor applies formatting through this so the change is one ordinary, undoable
/// text-view edit instead of a replacement of the whole document.
struct MarkdownTextEdit: Equatable {
  var range: NSRange
  var replacement: String

  static func between(_ original: String, _ updated: String) -> MarkdownTextEdit? {
    guard original != updated else { return nil }
    let old = original as NSString
    let new = updated as NSString
    let oldUnits = original.utf16
    let newUnits = updated.utf16

    var prefix = zip(oldUnits, newUnits).prefix { $0 == $1 }.count
    var suffix = zip(oldUnits.reversed(), newUnits.reversed()).prefix { $0 == $1 }.count
    suffix = min(suffix, min(old.length, new.length) - prefix)

    // Don't split a surrogate pair at either end.
    if prefix > 0, UTF16.isLeadSurrogate(old.character(at: prefix - 1)) { prefix -= 1 }
    if suffix > 0, UTF16.isTrailSurrogate(old.character(at: old.length - suffix)) { suffix -= 1 }

    let range = NSRange(location: prefix, length: old.length - suffix - prefix)
    let replacement = new.substring(with: NSRange(location: prefix, length: new.length - suffix - prefix))
    return MarkdownTextEdit(range: range, replacement: replacement)
  }
}

enum MarkdownFormatter {
  static func apply(
    _ command: MarkdownFormatCommand,
    to text: String,
    selection: TextSelection
  ) -> MarkdownFormatResult {
    switch command {
    case .bold:
      toggleInline(text: text, selection: selection, marker: "**", placeholder: "strong text")
    case .italic:
      toggleInline(text: text, selection: selection, marker: "*", placeholder: "emphasis")
    case .inlineCode:
      toggleInline(text: text, selection: selection, marker: "`", placeholder: "code")
    case .link:
      insertLink(text: text, selection: selection)
    case .heading:
      toggleLines(.heading, text: text, selection: selection)
    case .unorderedList:
      toggleLines(.bullet, text: text, selection: selection)
    case .orderedList:
      toggleLines(.numbered, text: text, selection: selection)
    case .quote:
      toggleLines(.quote, text: text, selection: selection)
    case .codeBlock:
      wrapCodeBlock(text: text, selection: selection)
    }
  }

  // MARK: Inline markers

  /// Wraps the selection in `marker`, or removes the marker when the selection is already wrapped,
  /// either inside the markers (`**|word|**`) or including them (`|**word**|`).
  private static func toggleInline(
    text: String,
    selection: TextSelection,
    marker: String,
    placeholder: String
  ) -> MarkdownFormatResult {
    let nsText = text as NSString
    let range = selection.clamped(to: nsText.length).nsRange
    let markerLength = (marker as NSString).length
    let markerUnit = (marker as NSString).character(at: 0)

    func runLength(from start: Int, step: Int, limit: Int) -> Int {
      var count = 0
      var index = start
      while index >= 0, index < nsText.length, count < limit, nsText.character(at: index) == markerUnit {
        count += 1
        index += step
      }
      return count
    }
    // `*` alone is italic only on an odd run: `**word**` is bold, `***word***` is both.
    func isWrapped(before: Int, after: Int) -> Bool {
      if marker == "*" { return before % 2 == 1 && after % 2 == 1 }
      return before >= markerLength && after >= markerLength
    }

    func containsMarker(_ candidate: NSRange) -> Bool {
      (0..<candidate.length).contains { nsText.character(at: candidate.location + $0) == markerUnit }
    }

    // Markers just outside the selection.
    let before = runLength(from: range.location - 1, step: -1, limit: 3)
    let after = runLength(from: NSMaxRange(range), step: 1, limit: 3)
    if isWrapped(before: before, after: after), !containsMarker(range) {
      let outer = NSRange(location: range.location - markerLength, length: range.length + markerLength * 2)
      let output = nsText.replacingCharacters(in: outer, with: nsText.substring(with: range))
      return MarkdownFormatResult(
        text: output,
        selection: TextSelection(location: outer.location, length: range.length)
      )
    }

    // Markers at the edges of the selection.
    if range.length >= markerLength * 2 + 1 {
      let leading = runLength(from: range.location, step: 1, limit: 3)
      let trailing = runLength(from: NSMaxRange(range) - 1, step: -1, limit: 3)
      let middle = NSRange(location: range.location + leading, length: range.length - leading - trailing)
      if middle.length > 0, !containsMarker(middle), isWrapped(before: leading, after: trailing) {
        let inner = NSRange(location: range.location + markerLength, length: range.length - markerLength * 2)
        let output = nsText.replacingCharacters(in: range, with: nsText.substring(with: inner))
        return MarkdownFormatResult(
          text: output,
          selection: TextSelection(location: range.location, length: inner.length)
        )
      }
    }

    guard range.length > 0 else {
      let replacement = "\(marker)\(placeholder)\(marker)"
      let output = nsText.replacingCharacters(in: range, with: replacement)
      return MarkdownFormatResult(
        text: output,
        selection: TextSelection(location: range.location + markerLength, length: (placeholder as NSString).length)
      )
    }

    // Keep surrounding whitespace outside the markers: `** word**` isn't emphasis.
    let selected = nsText.substring(with: range) as NSString
    var coreStart = 0
    var coreEnd = selected.length
    let whitespace = CharacterSet.whitespacesAndNewlines
    func isSpace(_ unit: unichar) -> Bool { UnicodeScalar(unit).map(whitespace.contains) ?? false }
    while coreStart < coreEnd, isSpace(selected.character(at: coreStart)) { coreStart += 1 }
    while coreEnd > coreStart, isSpace(selected.character(at: coreEnd - 1)) { coreEnd -= 1 }
    if coreStart == coreEnd {
      coreStart = 0
      coreEnd = selected.length
    }
    let core = NSRange(location: range.location + coreStart, length: coreEnd - coreStart)
    let output = nsText.replacingCharacters(in: core, with: "\(marker)\(nsText.substring(with: core))\(marker)")
    return MarkdownFormatResult(
      text: output,
      selection: TextSelection(location: core.location + markerLength, length: core.length)
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

  /// Puts the fences on lines of their own, whatever the caret's position in its line.
  private static func wrapCodeBlock(text: String, selection: TextSelection) -> MarkdownFormatResult {
    let nsText = text as NSString
    let range = selection.clamped(to: nsText.length).nsRange
    var selected = nsText.substring(with: range)
    let endsWithNewline = selected.hasSuffix("\n")
    if endsWithNewline { selected.removeLast() }
    let body = selected.isEmpty ? "code" : selected

    let lead = range.location > 0 && !isLineBreak(nsText.character(at: range.location - 1)) ? "\n" : ""
    let trail: String
    if endsWithNewline {
      trail = "\n"
    } else if NSMaxRange(range) < nsText.length, !isLineBreak(nsText.character(at: NSMaxRange(range))) {
      trail = "\n"
    } else {
      trail = ""
    }

    let replacement = "\(lead)```\n\(body)\n```\(trail)"
    let output = nsText.replacingCharacters(in: range, with: replacement)
    let bodyLocation = range.location + (lead as NSString).length + 4
    return MarkdownFormatResult(
      text: output,
      selection: TextSelection(location: bodyLocation, length: (body as NSString).length)
    )
  }

  // MARK: Line prefixes

  private enum LineStyle {
    case heading
    case bullet
    case numbered
    case quote
  }

  private struct Line {
    var range: NSRange        // the line's content, without its line break
    var indent: Int           // UTF-16 length of leading spaces and tabs
    var heading: Int          // length of a "# " … "###### " marker after the indent, or 0
    var bullet: Int           // length of a "- " / "* " / "+ " marker after the indent, or 0
    var number: Int           // length of a "1. " / "1) " marker after the indent, or 0
    var quote: Int            // length of a ">" or "> " marker after the indent, or 0
    var isBlank: Bool
  }

  /// One replacement in the original text: `range` is replaced by `text`.
  private struct Change {
    var range: NSRange
    var text: String
  }

  /// Adds or removes a line marker on every line the selection touches (the caret's line when
  /// nothing is selected). When every non-blank line already has the marker it is removed, so the
  /// command toggles; otherwise lines without it gain it, and other list markers are converted.
  private static func toggleLines(_ style: LineStyle, text: String, selection: TextSelection) -> MarkdownFormatResult {
    let nsText = text as NSString
    let range = selection.clamped(to: nsText.length).nsRange
    let lines = linesTouched(by: range, in: nsText)

    let targets = lines.filter { !$0.isBlank }.isEmpty ? lines : lines.filter { !$0.isBlank }
    var changes: [Change] = []

    switch style {
    case .heading:
      if targets.allSatisfy({ $0.heading > 0 }) {
        for line in targets {
          changes.append(Change(range: NSRange(location: line.range.location, length: line.indent + line.heading), text: ""))
        }
      } else {
        for line in targets where line.heading == 0 {
          changes.append(Change(range: NSRange(location: line.range.location, length: line.indent), text: "# "))
        }
      }

    case .quote:
      if targets.allSatisfy({ $0.quote > 0 }) {
        for line in targets {
          changes.append(Change(range: NSRange(location: line.range.location + line.indent, length: line.quote), text: ""))
        }
      } else {
        let hasContent = lines.contains { !$0.isBlank }
        for line in lines where line.quote == 0 {
          let start = NSRange(location: line.range.location, length: 0)
          if !line.isBlank || !hasContent {
            changes.append(Change(range: start, text: "> "))
          } else {
            // A blank line inside a multi-line quote gets a bare ">" so the quote stays one block.
            changes.append(Change(range: start, text: ">"))
          }
        }
      }

    case .bullet:
      if targets.allSatisfy({ $0.bullet > 0 }) {
        for line in targets {
          changes.append(Change(range: NSRange(location: line.range.location + line.indent, length: line.bullet), text: ""))
        }
      } else {
        for line in targets where line.bullet == 0 {
          changes.append(Change(range: NSRange(location: line.range.location + line.indent, length: line.number), text: "- "))
        }
      }

    case .numbered:
      if targets.allSatisfy({ $0.number > 0 }) {
        for line in targets {
          changes.append(Change(range: NSRange(location: line.range.location + line.indent, length: line.number), text: ""))
        }
      } else {
        for (index, line) in targets.enumerated() {
          let markerLength = line.number > 0 ? line.number : line.bullet
          changes.append(Change(range: NSRange(location: line.range.location + line.indent, length: markerLength), text: "\(index + 1). "))
        }
      }
    }

    let output = NSMutableString(string: nsText)
    for change in changes.reversed() {
      output.replaceCharacters(in: change.range, with: change.text)
    }

    let newSelection: TextSelection
    if range.length == 0 {
      newSelection = TextSelection(location: map(range.location, through: changes, towardEnd: true), length: 0)
    } else {
      let start = map(range.location, through: changes, towardEnd: false)
      let end = map(NSMaxRange(range), through: changes, towardEnd: true)
      newSelection = TextSelection(location: start, length: max(0, end - start))
    }
    return MarkdownFormatResult(text: output as String, selection: newSelection)
  }

  /// Maps a position in the original text to the output. A position at an insertion point, or inside
  /// replaced text, goes after the new text when `towardEnd` is true and before it otherwise.
  private static func map(_ position: Int, through changes: [Change], towardEnd: Bool) -> Int {
    var shift = 0
    for change in changes {
      let newLength = (change.text as NSString).length
      if position < change.range.location || (position == change.range.location && !towardEnd) {
        break
      }
      if position >= NSMaxRange(change.range) {
        shift += newLength - change.range.length
        continue
      }
      // Inside the replaced text (or at an insertion point, toward the end).
      return towardEnd ? change.range.location + shift + newLength : change.range.location + shift
    }
    return position + shift
  }

  private static func linesTouched(by range: NSRange, in text: NSString) -> [Line] {
    // A selection ending just after a line break doesn't reach into the next line, so selecting
    // whole lines doesn't also mark the line below.
    let lineSpan = text.lineRange(for: range)
    if lineSpan.length == 0 {
      return [parseLine(NSRange(location: lineSpan.location, length: 0), in: text)]
    }

    var lines: [Line] = []
    var location = lineSpan.location
    while location < NSMaxRange(lineSpan) {
      var start = 0
      var end = 0
      var contentsEnd = 0
      text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
      lines.append(parseLine(NSRange(location: start, length: contentsEnd - start), in: text))
      guard end > location else { break }
      location = end
    }
    return lines
  }

  private static func parseLine(_ range: NSRange, in text: NSString) -> Line {
    let content = text.substring(with: range) as NSString
    var index = 0
    while index < content.length, content.character(at: index) == 0x20 || content.character(at: index) == 0x09 {
      index += 1
    }
    let indent = index
    let rest = content.substring(from: indent) as NSString

    func markerLength(_ pattern: NSRegularExpression) -> Int {
      pattern.firstMatch(in: rest as String, range: NSRange(location: 0, length: rest.length))?.range.length ?? 0
    }

    return Line(
      range: range,
      indent: indent,
      heading: markerLength(headingMarker),
      bullet: markerLength(bulletMarker),
      number: markerLength(numberMarker),
      quote: markerLength(quoteMarker),
      isBlank: rest.length == 0
    )
  }

  private static let headingMarker = try! NSRegularExpression(pattern: "^#{1,6}(?:[ \\t]+|$)")
  private static let bulletMarker = try! NSRegularExpression(pattern: "^[-*+][ \\t]+")
  private static let numberMarker = try! NSRegularExpression(pattern: "^\\d{1,9}[.)][ \\t]+")
  private static let quoteMarker = try! NSRegularExpression(pattern: "^> ?")

  private static func isLineBreak(_ unit: unichar) -> Bool {
    unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029
  }
}
