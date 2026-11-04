import AppKit
import XCTest
@testable import miniMark

final class MarkdownFormattingTests: XCTestCase {
  private func selected(_ result: MarkdownFormatResult) -> String {
    (result.text as NSString).substring(with: result.selection.nsRange)
  }

  // MARK: Inline markers

  func testBoldWrapsSelectionAndKeepsItSelected() {
    let result = MarkdownFormatter.apply(
      .bold,
      to: "hello world",
      selection: TextSelection(location: 6, length: 5)
    )

    XCTAssertEqual(result.text, "hello **world**")
    XCTAssertEqual(result.selection, TextSelection(location: 8, length: 5))
  }

  func testBoldTogglesOffWhenSelectionIsInsideMarkers() {
    let result = MarkdownFormatter.apply(
      .bold,
      to: "hello **world**",
      selection: TextSelection(location: 8, length: 5)
    )

    XCTAssertEqual(result.text, "hello world")
    XCTAssertEqual(selected(result), "world")
  }

  func testBoldTogglesOffWhenSelectionIncludesMarkers() {
    let result = MarkdownFormatter.apply(.bold, to: "**bold**", selection: TextSelection(location: 0, length: 8))

    XCTAssertEqual(result.text, "bold")
    XCTAssertEqual(selected(result), "bold")
  }

  func testBoldTwiceRestoresOriginalText() {
    let first = MarkdownFormatter.apply(.bold, to: "a word here", selection: TextSelection(location: 2, length: 4))
    let second = MarkdownFormatter.apply(.bold, to: first.text, selection: first.selection)

    XCTAssertEqual(second.text, "a word here")
    XCTAssertEqual(second.selection, TextSelection(location: 2, length: 4))
  }

  func testItalicOnBoldTextAddsItalicInsteadOfStrippingBold() {
    let result = MarkdownFormatter.apply(.italic, to: "**x**", selection: TextSelection(location: 2, length: 1))

    XCTAssertEqual(result.text, "***x***")
  }

  func testBoldDoesNotUnwrapAcrossTwoSeparateBoldRuns() {
    let text = "**a** and **b**"
    let result = MarkdownFormatter.apply(.bold, to: text, selection: TextSelection(location: 0, length: (text as NSString).length))

    XCTAssertNotEqual(result.text, "a** and **b")
  }

  func testBoldKeepsSurroundingWhitespaceOutsideMarkers() {
    let result = MarkdownFormatter.apply(.bold, to: "say hello now", selection: TextSelection(location: 3, length: 7))

    XCTAssertEqual(result.text, "say **hello** now")
  }

  func testBoldWithoutSelectionInsertsSelectedPlaceholder() {
    let result = MarkdownFormatter.apply(.bold, to: "", selection: .zero)

    XCTAssertEqual(result.text, "**strong text**")
    XCTAssertEqual(selected(result), "strong text")
  }

  func testLinkSelectsURLPlaceholder() {
    let result = MarkdownFormatter.apply(
      .link,
      to: "miniMark",
      selection: TextSelection(location: 0, length: 8)
    )

    XCTAssertEqual(result.text, "[miniMark](url)")
    XCTAssertEqual((result.text as NSString).substring(with: result.selection.nsRange), "url")
  }

  // MARK: Line markers

  func testHeadingWithCaretPrefixesTheCaretsLine() {
    let result = MarkdownFormatter.apply(.heading, to: "first\nsecond", selection: TextSelection(location: 8, length: 0))

    XCTAssertEqual(result.text, "first\n# second")
    XCTAssertEqual(result.selection, TextSelection(location: 10, length: 0))
  }

  func testHeadingOnExistingHeadingTogglesItOff() {
    let result = MarkdownFormatter.apply(.heading, to: "# Title", selection: TextSelection(location: 4, length: 0))

    XCTAssertEqual(result.text, "Title")
    XCTAssertEqual(result.selection, TextSelection(location: 2, length: 0))
  }

