import XCTest
@testable import miniMark

final class DocumentStatsTests: XCTestCase {
  func testCountsWordsCharactersAndPosition() {
    let text = "One two\nThree"
    let stats = DocumentStats.calculate(
      text: text,
      selection: TextSelection(location: (text as NSString).length, length: 0)
    )

    XCTAssertEqual(stats.wordCount, 3)
    XCTAssertEqual(stats.characterCount, text.count)
    XCTAssertEqual(stats.line, 2)
    XCTAssertEqual(stats.column, 6)
  }

  func testCRLFCountsAsOneLineBreak() {
    let text = "a\r\nb\r\nc"
    let stats = DocumentStats.calculate(
      text: text,
      selection: TextSelection(location: (text as NSString).length, length: 0)
    )

    XCTAssertEqual(stats.line, 3)
    XCTAssertEqual(stats.column, 2)
  }

  func testColumnCountsUserPerceivedCharacters() {
    let text = "e\u{301}👍🏽x"
    let stats = DocumentStats.calculate(
      text: text,
      selection: TextSelection(location: (text as NSString).length, length: 0)
    )

    XCTAssertEqual(stats.line, 1)
    XCTAssertEqual(stats.column, 4)
    XCTAssertEqual(stats.characterCount, 3)
  }

  func testCaretInMiddleOfDocument() {
    let text = "first line\nsecond line\nthird"
    let stats = DocumentStats.calculate(text: text, selection: TextSelection(location: 18, length: 0))

    XCTAssertEqual(stats.line, 2)
    XCTAssertEqual(stats.column, 8)
  }

  func testCJKCountsEachIdeographAsAWord() {
    XCTAssertEqual(DocumentStats.calculate(text: "Hello 世界。", selection: .zero).wordCount, 3)
    XCTAssertEqual(DocumentStats.calculate(text: "日本語のテキスト", selection: .zero).wordCount, 8)
  }

  func testMetricsMatchOneShotCalculation() {
    let text = "# Title\n\nSome words here.\r\nMore."
    let metrics = DocumentTextMetrics(text: text)
    let selection = TextSelection(location: 12, length: 0)

    XCTAssertEqual(
      DocumentStats(metrics: metrics, text: text, selection: selection),
      DocumentStats.calculate(text: text, selection: selection)
    )
    XCTAssertEqual(metrics.lineStarts, [0, 8, 9, 27])
  }
}

