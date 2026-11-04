import XCTest
@testable import miniMark

final class MarkdownExportTests: XCTestCase {
  func testExportHTMLIsStandaloneAndRemovesPreviewControls() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("miniMarkExportTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let imageURL = directory.appendingPathComponent("image.png")
    let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
    try pngData.write(to: imageURL)

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: """
      # Export Me

      ![Tiny image](image.png)

      ```swift
      let value = 42
      ```
      """,
      baseURL: directory,
      mode: .export
    )

    XCTAssertTrue(html.contains(#"<body class="export-document">"#))
    XCTAssertTrue(html.contains("@media print"))
    XCTAssertTrue(html.contains("table-layout: fixed"))
    XCTAssertTrue(html.contains(#"<img src="data:image/png;base64,"#))
    XCTAssertTrue(html.contains(pngData.base64EncodedString()))
    XCTAssertFalse(html.contains(#"class="codeblock-copy""#))
    XCTAssertFalse(html.contains("<script>"))
  }

  func testExportHTMLIncludesStandaloneMermaidPayloadWhenNeeded() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: """
      # Diagram

      ```mermaid
      graph TD
      A-->B
      ```
      """,
      baseURL: nil,
      mode: .export
    )

    XCTAssertTrue(html.contains(#"<pre class="mermaid">graph TD"#))
    XCTAssertTrue(html.contains("A--&gt;B"))
    XCTAssertTrue(html.contains("globalThis[\"mermaid\"]"))
    XCTAssertTrue(html.contains("mermaid.initialize"))
    XCTAssertTrue(html.contains("securityLevel: 'strict'"))
    XCTAssertFalse(html.contains(#"class="codeblock-copy""#))
  }

  func testPrintHTMLRendersMermaidBeforePDFOutput() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: """
      ```mermaid
      graph TD
      A-->B
      ```
      """,
      baseURL: nil,
      mode: .print
    )

    XCTAssertTrue(html.contains(#"<pre class="mermaid">graph TD"#))
    XCTAssertTrue(html.contains("mermaid.initialize"))
    XCTAssertTrue(html.contains("mermaidReady = 'pending'"))
    XCTAssertTrue(html.contains("mermaidReady = 'ready'"))
  }

  func testMermaidHTMLDefinesVisibleDarkModeLines() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: """
      ```mermaid
      sequenceDiagram
      A->>B: Hello
      ```
      """,
      baseURL: nil,
      mode: .preview
    )

    XCTAssertTrue(html.contains(".mermaid .flowchart-link"))
    XCTAssertTrue(html.contains(".mermaid .messageLine0"))
    XCTAssertTrue(html.contains("stroke: #d6dde8 !important"))
    XCTAssertTrue(html.contains("theme: isDark ? 'dark' : 'default'"))
  }

  func testRichTextHTMLUsesCompactTablesAndImageWidths() {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: """
      | Source | Preview |
      | :---: | :---: |
      | ![Source](source.png) | A long table cell that should wrap instead of forcing the document wider |
      """,
      baseURL: nil,
      mode: .richText
    )

    XCTAssertTrue(html.contains("width: 6.45in"))
    XCTAssertTrue(html.contains(#"<table width="100%" style="width: 100%; max-width: 100%; table-layout: fixed;">"#))
    XCTAssertTrue(html.contains(#"style="text-align: center; width: 50%; overflow-wrap: anywhere; word-break: break-word; vertical-align: top;""#))
    XCTAssertTrue(html.contains(#"width="220" style="max-width: 220px; height: auto;""#))
  }

  func testPlainTextExportRendersReadableText() {
    let text = MarkdownPlainTextRenderer.plainText(
      for: """
      # Title

      A **bold** [link](https://example.com) and `code`.

      - First
      1. Second
      > Quote *here*

      | Name | Value |
      | --- | --- |
      | ![Logo](logo.png) | __Done__ |

      ```swift
      let answer = 42
      ```
      """
    )

    XCTAssertTrue(text.contains("Title"))
    XCTAssertTrue(text.contains("A bold link and code."))
    XCTAssertTrue(text.contains("- First"))
    XCTAssertTrue(text.contains("1. Second"))
    XCTAssertTrue(text.contains("> Quote here"))
    XCTAssertTrue(text.contains("Name | Value"))
    XCTAssertTrue(text.contains("Logo | Done"))
    XCTAssertTrue(text.contains("let answer = 42"))
    XCTAssertFalse(text.contains("**bold**"))
    XCTAssertFalse(text.contains("[link]"))
  }

  func testPlainTextKeepsIntrawordUnderscores() {
    let text = MarkdownPlainTextRenderer.plainText(for: "Use my_var_name and __init__ here, or _emphasis_ too.")

    XCTAssertTrue(text.contains("Use my_var_name and init here, or emphasis too."))
  }

  func testPlainTextKeepsSpacedAndIntrawordAsterisks() {
    let text = MarkdownPlainTextRenderer.plainText(for: "Compute 2 * 3 * 4 and 2*3*4 then *real* and **strong**.")

    XCTAssertTrue(text.contains("Compute 2 * 3 * 4 and 2*3*4 then real and strong."))
  }

  func testPlainTextDoesNotUnescapeLiteralEntities() {
    let text = MarkdownPlainTextRenderer.plainText(for: "Type &lt;div&gt; and AT&amp;T literally.")

    XCTAssertTrue(text.contains("Type &lt;div&gt; and AT&amp;T literally."))
  }

  func testPlainTextKeepsNestedListIndentation() {
    let text = MarkdownPlainTextRenderer.plainText(
      for: """
      - Parent
        - Child
          - Grandchild
      1. One
         1. Nested one
      """
    )

    XCTAssertTrue(text.contains("- Parent\n  - Child\n    - Grandchild"))
    XCTAssertTrue(text.contains("1. One\n   1. Nested one"))
  }

  func testPlainTextKeepsCodeVerbatim() {
    let text = MarkdownPlainTextRenderer.plainText(
      for: """
      Call `my_func(*args, **kwargs)` and `a_b_c`.

      ```python
      x = 2 * 3 * 4
      name = "**not bold**" + &lt;
          indented = _keep_
      ```
      """
    )

    XCTAssertTrue(text.contains("Call my_func(*args, **kwargs) and a_b_c."))
    XCTAssertTrue(text.contains("x = 2 * 3 * 4"))
    XCTAssertTrue(text.contains(#"name = "**not bold**" + &lt;"#))
    XCTAssertTrue(text.contains("    indented = _keep_"))
  }

  func testPlainTextBackslashEscapesLoseOnlyTheBackslash() {
    let text = MarkdownPlainTextRenderer.plainText(for: #"Literal \*stars\* and C:\path stay."#)

    XCTAssertTrue(text.contains(#"Literal *stars* and C:\path stay."#))
  }

  func testRTFExportReturnsRTFData() throws {
    let context = MarkdownExportContext(
      markdown: """
      # Title

      A small **document**.
      """,
      fileURL: nil
    )

    let data = try MarkdownExportData.makeData(for: context, format: .rtf)
    let prefix = String(data: data.prefix(6), encoding: .ascii)

    XCTAssertEqual(prefix, "{\\rtf1")
    XCTAssertGreaterThan(data.count, 20)
  }
}
