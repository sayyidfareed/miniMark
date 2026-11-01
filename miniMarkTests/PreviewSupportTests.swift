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

  func testStrikethroughRendersDeletedText() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: "This is ~~old~~ text", baseURL: nil)

    XCTAssertTrue(html.contains("<del>old</del>"))
  }

  func testTaskListsRenderCheckboxes() {
    let markdown = """
    - [x] Done
    - [ ] Open
    - Plain item
    """

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: nil)

    XCTAssertTrue(html.contains(#"<li class="task-list-item"><input type="checkbox" checked disabled> Done</li>"#))
    XCTAssertTrue(html.contains(#"<li class="task-list-item"><input type="checkbox" disabled> Open</li>"#))
    XCTAssertTrue(html.contains("<li>Plain item</li>"))
  }

  func testTaskListsUseGlyphsInRichText() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: "- [x] Done\n- [ ] Open",
      baseURL: nil,
      mode: .richText
    )

    XCTAssertTrue(html.contains("\u{2611} Done"))
    XCTAssertTrue(html.contains("\u{2610} Open"))
    XCTAssertFalse(html.contains("<input"))
  }

  func testFootnotesRenderNumberedReferencesAndNotes() throws {
    let markdown = """
    First claim.[^a] Second claim.[^b]

    [^b]: Second note.
    [^a]: First note
        continues here.
    """

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: nil)

    XCTAssertTrue(html.contains(#"<section class="footnotes">"#))
    XCTAssertTrue(html.contains(#"id="fnref-a""#))
    XCTAssertTrue(html.contains("First note continues here."))
    let first = try XCTUnwrap(html.range(of: #"id="fn-a""#))
    let second = try XCTUnwrap(html.range(of: #"id="fn-b""#))
    XCTAssertLessThan(first.lowerBound, second.lowerBound)
  }

  func testUnknownFootnoteReferenceStaysLiteral() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: "No note here.[^missing]", baseURL: nil)

    XCTAssertTrue(html.contains("[^missing]"))
    XCTAssertFalse(html.contains(#"<section class="footnotes">"#))
  }

  func testFootnoteMarkerInsideCodeSpanStaysLiteral() {
    let markdown = """
    Use `[^a]` for notes.[^a]

    [^a]: A note.
    """

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: nil)

    XCTAssertTrue(html.contains("<code>[^a]</code>"))
    XCTAssertTrue(html.contains(#"<section class="footnotes">"#))
  }

  func testInlineMathIsMarkedForKaTeXAndNotEmphasized() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: #"Euler: $e^{i\pi}+1=0$ and $a*b*c$"#,
      baseURL: nil
    )

    XCTAssertTrue(html.contains(#"data-tex="e^{i\pi}+1=0""#))
    XCTAssertTrue(html.contains(#"data-tex="a*b*c""#))
    XCTAssertFalse(html.contains("<em>b</em>"))
  }

  func testCurrencyAmountsAreNotTreatedAsMath() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: "It costs $5 and $10 today.", baseURL: nil)

    XCTAssertFalse(html.contains(#"class="math-inline""#))
    XCTAssertTrue(html.contains("It costs $5 and $10 today."))
  }

  func testDisplayMathBlocksRenderOnOneLineAndAcrossLines() {
    let markdown = """
    $$x^2$$

    $$
    a + b
    = c
    $$
    """

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: nil)

    XCTAssertEqual(html.components(separatedBy: #"class="math-block" data-tex="#).count - 1, 2)
    XCTAssertTrue(html.contains(#"data-tex="x^2""#))
    XCTAssertTrue(html.contains("a + b\n= c"))
  }

  func testMathInsideCodeSpanStaysCode() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: "Write `$x$` in code.", baseURL: nil)

    XCTAssertTrue(html.contains("<code>$x$</code>"))
    XCTAssertFalse(html.contains(#"class="math-inline""#))
  }

  func testRichTextMathKeepsPlainDelimiters() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: "Inline $x^2$ here.", baseURL: nil, mode: .richText)

    XCTAssertTrue(html.contains("$x^2$"))
    XCTAssertFalse(html.contains("data-tex"))
  }

  func testPlaceholderMarkersInDocumentTextCannotInjectSegments() {
    let markdown = "Use `code` then \u{E000}0\u{E001} here."

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: nil)

    XCTAssertEqual(html.components(separatedBy: "<code>code</code>").count - 1, 1)
  }

  func testCodeBlocksKeepTheLanguageClassTheHighlighterReads() {
    let markdown = """
    ```swift
    let value = 42
    ```
    """

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: nil)

    XCTAssertTrue(html.contains(#"<code class="language-swift">"#))
  }

  func testLinkDestinationInCodeSpanCannotInjectAttributes() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: #"[x](`" onclick="alert(1)" data-x="`)"#,
      baseURL: nil
    )

    XCTAssertFalse(html.contains(#" onclick=""#))
    XCTAssertFalse(html.contains(#"data-x=""#))
  }

  func testImageAltInCodeSpanCannotInjectAttributes() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: #"![`" onerror="alert(1)" x="`](a.png)"#,
      baseURL: nil
    )

    XCTAssertFalse(html.contains(#" onerror=""#))
  }

  func testUnsafeMarkdownLinkDestinationsBecomePlainText() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: "[click](javascript:alert(1))", baseURL: nil)

    XCTAssertFalse(html.contains(#"href="javascript"#))
    XCTAssertTrue(html.contains("click"))
  }

  func testRawHTMLScriptElementsAreRemovedWithTheirContents() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: "<div><script>alert(1)</script><p>kept</p></div>",
      baseURL: nil
    )

    XCTAssertFalse(html.contains("alert(1)"))
    XCTAssertTrue(html.contains("<p>kept</p>"))
  }

  func testRawHTMLEventHandlersAndScriptAddressesAreDropped() {
    let markdown = """
    <p><img src="x.png" onerror="alert(1)"><a href="javascript:alert(2)" onclick="alert(3)">a</a><a href="java&#x73;cript:alert(4)">b</a><a href=" JaVa\tScRiPt:alert(5)">c</a></p>
    """

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: nil)

    XCTAssertFalse(html.contains("onerror"))
    XCTAssertFalse(html.contains("onclick"))
    XCTAssertFalse(html.lowercased().contains("javascript:"))
    XCTAssertFalse(html.contains("alert("))
    XCTAssertTrue(html.contains(#"<img src="x.png""#))
  }

  func testRawHTMLUnknownTagsAreShownAsText() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: "<div><custom x=\"1\">hi</custom></div>", baseURL: nil)

    XCTAssertTrue(html.contains("&lt;custom"))
    XCTAssertFalse(html.contains("<custom"))
  }

  func testRawHTMLKeepsReadmeLayoutAttributes() {
    let markdown = """
    <details open><summary>More</summary><table width="100%"><tr><td colspan="2" align="center">cell</td></tr></table></details>
    """

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: nil)

    XCTAssertTrue(html.contains("<details open>"))
    XCTAssertTrue(html.contains(#"<table width="100%">"#))
    XCTAssertTrue(html.contains(#"colspan="2""#))
  }

  func testPageHasContentSecurityPolicyAndEveryScriptCarriesTheNonce() {
    let markdown = """
    ```swift
    let value = 1
    ```

    Text.[^a] And $x^2$.

    [^a]: Note.
    """

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: nil)

    XCTAssertTrue(html.contains("Content-Security-Policy"))
    XCTAssertTrue(html.contains("script-src 'nonce-"))
    // Real tags only: a bundled library mentions "<script" inside its own source text, followed by "(".
    XCTAssertFalse(html.contains("<script>"), "script tag without a nonce")
    for part in html.components(separatedBy: "<script ").dropFirst() {
      XCTAssertTrue(part.hasPrefix("nonce=\""), "script tag without a nonce")
    }
  }

  func testNestedActiveElementsRemoveEverythingInsideThem() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: "<div><svg><svg></svg><p>must disappear</p></svg><p>kept</p></div>",
      baseURL: nil
    )

    XCTAssertFalse(html.contains("must disappear"))
    XCTAssertTrue(html.contains("<p>kept</p>"))
  }

  func testUnclosedActiveElementRemovesTheRestOfTheBlock() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: "<div><p>before</p><script>alert(1)<p>afterxyzmarker</p></div>",
      baseURL: nil
    )

    XCTAssertTrue(html.contains("<p>before</p>"))
    XCTAssertFalse(html.contains("alert(1)"))
    XCTAssertFalse(html.contains("afterxyzmarker"))
  }

  func testSelfClosingSyntaxDoesNotSkipRemovalOfRawTextElements() {
    for tag in ["script", "style", "iframe", "noscript"] {
      let closed = MarkdownPreviewHTMLRenderer.htmlDocument(
        for: "<div><\(tag)/>must disappear</\(tag)><p>kept</p></div>",
        baseURL: nil
      )
      XCTAssertFalse(closed.contains("must disappear"), "<\(tag)/> kept its contents")
      XCTAssertTrue(closed.contains("<p>kept</p>"), "<\(tag)/> removed too much")

      let unclosed = MarkdownPreviewHTMLRenderer.htmlDocument(
        for: "<div><p>before</p><\(tag)/>must disappear<p>afterxyzmarker</p></div>",
        baseURL: nil
      )
      XCTAssertFalse(unclosed.contains("must disappear"), "unclosed <\(tag)/> kept its contents")
      XCTAssertFalse(unclosed.contains("afterxyzmarker"), "unclosed <\(tag)/> did not drop the rest")
    }
  }

  func testSelfClosingSvgIsEmptyButFormStillOpens() {
    let svg = MarkdownPreviewHTMLRenderer.htmlDocument(for: "<div><svg/><p>kept</p></div>", baseURL: nil)
    XCTAssertTrue(svg.contains("<p>kept</p>"))

    let form = MarkdownPreviewHTMLRenderer.htmlDocument(for: "<div><form/>must disappear</form><p>kept</p></div>", baseURL: nil)
    XCTAssertFalse(form.contains("must disappear"))
    XCTAssertTrue(form.contains("<p>kept</p>"))
  }
}
