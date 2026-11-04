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

  func testReadsUTF8WithBOMAndKeepsBOMOnSave() throws {
    let data = Data([0xEF, 0xBB, 0xBF]) + Data("# Café\n".utf8)
    let document = try MarkdownDocument(data: data)

    XCTAssertEqual(document.text, "# Café\n")
    XCTAssertEqual(document.sourceEncoding, .utf8WithBOM)
    XCTAssertEqual(document.dataRepresentation(), data)
  }

  func testReadsUTF16LittleEndianWithBOMAndRoundTrips() throws {
    let data = Data([0xFF, 0xFE]) + "# Héllo\n".data(using: .utf16LittleEndian)!
    let document = try MarkdownDocument(data: data)

    XCTAssertEqual(document.text, "# Héllo\n")
    XCTAssertEqual(document.sourceEncoding, .utf16LittleEndian)
    XCTAssertEqual(document.dataRepresentation(), data)
  }

  func testReadsUTF16BigEndianWithBOMAndRoundTrips() throws {
    let data = Data([0xFE, 0xFF]) + "# Héllo\n".data(using: .utf16BigEndian)!
    let document = try MarkdownDocument(data: data)

    XCTAssertEqual(document.text, "# Héllo\n")
    XCTAssertEqual(document.sourceEncoding, .utf16BigEndian)
    XCTAssertEqual(document.dataRepresentation(), data)
  }

  func testReadsLatin1BytesAndSavesAsUTF8() throws {
    // 0xE9 is "é" in Latin-1 / Windows-1252 and is not valid UTF-8 on its own.
    let data = Data([0x63, 0x61, 0x66, 0xE9, 0x0A])
    let document = try MarkdownDocument(data: data)

    XCTAssertEqual(document.text, "café\n")
    XCTAssertEqual(document.sourceEncoding, .legacyFallback)
    XCTAssertEqual(document.dataRepresentation(), Data("café\n".utf8))
  }

  func testReadsWindowsCP1252SmartQuotes() throws {
    let data = Data([0x93, 0x68, 0x69, 0x94])
    let document = try MarkdownDocument(data: data)

    XCTAssertEqual(document.text, "\u{201C}hi\u{201D}")
  }

  func testUndefinedCP1252BytesStillOpen() throws {
    // 0x81 is undefined in Windows-1252; the file must still open.
    let document = try MarkdownDocument(data: Data([0x61, 0x81, 0x62]))

    XCTAssertEqual(document.text.count, 3)
  }

  func testEmptyFileOpens() throws {
    XCTAssertEqual(try MarkdownDocument(data: Data()).text, "")
  }

  func testSupportsMarkdownExtensions() {
    XCTAssertTrue(UTType.minimarkMarkdown.tags[.filenameExtension]?.contains("md") == true)
    XCTAssertTrue(UTType.minimarkMarkdownLong.tags[.filenameExtension]?.contains("markdown") == true)
  }
}
