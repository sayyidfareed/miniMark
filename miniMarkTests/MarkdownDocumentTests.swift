import UniformTypeIdentifiers
import XCTest
@testable import miniMark

final class MarkdownDocumentTests: XCTestCase {
  func testReadsUTF8Markdown() throws {
    let document = try MarkdownDocument(data: Data("# Hello\n".utf8))

    XCTAssertEqual(document.text, "# Hello\n")
  }

  func testWritesUTF8Markdown() throws {
    let document = MarkdownDocument(text: "A **small** note")

    XCTAssertEqual(document.dataRepresentation(), Data("A **small** note".utf8))
  }

  func testSupportsMarkdownExtensions() {
    XCTAssertTrue(UTType.minimarkMarkdown.tags[.filenameExtension]?.contains("md") == true)
    XCTAssertTrue(UTType.minimarkMarkdownLong.tags[.filenameExtension]?.contains("markdown") == true)
  }
}
