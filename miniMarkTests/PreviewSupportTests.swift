import MarkdownUI
import XCTest
@testable import miniMark

final class PreviewSupportTests: XCTestCase {
  func testMarkdownFixtureCanBePreparedForPreview() {
    let fixture = """
    # Title

    - [x] Task

    | A | B |
    | - | - |
    | 1 | 2 |

    ```swift
    let value = 42
    ```

    ![Alt](image.png)
    [Link](https://example.com)
    """

    _ = MarkdownContent(fixture)
  }

  func testPreviewRendererKeepsCommonReadmeHTMLRenderable() {
    let markdown = """
    <p align="center">
      <img src="docs/assets/venvdeck-icon.png" alt="VenvDeck app icon" width="128" height="128">
    </p>

    <h1 align="center">VenvDeck</h1>

    <p align="center">
      <strong>The macOS control room.</strong>
    </p>

    <p align="center">
      <a href="https://example.com"><strong>Download</strong></a>
      &middot;
      <a href="#build-from-source">Build from Source</a>
    </p>
    """

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: URL(fileURLWithPath: "/tmp"))

    XCTAssertTrue(html.contains("<p"))
    XCTAssertTrue(html.contains("<img"))
    XCTAssertTrue(html.contains("docs/assets/venvdeck-icon.png"))
    XCTAssertTrue(html.contains("<h1"))
    XCTAssertTrue(html.contains("VenvDeck"))
    XCTAssertTrue(html.contains("<strong>The macOS control room.</strong>"))
    XCTAssertTrue(html.contains("https://example.com"))
    XCTAssertTrue(html.contains("#build-from-source"))
    XCTAssertFalse(html.contains("&lt;p"))
    XCTAssertFalse(html.contains("&lt;img"))
  }

  func testPreviewRendererEmbedsRelativeMarkdownImagesFromBaseDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MiniMarkPreviewSupportTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let imageURL = directory.appendingPathComponent("screenshot.png")
    let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
    try pngData.write(to: imageURL)

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: "![Screenshot](screenshot.png)",
      baseURL: directory
    )

    XCTAssertTrue(html.contains(#"<img src="data:image/png;base64,"#))
    XCTAssertTrue(html.contains(pngData.base64EncodedString()))
    XCTAssertFalse(html.contains(#"src="screenshot.png""#))
  }

  func testPreviewRendererRendersTablesAndEmbedsRelativeImagesInCells() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MiniMarkPreviewSupportTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let imageURL = directory.appendingPathComponent("screenshot.png")
    let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
    try pngData.write(to: imageURL)

    let markdown = """
    | Source | Preview |
    | :---: | :---: |
    | ![Screenshot](screenshot.png) | Text |
    """

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: directory)

    XCTAssertTrue(html.contains("<table>"))
    XCTAssertTrue(html.contains("<thead>"))
    XCTAssertTrue(html.contains("<tbody>"))
    XCTAssertTrue(html.contains(#"style="text-align: center""#))
    XCTAssertTrue(html.contains(#"<img src="data:image/png;base64,"#))
    XCTAssertFalse(html.contains("| Source | Preview |"))
  }

  func testPreviewRendererLeavesRemoteMarkdownImagesAsLinks() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: "![Screenshot](https://example.com/screenshot.png)",
      baseURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
    )

    XCTAssertTrue(html.contains(#"src="https://example.com/screenshot.png""#))
    XCTAssertFalse(html.contains("data:image/png;base64,"))
  }

  func testPreviewRendererAddsLightweightCopyButtonToCodeBlocks() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: """
      ```swift
      let value = 42
      ```
      """,
      baseURL: nil
    )

    XCTAssertTrue(html.contains(#"class="codeblock-copy""#))
    XCTAssertTrue(html.contains(#"aria-label="Copy code""#))
    XCTAssertTrue(html.contains(#"title="Copy code""#))
    XCTAssertTrue(html.contains("is-copied"))
    XCTAssertTrue(html.contains("setTimeout"))
    XCTAssertFalse(html.contains(#">Copy</button>"#))
  }

  func testHighlighterReturnsTextForCommonLanguage() {
    let highlighter = HighlightrCodeSyntaxHighlighter(themeName: "xcode")
    _ = highlighter.highlightCode("let value = 42", language: "swift")
  }
}
