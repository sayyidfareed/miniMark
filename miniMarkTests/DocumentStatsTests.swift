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
}