  func testHeadingOnDeeperHeadingTogglesItOff() {
    let result = MarkdownFormatter.apply(.heading, to: "## Title", selection: TextSelection(location: 0, length: 8))

    XCTAssertEqual(result.text, "Title")
  }

  func testHeadingOnEmptyLineInsertsMarkerOnly() {
    let result = MarkdownFormatter.apply(.heading, to: "", selection: .zero)

    XCTAssertEqual(result.text, "# ")
    XCTAssertEqual(result.selection, TextSelection(location: 2, length: 0))
  }

  func testBulletedListPrefixesSelectedLines() {
    let result = MarkdownFormatter.apply(
      .unorderedList,
      to: "one\ntwo",
      selection: TextSelection(location: 0, length: 7)
    )

    XCTAssertEqual(result.text, "- one\n- two")
  }

  func testBulletedListWithCaretPrefixesLineNotCaret() {
    let result = MarkdownFormatter.apply(.unorderedList, to: "buy milk", selection: TextSelection(location: 4, length: 0))

    XCTAssertEqual(result.text, "- buy milk")
    XCTAssertEqual(result.selection, TextSelection(location: 6, length: 0))
  }

  func testBulletedListTogglesOff() {
    let result = MarkdownFormatter.apply(.unorderedList, to: "- one\n- two", selection: TextSelection(location: 0, length: 11))

    XCTAssertEqual(result.text, "one\ntwo")
  }

  func testBulletedListSkipsBlankLinesInSelection() {
    let result = MarkdownFormatter.apply(.unorderedList, to: "one\n\ntwo", selection: TextSelection(location: 0, length: 8))

    XCTAssertEqual(result.text, "- one\n\n- two")
  }

  func testSelectingWholeLinesDoesNotMarkTheNextLine() {
    let result = MarkdownFormatter.apply(.unorderedList, to: "one\ntwo\nthree", selection: TextSelection(location: 0, length: 8))

    XCTAssertEqual(result.text, "- one\n- two\nthree")
  }

  func testNumberedListConvertsBullets() {
    let result = MarkdownFormatter.apply(.orderedList, to: "- a\n- b", selection: TextSelection(location: 0, length: 7))

    XCTAssertEqual(result.text, "1. a\n2. b")
  }

  func testNumberedListTogglesOff() {
    let result = MarkdownFormatter.apply(.orderedList, to: "1. a\n2. b", selection: TextSelection(location: 0, length: 9))

    XCTAssertEqual(result.text, "a\nb")
  }

  func testQuoteWithCaretPrefixesLineAndTogglesOff() {
    let quoted = MarkdownFormatter.apply(.quote, to: "a\nwise words", selection: TextSelection(location: 5, length: 0))
    XCTAssertEqual(quoted.text, "a\n> wise words")

    let unquoted = MarkdownFormatter.apply(.quote, to: quoted.text, selection: quoted.selection)
    XCTAssertEqual(unquoted.text, "a\nwise words")
  }

  func testQuoteKeepsBlankLinesInsideTheQuote() {
    let result = MarkdownFormatter.apply(.quote, to: "one\n\ntwo", selection: TextSelection(location: 0, length: 8))

    XCTAssertEqual(result.text, "> one\n>\n> two")
  }

  // MARK: Code blocks

  func testCodeBlockInsertsPlaceholderWhenSelectionIsEmpty() {
    let result = MarkdownFormatter.apply(
      .codeBlock,
      to: "",
      selection: .zero
    )

    XCTAssertEqual(result.text, "```\ncode\n```")
    XCTAssertEqual((result.text as NSString).substring(with: result.selection.nsRange), "code")
  }

  func testCodeBlockMidLinePutsFencesOnTheirOwnLines() {
    let result = MarkdownFormatter.apply(.codeBlock, to: "abc", selection: TextSelection(location: 1, length: 0))

    XCTAssertEqual(result.text, "a\n```\ncode\n```\nbc")
    XCTAssertEqual(selected(result), "code")
  }

