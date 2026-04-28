import XCTest
@testable import miniMark

final class MarkdownFormattingTests: XCTestCase {
  func testBoldWrapsSelection() {
    let result = MarkdownFormatter.apply(
      .bold,
      to: "hello world",
      selection: TextSelection(location: 6, length: 5)
    )

    XCTAssertEqual(result.text, "hello **world**")
    XCTAssertEqual(result.selection, TextSelection(location: 8, length: 0))
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

  func testBulletedListPrefixesSelectedLines() {
    let result = MarkdownFormatter.apply(
      .unorderedList,
      to: "one\ntwo",
      selection: TextSelection(location: 0, length: 7)
    )

    XCTAssertEqual(result.text, "- one\n- two")
  }

  func testCodeBlockInsertsPlaceholderWhenSelectionIsEmpty() {
    let result = MarkdownFormatter.apply(
      .codeBlock,
      to: "",
      selection: .zero
    )

    XCTAssertEqual(result.text, "```\ncode\n```")
    XCTAssertEqual((result.text as NSString).substring(with: result.selection.nsRange), "code")
  }
}

