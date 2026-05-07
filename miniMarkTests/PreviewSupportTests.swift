import MarkdownUI
import XCTest
@testable import miniMark

final class PreviewSupportTests: XCTestCase {
  func testReadmeLocalImageReferencesExist() throws {
    let repositoryURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let readmeURL = repositoryURL.appendingPathComponent("README.md")
    let readme = try String(contentsOf: readmeURL, encoding: .utf8)
    let regex = try NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#)
    let matches = regex.matches(in: readme, range: NSRange(readme.startIndex..., in: readme))
    XCTAssertFalse(matches.isEmpty)

    for match in matches {
      guard let range = Range(match.range(at: 1), in: readme) else { continue }

      let rawPath = String(readme[range])
      guard
        !rawPath.hasPrefix("/"),
        URLComponents(string: rawPath)?.scheme == nil
      else {
        continue
      }

      let path = rawPath
        .split(separator: "#", maxSplits: 1).first.map(String.init) ?? rawPath
      let pathWithoutQuery = path
        .split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
      let imageURL = repositoryURL.appendingPathComponent(pathWithoutQuery)

      XCTAssertTrue(
        FileManager.default.fileExists(atPath: imageURL.path),
        "Missing README image reference: \(pathWithoutQuery)"
      )
    }
  }

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

  func testPreviewRendererScalesPreviewTextWithWindowWidth() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: "# Title", baseURL: nil)

    XCTAssertTrue(html.contains("--preview-font-size: clamp("))
    XCTAssertTrue(html.contains("--preview-content-width: clamp("))
    XCTAssertTrue(html.contains("font: var(--preview-font-size)/1.55"))
    XCTAssertTrue(html.contains("width: min(100%, var(--preview-content-width));"))
  }

  func testPreviewRendererEmbedsRelativeRawHTMLImagesFromBaseDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("miniMarkPreviewSupportTests-\(UUID().uuidString)", isDirectory: true)
    let assetsDirectory = directory.appendingPathComponent("docs/assets", isDirectory: true)
    try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let imageURL = assetsDirectory.appendingPathComponent("icon.png")
    let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
    try pngData.write(to: imageURL)

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: #"<p><img src="docs/assets/icon.png" alt="Icon"></p>"#,
      baseURL: directory
    )

    XCTAssertTrue(html.contains(#"<img src="data:image/png;base64,"#))
    XCTAssertTrue(html.contains(pngData.base64EncodedString()))
    XCTAssertFalse(html.contains(#"src="docs/assets/icon.png""#))
  }

  func testPreviewRendererEmbedsRelativeMarkdownImagesFromBaseDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("miniMarkPreviewSupportTests-\(UUID().uuidString)", isDirectory: true)
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

  func testPreviewRendererEmbedsNestedImagesFromDocumentDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("miniMarkPreviewSupportTests-\(UUID().uuidString)", isDirectory: true)
    let resourcesDirectory = directory.appendingPathComponent("miniMark/Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let imageURL = resourcesDirectory.appendingPathComponent("screenshot_source.png")
    let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
    try pngData.write(to: imageURL)

    let documentURL = directory.appendingPathComponent("README.md")
    let baseURL = URL(fileURLWithPath: documentURL.deletingLastPathComponent().path)
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: "![Source mode](miniMark/Resources/screenshot_source.png)",
      baseURL: baseURL
    )

    XCTAssertTrue(html.contains(#"<base href="\#(directory.absoluteString)""#))
    XCTAssertTrue(html.contains(#"<img src="data:image/png;base64,"#))
    XCTAssertTrue(html.contains(pngData.base64EncodedString()))
    XCTAssertFalse(html.contains(#"src="miniMark/Resources/screenshot_source.png""#))
  }

  func testPreviewRendererRendersTablesAndEmbedsRelativeImagesInCells() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("miniMarkPreviewSupportTests-\(UUID().uuidString)", isDirectory: true)
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

  func testPreviewRendererRendersMermaidFenceAsDiagramContainer() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: """
      ```mermaid
      graph TD
      A-->B
      ```
      """,
      baseURL: nil
    )

    XCTAssertTrue(html.contains(#"<pre class="mermaid">graph TD"#))
    XCTAssertTrue(html.contains("A--&gt;B"))
    XCTAssertTrue(html.contains("mermaid.initialize"))
    XCTAssertTrue(html.contains("securityLevel: 'strict'"))
    XCTAssertTrue(html.contains("querySelector: '.mermaid'"))
    XCTAssertFalse(html.contains(#"class="language-mermaid""#))
  }

  func testPreviewRendererOnlyTreatsExactMermaidLanguageAsDiagram() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: """
      ```mermaid extra
      graph TD
      A-->B
      ```
      """,
      baseURL: nil
    )

    XCTAssertTrue(html.contains(#"class="language-mermaid extra""#))
    XCTAssertTrue(html.contains("A--&gt;B"))
    XCTAssertFalse(html.contains(#"<pre class="mermaid">"#))
    XCTAssertFalse(html.contains("mermaid.initialize"))
  }

  func testPreviewRendererDoesNotIncludeMermaidPayloadWithoutMermaidFence() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: """
      ```swift
      let value = 42
      ```
      """,
      baseURL: nil
    )

    XCTAssertFalse(html.contains(#"<pre class="mermaid">"#))
    XCTAssertFalse(html.contains("mermaid.initialize"))
    XCTAssertFalse(html.contains("globalThis[\"mermaid\"]"))
  }

  func testPreviewRendererEscapesMermaidSource() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: """
      ```mermaid
      graph TD
      A[<script>alert(1)</script>]-->B
      ```
      """,
      baseURL: nil
    )

    XCTAssertTrue(html.contains("A[&lt;script&gt;alert(1)&lt;/script&gt;]--&gt;B"))
    XCTAssertFalse(html.contains("A[<script>alert(1)</script>]"))
  }

  func testRichTextRendererKeepsMermaidAsReadableCodeBlock() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: """
      ```mermaid
      graph TD
      A-->B
      ```
      """,
      baseURL: nil,
      mode: .richText
    )

    XCTAssertTrue(html.contains(#"class="language-mermaid""#))
    XCTAssertTrue(html.contains("A--&gt;B"))
    XCTAssertFalse(html.contains(#"<pre class="mermaid">"#))
    XCTAssertFalse(html.contains("mermaid.initialize"))
  }

  func testHighlighterReturnsTextForCommonLanguage() {
    let highlighter = HighlightrCodeSyntaxHighlighter(themeName: "xcode")
    _ = highlighter.highlightCode("let value = 42", language: "swift")
  }
}