  func testCodeBlockAroundWholeLinesKeepsOneNewline() {
    let result = MarkdownFormatter.apply(.codeBlock, to: "a\nb\nc", selection: TextSelection(location: 2, length: 2))

    XCTAssertEqual(result.text, "a\n```\nb\n```\nc")
  }

  // MARK: Minimal edits

  func testTextEditReplacesOnlyTheChangedSpan() throws {
    let edit = try XCTUnwrap(MarkdownTextEdit.between("hello world", "hello **world**"))

    XCTAssertEqual(edit.range.location, 6)
    XCTAssertEqual(
      ("hello world" as NSString).replacingCharacters(in: edit.range, with: edit.replacement),
      "hello **world**"
    )
  }

  func testTextEditDoesNotSplitSurrogatePairs() throws {
    let edit = try XCTUnwrap(MarkdownTextEdit.between("a😀b", "a😃b"))

    XCTAssertEqual(edit.range, NSRange(location: 1, length: 2))
    XCTAssertEqual(edit.replacement, "😃")
  }

  func testTextEditIsNilForIdenticalText() {
    XCTAssertNil(MarkdownTextEdit.between("same", "same"))
  }
}

final class MarkdownSourceStylerTests: XCTestCase {
  private func makeStyledStorage(_ text: String) -> (NSTextStorage, MarkdownSourceStyler) {
    let storage = NSTextStorage(string: text)
    let styler = MarkdownSourceStyler()
    storage.delegate = styler
    styler.styleAll(storage)
    return (storage, styler)
  }

  /// The same text styled from scratch, to check incremental restyling gives the identical result.
  private func freshlyStyled(_ text: String) -> NSTextStorage {
    makeStyledStorage(text).0
  }

  private func font(_ storage: NSTextStorage, at location: Int) -> NSFont? {
    storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
  }

  private func location(of needle: String, in storage: NSTextStorage) -> Int {
    (storage.string as NSString).range(of: needle).location
  }

  private func longDocument(lines count: Int) -> String {
    (0..<count).map { index -> String in
      switch index % 50 {
      case 0: return "# Section \(index)"
      case 10: return "```swift"
      case 11: return "let value = \(index) // **not bold**"
      case 12: return "```"
      case 20: return "- item with **bold** and `code`"
      default: return "Line \(index) with *emphasis* and a [link](https://example.com)."
      }
    }.joined(separator: "\n")
  }

  func testOneCharacterEditInLongDocumentRestylesOnlyItsParagraph() {
    let (storage, styler) = makeStyledStorage(longDocument(lines: 10_000))
    let target = location(of: "Line 5003 with", in: storage)

    storage.replaceCharacters(in: NSRange(location: target, length: 0), with: "x")
    let restyled = styler.stylePendingEdits(in: storage)

    XCTAssertNotEqual(restyled.location, NSNotFound)
    XCTAssertTrue(NSLocationInRange(target, restyled))
    XCTAssertLessThan(restyled.length, 200, "a one-character edit should restyle one paragraph, not the document")
    XCTAssertTrue(storage.isEqual(to: freshlyStyled(storage.string)))
  }

  func testEditInsideLongDocumentCodeBlockRestylesOnlyItsParagraph() {
    let (storage, styler) = makeStyledStorage(longDocument(lines: 10_000))
    let target = location(of: "let value = 5011", in: storage)

    storage.replaceCharacters(in: NSRange(location: target, length: 0), with: "# ")
    let restyled = styler.stylePendingEdits(in: storage)

    XCTAssertLessThan(restyled.length, 200)
    XCTAssertEqual(font(storage, at: target), MarkdownSourceStyler.baseFont)
    XCTAssertTrue(storage.isEqual(to: freshlyStyled(storage.string)))
  }

  func testNothingPendingRestylesNothing() {
    let (storage, styler) = makeStyledStorage("# Title\n")

    XCTAssertEqual(styler.stylePendingEdits(in: storage).location, NSNotFound)
  }

