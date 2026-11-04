import AppKit

/// Colours and sizes Markdown source in the editor's text storage.
///
/// The styler remembers where the fenced code blocks are, so an ordinary keystroke restyles only the
/// paragraphs it touched. An edit that adds, removes or changes a fence line also restyles every
/// paragraph whose code-block membership changed (for a new opening fence that is usually the rest of
/// the document). Text inside a fenced block gets no Markdown styling.
///
/// Set an instance as the text storage's delegate so it sees every character edit, call `styleAll(_:)`
/// once, then `stylePendingEdits(in:)` after each change.
final class MarkdownSourceStyler: NSObject, NSTextStorageDelegate {
  static let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

  static let paragraphStyle: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 2.5
    style.paragraphSpacing = 3
    return style
  }()

  static var baseAttributes: [NSAttributedString.Key: Any] {
    [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraphStyle]
  }

  static var typingAttributes: [NSAttributedString.Key: Any] {
    [.font: baseFont, .foregroundColor: NSColor.labelColor]
  }

  /// A fenced code block: `range` runs from the start of the opening fence line to the end of the
  /// closing fence line (or the end of the document when the block is never closed).
  struct CodeBlock: Equatable {
    var range: NSRange
    var openingFence: NSRange
    var closingFence: NSRange?

    func shifted(by delta: Int) -> CodeBlock {
      CodeBlock(
        range: NSRange(location: range.location + delta, length: range.length),
        openingFence: NSRange(location: openingFence.location + delta, length: openingFence.length),
        closingFence: closingFence.map { NSRange(location: $0.location + delta, length: $0.length) }
      )
    }
  }

  private(set) var codeBlocks: [CodeBlock] = []
  private var hasStyled = false
  private var pendingRange: NSRange?
  private var pendingDelta = 0

  var hasPendingEdits: Bool { pendingRange != nil || !hasStyled }

  // MARK: Edit tracking

  func textStorage(
    _ textStorage: NSTextStorage,
    didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange,
    changeInLength delta: Int
  ) {
    guard editedMask.contains(.editedCharacters) else { return }
    noteEdit(editedRange, changeInLength: delta)
  }

  /// Records a character edit. `edited` is in post-edit coordinates; `delta` is the change in length.
  /// Several edits before the next restyle merge into one range that covers all of them.
  func noteEdit(_ edited: NSRange, changeInLength delta: Int) {
    guard let pending = pendingRange else {
      pendingRange = edited
      pendingDelta = delta
      return
    }
    let oldEditEnd = NSMaxRange(edited) - delta
    var start = pending.location
    var end = NSMaxRange(pending)
    if end <= edited.location {
      // Entirely before this edit: unchanged.
    } else if start >= oldEditEnd {
      start += delta
      end += delta
    } else {
      start = min(start, edited.location)
      end = max(end + delta, NSMaxRange(edited))
    }
    start = min(start, edited.location)
    end = max(end, NSMaxRange(edited))
    pendingRange = NSRange(location: max(0, start), length: max(0, end - max(0, start)))
    pendingDelta += delta
  }

  // MARK: Styling

  /// Restyles the whole document and rebuilds the code-block map. Returns the styled range.
  @discardableResult
  func styleAll(_ storage: NSTextStorage) -> NSRange {
    let text: NSString = storage.mutableString
    codeBlocks = Self.findCodeBlocks(in: text)
    hasStyled = true
    pendingRange = nil
    pendingDelta = 0
    let fullRange = NSRange(location: 0, length: text.length)
    style(storage, text: text, range: fullRange)
    return fullRange
  }

  /// Restyles what the edits since the last call touched. Returns the restyled range, or a range with
  /// location `NSNotFound` when there was nothing to do.
  @discardableResult
  func stylePendingEdits(in storage: NSTextStorage) -> NSRange {
    guard hasStyled else { return styleAll(storage) }
    guard let pending = pendingRange else { return NSRange(location: NSNotFound, length: 0) }
    let delta = pendingDelta
    pendingRange = nil
    pendingDelta = 0

    let text: NSString = storage.mutableString
    let length = text.length
    let edited = Self.clamp(pending, to: length)
    let oldEdit = NSRange(location: edited.location, length: max(0, edited.length - delta))
    // Include the character after the edit: pressing Return mid-line leaves the second half on a
    // new line that still carries the old line's styling.
    var restyle = text.lineRange(for: NSRange(
      location: edited.location,
      length: min(edited.length + 1, length - edited.location)
    ))

    let fenceTouched = codeBlocks.contains { block in
      Self.touches(oldEdit, block.openingFence) || block.closingFence.map { Self.touches(oldEdit, $0) } == true
    } || Self.containsFenceLine(in: text, range: restyle)

    let adjusted = codeBlocks.map { Self.adjust($0, oldEdit: oldEdit, delta: delta, newLength: length) }
    if fenceTouched {
      let rebuilt = Self.findCodeBlocks(in: text)
      if let changed = Self.changedRegion(old: adjusted, new: rebuilt) {
        restyle = NSUnionRange(restyle, changed)
      }
      codeBlocks = rebuilt
    } else {
      codeBlocks = adjusted.map(\.block)
    }

    restyle = text.lineRange(for: Self.clamp(restyle, to: length))
    style(storage, text: text, range: restyle)
    return restyle
  }

  private func style(_ storage: NSTextStorage, text: NSString, range: NSRange) {
    guard range.length > 0 else { return }
    storage.beginEditing()
    storage.setAttributes(Self.baseAttributes, range: range)

    var cursor = range.location
    let end = NSMaxRange(range)
    for block in codeBlocks where NSMaxRange(block.range) > range.location && block.range.location < end {
      if block.range.location > cursor {
        styleMarkdown(storage, text: text, range: NSRange(location: cursor, length: block.range.location - cursor))
      }
      styleFence(storage, block.openingFence, within: range)
      if let closing = block.closingFence { styleFence(storage, closing, within: range) }
      cursor = max(cursor, NSMaxRange(block.range))
    }
    if cursor < end {
      styleMarkdown(storage, text: text, range: NSRange(location: cursor, length: end - cursor))
    }
    storage.endEditing()
  }

  private func styleFence(_ storage: NSTextStorage, _ fence: NSRange, within range: NSRange) {
    let target = NSIntersectionRange(fence, range)
    guard target.length > 0 else { return }
    storage.addAttributes([.foregroundColor: NSColor.systemPurple, .font: Self.fenceFont], range: target)
  }

  /// Styles paragraphs that are not inside a fenced code block. `range` is paragraph-aligned.
  /// The patterns run over a copy of just this range: matching against the live storage string
  /// could make the regex engine copy the whole document for every pattern.
  private func styleMarkdown(_ storage: NSTextStorage, text: NSString, range: NSRange) {
    let local = text.substring(with: range)
    let localRange = NSRange(location: 0, length: (local as NSString).length)
    let offset = range.location
    func shifted(_ localMatch: NSRange) -> NSRange {
      NSRange(location: localMatch.location + offset, length: localMatch.length)
    }
    func matches(_ regex: NSRegularExpression) -> [NSTextCheckingResult] {
      regex.matches(in: local, range: localRange)
    }

    for match in matches(Self.headingRegex) {
      let level = min(max(match.range(at: 1).length, 1), 6)
      storage.addAttributes([
        .font: Self.headingFonts[level - 1],
        .foregroundColor: NSColor.controlAccentColor
      ], range: shifted(match.range))
    }

    for match in matches(Self.quoteRegex) {
      storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: shifted(match.range))
    }

    for match in matches(Self.listRegex) {
      storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: shifted(match.range(at: 1)))
    }

    let codeSpans = matches(Self.inlineCodeRegex).map(\.range)
    for span in codeSpans {
      storage.addAttributes([
        .foregroundColor: NSColor.systemPink,
        .backgroundColor: Self.codeBackgroundColor
      ], range: shifted(span))
    }
    func outsideCodeSpans(_ match: NSTextCheckingResult) -> Bool {
      !codeSpans.contains { NSIntersectionRange($0, match.range).length > 0 }
    }

    for match in matches(Self.linkRegex) where outsideCodeSpans(match) {
      storage.addAttributes([
        .foregroundColor: NSColor.linkColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue
      ], range: shifted(match.range))
    }

    // Emphasis changes the weight or slant of whatever font is already there, so bold or italic
    // text inside a heading keeps the heading's size.
    for match in matches(Self.boldRegex) where outsideCodeSpans(match) {
      storage.enumerateAttribute(.font, in: shifted(match.range)) { value, subrange, _ in
        let font = (value as? NSFont) ?? Self.baseFont
        storage.addAttribute(.font, value: Self.boldVariant(of: font), range: subrange)
      }
    }

    for match in matches(Self.italicRegex) where outsideCodeSpans(match) {
      storage.enumerateAttribute(.font, in: shifted(match.range)) { value, subrange, _ in
        let font = (value as? NSFont) ?? Self.baseFont
        let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        storage.addAttribute(.font, value: italic, range: subrange)
      }
    }
  }

  // MARK: Fonts, colours and patterns

  private static let headingFonts: [NSFont] = (1...6).map { level in
    NSFont.monospacedSystemFont(ofSize: CGFloat(max(15, 23 - level * 2)), weight: .semibold)
  }
  private static let boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
  private static let fenceFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)

  private static func boldVariant(of font: NSFont) -> NSFont {
    if font.pointSize > baseFont.pointSize {
      return NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold)
    }
    return boldFont
  }

  /// Resolved per appearance, so code spans keep the right tint when the app switches light or dark.
  private static let codeBackgroundColor = NSColor(name: nil) { appearance in
    var color = NSColor.textBackgroundColor
    appearance.performAsCurrentDrawingAppearance {
      color = NSColor.textBackgroundColor.blended(withFraction: 0.08, of: .systemPink) ?? NSColor.textBackgroundColor
    }
    return color
  }

  private static func regex(_ pattern: String) -> NSRegularExpression {
    // The patterns are constants; a typo should fail loudly in tests rather than silently unstyle.
    try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
  }

  private static let headingRegex = regex("^(#{1,6})(?:[ \\t][^\\r\\n]*)?$")
  private static let quoteRegex = regex("^[ \\t]*>[^\\r\\n]*")
  private static let listRegex = regex("^[ \\t]*([-*+] |\\d+\\. )")
  private static let inlineCodeRegex = regex("`[^`\\r\\n]+`")
  private static let linkRegex = regex("\\[[^\\]\\r\\n]+\\]\\([^)\\r\\n]+\\)")
  private static let boldRegex = regex("\\*\\*(?![\\s*])[^*\\r\\n]+(?<![\\s*])\\*\\*")
  private static let italicRegex = regex("(?<!\\*)\\*(?![\\s*])[^*\\r\\n]+(?<![\\s*])\\*(?!\\*)")
  private static let fenceRegex = regex("^ {0,3}(`{3,}|~{3,})([^\\r\\n]*)$")

  // MARK: Code blocks

  static func findCodeBlocks(in text: NSString) -> [CodeBlock] {
    var blocks: [CodeBlock] = []
    var open: (line: NSRange, marker: unichar, count: Int)?
    let fullRange = NSRange(location: 0, length: text.length)

    fenceRegex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
      guard let match else { return }
      let fence = match.range(at: 1)
      let marker = text.character(at: fence.location)
      let rest = text.substring(with: match.range(at: 2))
      let line = text.lineRange(for: NSRange(location: match.range.location, length: 0))

      if let opening = open {
        let isClosing = marker == opening.marker
          && fence.length >= opening.count
          && rest.trimmingCharacters(in: .whitespaces).isEmpty
        if isClosing {
          blocks.append(CodeBlock(
            range: NSRange(location: opening.line.location, length: NSMaxRange(line) - opening.line.location),
            openingFence: opening.line,
            closingFence: line
          ))
          open = nil
        }
      } else {
        // A backtick fence's info string can't contain a backtick (CommonMark 4.5).
        if marker == 0x60, rest.contains("`") { return }
        open = (line, marker, fence.length)
      }
    }

    if let opening = open {
      blocks.append(CodeBlock(
        range: NSRange(location: opening.line.location, length: text.length - opening.line.location),
        openingFence: opening.line,
        closingFence: nil
      ))
    }
    return blocks
  }

  private static func containsFenceLine(in text: NSString, range: NSRange) -> Bool {
    let local = text.substring(with: range)
    return fenceRegex.firstMatch(in: local, range: NSRange(location: 0, length: (local as NSString).length)) != nil
  }

  /// Whether an edit (in pre-edit coordinates) changed a fence line, including joining it to the
  /// line above by deleting the newline in front of it.
  private static func touches(_ edit: NSRange, _ fenceLine: NSRange) -> Bool {
    edit.location < NSMaxRange(fenceLine) && NSMaxRange(edit) >= fenceLine.location
  }

  private struct AdjustedBlock {
    var block: CodeBlock
    /// False when the edit overlapped the block in a way that may have changed it; such a block
    /// never compares equal, and its range is only an approximation of the area it covered.
    var exact: Bool
  }

  private static func adjust(_ block: CodeBlock, oldEdit: NSRange, delta: Int, newLength: Int) -> AdjustedBlock {
    let oldEditEnd = NSMaxRange(oldEdit)
    var result = block
    var exact = true
    if NSMaxRange(block.range) <= oldEdit.location {
      // Before the edit: unchanged (an unclosed block is extended below).
    } else if block.range.location >= oldEditEnd {
      // After the edit: moved. If the edit broke the fence, the rebuilt list won't match it.
      result = block.shifted(by: delta)
    } else if oldEdit.location >= NSMaxRange(block.openingFence),
              block.closingFence.map({ oldEditEnd < $0.location }) ?? true {
      // Inside the block's content: it grows or shrinks; the closing fence moves.
      result.range.length += delta
      result.closingFence = block.closingFence.map { NSRange(location: $0.location + delta, length: $0.length) }
    } else {
      let start = min(block.range.location, oldEdit.location)
      let end = max(NSMaxRange(block.range) + delta, oldEdit.location + max(0, oldEdit.length + delta))
      result.range = NSRange(location: start, length: max(0, end - start))
      exact = false
    }
    if result.closingFence == nil {
      // An unclosed block always runs to the end of the document.
      result.range.length = max(0, newLength - result.range.location)
    }
    result.range = clamp(result.range, to: newLength)
    return AdjustedBlock(block: result, exact: exact)
  }

  /// The area whose code-block membership differs between the old (adjusted) and new block lists.
  private static func changedRegion(old: [AdjustedBlock], new: [CodeBlock]) -> NSRange? {
    func same(_ lhs: AdjustedBlock, _ rhs: CodeBlock) -> Bool { lhs.exact && lhs.block == rhs }
    var prefix = 0
    while prefix < old.count, prefix < new.count, same(old[prefix], new[prefix]) { prefix += 1 }
    var suffix = 0
    while suffix < old.count - prefix, suffix < new.count - prefix,
          same(old[old.count - 1 - suffix], new[new.count - 1 - suffix]) {
      suffix += 1
    }
    let ranges = old[prefix..<(old.count - suffix)].map(\.block.range) + new[prefix..<(new.count - suffix)].map(\.range)
    guard var region = ranges.first else { return nil }
    for range in ranges.dropFirst() { region = NSUnionRange(region, range) }
    return region
  }

  private static func clamp(_ range: NSRange, to length: Int) -> NSRange {
    let location = min(max(0, range.location), length)
    return NSRange(location: location, length: min(max(0, range.length), length - location))
  }
}