  func testFencedCodeIsNotStyledAsMarkdown() {
    let (storage, _) = makeStyledStorage("```bash\n# comment\necho **hi**\n```\n# After\n")

    XCTAssertEqual(font(storage, at: location(of: "# comment", in: storage)), MarkdownSourceStyler.baseFont)
    XCTAssertEqual(font(storage, at: location(of: "hi**", in: storage)), MarkdownSourceStyler.baseFont)
    XCTAssertGreaterThan(font(storage, at: location(of: "# After", in: storage))?.pointSize ?? 0, 14)
  }

  func testOpeningAFenceRestylesTheTextItNowContains() {
    let (storage, styler) = makeStyledStorage("# Title\n\nSome **bold** text\n\n```bash\n# comment\n```\n\n# After\n")

    storage.replaceCharacters(in: NSRange(location: location(of: "Some", in: storage), length: 0), with: "```\n")
    let restyled = styler.stylePendingEdits(in: storage)

    XCTAssertTrue(NSLocationInRange(location(of: "# comment", in: storage), restyled))
    XCTAssertEqual(font(storage, at: location(of: "bold", in: storage)), MarkdownSourceStyler.baseFont)
    XCTAssertTrue(storage.isEqual(to: freshlyStyled(storage.string)))
  }

  func testDeletingAnOpeningFenceRestoresMarkdownStyling() {
    let (storage, styler) = makeStyledStorage("```\n# inside\n```\n")

    storage.replaceCharacters(in: NSRange(location: 0, length: 4), with: "")
    styler.stylePendingEdits(in: storage)

    XCTAssertGreaterThan(font(storage, at: 0)?.pointSize ?? 0, 14)
    XCTAssertTrue(storage.isEqual(to: freshlyStyled(storage.string)))
  }

  func testJoiningAFenceLineToTheLineAboveRestylesTheBlock() {
    let (storage, styler) = makeStyledStorage("text\n```\n# inside\n```\n# after\n")

    // Delete the newline in front of the opening fence: "text```" is not a fence.
    storage.replaceCharacters(in: NSRange(location: 4, length: 1), with: "")
    styler.stylePendingEdits(in: storage)

    XCTAssertTrue(storage.isEqual(to: freshlyStyled(storage.string)))
  }

  func testSeveralEditsBeforeRestyleMatchAFullRestyle() {
    let (storage, styler) = makeStyledStorage(longDocument(lines: 200))

    storage.replaceCharacters(in: NSRange(location: location(of: "Line 3 ", in: storage), length: 0), with: "**")
    storage.replaceCharacters(in: NSRange(location: location(of: "Line 121 ", in: storage), length: 4), with: "# Head")
    storage.replaceCharacters(in: NSRange(location: location(of: "Line 3 ", in: storage), length: 0), with: "z")
    styler.stylePendingEdits(in: storage)

    XCTAssertTrue(storage.isEqual(to: freshlyStyled(storage.string)))
  }

  func testReturnInsideHeadingUnstylesTheNewLine() {
    let (storage, styler) = makeStyledStorage("# Title\n")

    storage.replaceCharacters(in: NSRange(location: 4, length: 0), with: "\n")
    styler.stylePendingEdits(in: storage)

    XCTAssertEqual(font(storage, at: location(of: "tle", in: storage)), MarkdownSourceStyler.baseFont)
    XCTAssertTrue(storage.isEqual(to: freshlyStyled(storage.string)))
  }

  func testHeadingDoesNotSpanLines() {
    let (storage, _) = makeStyledStorage("#\nnext\n#hashtag\n")

    XCTAssertEqual(font(storage, at: location(of: "next", in: storage)), MarkdownSourceStyler.baseFont)
    XCTAssertEqual(font(storage, at: location(of: "#hashtag", in: storage)), MarkdownSourceStyler.baseFont)
  }

  func testBoldInsideHeadingKeepsHeadingSize() throws {
    let (storage, _) = makeStyledStorage("# a **b**\n")

    let headingFont = try XCTUnwrap(font(storage, at: 2))
    let boldFont = try XCTUnwrap(font(storage, at: location(of: "b**", in: storage)))
    XCTAssertEqual(boldFont.pointSize, headingFont.pointSize)
  }
}
