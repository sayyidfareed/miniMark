import AppKit
import Foundation
import SwiftUI
import WebKit

struct MarkdownPreview: View {
  let markdown: String
  let fileURL: URL?

  var body: some View {
    MarkdownWebPreview(markdown: markdown, baseURL: baseURL)
      .background(Color(nsColor: .textBackgroundColor))
  }

  private var baseURL: URL? {
    fileURL?.deletingLastPathComponent()
  }
}

struct MarkdownPreviewHTMLRenderer {
  private enum TableAlignment {
    case left
    case center
    case right
  }

  static func htmlDocument(for markdown: String, baseURL: URL?) -> String {
    let body = renderBodyHTML(for: markdown, baseURL: baseURL)
    let baseElement = baseURL.map { #"<base href="\#($0.absoluteString)">"# } ?? ""

    return """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      \(baseElement)
      <style>
        :root {
          color-scheme: light dark;
          --text: #111111;
          --muted: #646464;
          --border: #d8d8d8;
          --code-bg: #f5f5f5;
          --page-bg: #ffffff;
          --link: #0969da;
        }

        @media (prefers-color-scheme: dark) {
          :root {
            --text: #f2f2f2;
            --muted: #a6a6a6;
            --border: #3f3f3f;
            --code-bg: #242424;
            --page-bg: #1e1e1e;
            --link: #6aa7ff;
          }
        }

        html,
        body {
          min-height: 100%;
          margin: 0;
          background: var(--page-bg);
          color: var(--text);
          font: 16px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
        }

        body {
          box-sizing: border-box;
          margin: 0;
          padding: 0;
          overflow-wrap: break-word;
        }

        .content {
          box-sizing: border-box;
          max-width: 780px;
          margin: 0 auto;
          padding: 8px 18px 20px;
        }

        .content > *:first-child {
          margin-top: 0;
        }

        h1,
        h2,
        h3,
        h4,
        h5,
        h6 {
          line-height: 1.25;
          margin: 18px 0 8px;
          font-weight: 650;
        }

        h1,
        h2 {
          padding-bottom: 0.2em;
          border-bottom: 1px solid var(--border);
        }

        h1 { font-size: 1.85em; }
        h2 { font-size: 1.4em; }
        h3 { font-size: 1.2em; }

        p,
        ul,
        ol,
        blockquote,
        pre,
        table {
          margin-top: 0;
          margin-bottom: 10px;
        }

        ul,
        ol {
          padding-left: 1.6em;
        }

        li + li {
          margin-top: 2px;
        }

        a {
          color: var(--link);
          text-decoration: none;
        }

        a:hover {
          text-decoration: underline;
        }

        img {
          max-width: 100%;
          height: auto;
        }

        code {
          padding: 0.15em 0.35em;
          border-radius: 4px;
          background: var(--code-bg);
          font-family: "SF Mono", Menlo, Consolas, monospace;
          font-size: 0.88em;
        }

        pre {
          overflow-x: auto;
          padding: 12px 14px;
          border-radius: 8px;
          background: var(--code-bg);
        }

        pre code {
          padding: 0;
          background: transparent;
          font-size: 0.86em;
        }

        .codeblock {
          margin: 0 0 10px;
          border: 1px solid var(--border);
          border-radius: 8px;
          overflow: hidden;
          background: var(--code-bg);
        }

        .codeblock-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: 12px;
          padding: 4px 6px 4px 12px;
          border-bottom: 1px solid var(--border);
          background: rgba(0, 0, 0, 0.025);
          font-family: "SF Mono", Menlo, Consolas, monospace;
          font-size: 11px;
          letter-spacing: 0.02em;
          user-select: none;
        }

        @media (prefers-color-scheme: dark) {
          .codeblock-header {
            background: rgba(255, 255, 255, 0.04);
          }
        }

        .codeblock-lang {
          color: var(--muted);
          font-weight: 600;
          text-transform: lowercase;
        }

        .codeblock-copy {
          appearance: none;
          position: relative;
          flex: 0 0 auto;
          width: 24px;
          height: 24px;
          margin: 0;
          padding: 0;
          border: 0;
          border-radius: 4px;
          background: transparent;
          color: var(--muted);
          cursor: pointer;
          transition: background 120ms ease, color 120ms ease;
        }

        .codeblock-copy::before,
        .codeblock-copy::after {
          position: absolute;
          box-sizing: border-box;
          content: "";
          transition: opacity 120ms ease, transform 120ms ease;
        }

        .codeblock-copy::before {
          width: 9px;
          height: 11px;
          top: 7px;
          left: 9px;
          border: 1.5px solid currentColor;
          border-radius: 2px;
        }

        .codeblock-copy::after {
          width: 9px;
          height: 11px;
          top: 5px;
          left: 7px;
          border: 1.5px solid currentColor;
          border-radius: 2px;
          background: var(--code-bg);
        }

        .codeblock-copy:hover {
          background: rgba(0, 0, 0, 0.06);
          color: var(--text);
        }

        @media (prefers-color-scheme: dark) {
          .codeblock-copy:hover {
            background: rgba(255, 255, 255, 0.08);
          }
        }

        .codeblock-copy.is-copied {
          color: #1a7f37;
        }

        .codeblock-copy.is-copied::before {
          width: 12px;
          height: 7px;
          top: 7px;
          left: 6px;
          border-top: 0;
          border-right: 0;
          border-bottom-width: 2px;
          border-left-width: 2px;
          border-radius: 0;
          transform: rotate(-45deg);
        }

        .codeblock-copy.is-copied::after {
          opacity: 0;
          transform: scale(0.8);
        }

        @media (prefers-color-scheme: dark) {
          .codeblock-copy.is-copied {
            color: #4ac26b;
          }
        }

        .codeblock pre {
          margin: 0;
          border: 0;
          border-radius: 0;
          background: transparent;
        }

        blockquote {
          padding-left: 1em;
          color: var(--muted);
          border-left: 0.25em solid var(--border);
        }

        table {
          width: 100%;
          border-collapse: collapse;
        }

        th,
        td {
          padding: 6px 13px;
          border: 1px solid var(--border);
        }

        th {
          font-weight: 650;
        }
      </style>
    </head>
    <body>
      <main class="content">
        \(body)
      </main>
      <script>
        (function () {
          document.addEventListener('click', function (event) {
            var button = event.target.closest('.codeblock-copy');
            if (!button) return;
            event.preventDefault();

            var block = button.closest('.codeblock');
            var code = block && block.querySelector('pre code');
            if (!code) return;

            var text = code.innerText;
            var done = function () { markCopied(button); };
            var fail = function () { fallbackCopy(text, button); };

            if (navigator.clipboard && navigator.clipboard.writeText) {
              navigator.clipboard.writeText(text).then(done, fail);
            } else {
              fallbackCopy(text, button);
            }
          });

          function markCopied(button) {
            if (!button.dataset.label) {
              button.dataset.label = button.getAttribute('aria-label') || 'Copy code';
            }
            button.setAttribute('aria-label', 'Copied');
            button.setAttribute('title', 'Copied');
            button.classList.add('is-copied');
            clearTimeout(button._resetTimer);
            button._resetTimer = setTimeout(function () {
              button.setAttribute('aria-label', button.dataset.label);
              button.setAttribute('title', button.dataset.label);
              button.classList.remove('is-copied');
            }, 2200);
          }

          function fallbackCopy(text, button) {
            var area = document.createElement('textarea');
            area.value = text;
            area.setAttribute('readonly', '');
            area.style.position = 'fixed';
            area.style.opacity = '0';
            document.body.appendChild(area);
            area.select();
            try { document.execCommand('copy'); markCopied(button); } catch (e) {}
            document.body.removeChild(area);
          }
        })();
      </script>
    </body>
    </html>
    """
  }

  private static func renderBodyHTML(for markdown: String, baseURL: URL?) -> String {
    let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")

    var output: [String] = []
    var paragraph: [String] = []
    var listKind: String?
    var codeFence: (language: String, lines: [String])?
    var index = 0

    func closeList() {
      guard let kind = listKind else { return }
      output.append("</\(kind)>")
      listKind = nil
    }

    func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      output.append("<p>\(renderInline(paragraph.joined(separator: " "), baseURL: baseURL))</p>")
      paragraph.removeAll()
    }

    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if var fence = codeFence {
        if trimmed.hasPrefix("```") {
          output.append(renderCodeBlock(language: fence.language, content: fence.lines.joined(separator: "\n")))
          codeFence = nil
        } else {
          fence.lines.append(line)
          codeFence = fence
        }
        index += 1
        continue
      }

      if trimmed.isEmpty {
        flushParagraph()
        closeList()
        index += 1
        continue
      }

      if trimmed.hasPrefix("```") {
        flushParagraph()
        closeList()
        let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        codeFence = (language, [])
        index += 1
        continue
      }

      if isRawHTMLBlockStart(trimmed) {
        flushParagraph()
        closeList()
        let rawBlock = collectRawHTMLBlock(from: lines, startingAt: index)
        output.append(rawBlock.html)
        index = rawBlock.nextIndex
        continue
      }

      if let table = markdownTable(from: lines, startingAt: index, baseURL: baseURL) {
        flushParagraph()
        closeList()
        output.append(table.html)
        index = table.nextIndex
        continue
      }

      if let heading = markdownHeading(from: trimmed) {
        flushParagraph()
        closeList()
        output.append("<h\(heading.level)>\(renderInline(heading.text, baseURL: baseURL))</h\(heading.level)>")
        index += 1
        continue
      }

      if let item = unorderedListItem(from: trimmed) {
        flushParagraph()
        if listKind != "ul" {
          closeList()
          listKind = "ul"
          output.append("<ul>")
        }
        output.append("<li>\(renderInline(item, baseURL: baseURL))</li>")
        index += 1
        continue
      }

      if let item = orderedListItem(from: trimmed) {
        flushParagraph()
        if listKind != "ol" {
          closeList()
          listKind = "ol"
          output.append("<ol>")
        }
        output.append("<li>\(renderInline(item, baseURL: baseURL))</li>")
        index += 1
        continue
      }

      if trimmed.hasPrefix(">") {
        flushParagraph()
        closeList()
        let quote = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        output.append("<blockquote><p>\(renderInline(String(quote), baseURL: baseURL))</p></blockquote>")
        index += 1
        continue
      }

      closeList()
      paragraph.append(trimmed)
      index += 1
    }

    if let fence = codeFence {
      output.append(renderCodeBlock(language: fence.language, content: fence.lines.joined(separator: "\n")))
    }
    flushParagraph()
    closeList()

    return output.joined(separator: "\n")
  }

  private static func renderCodeBlock(language: String, content: String) -> String {
    let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
    let label = trimmedLanguage.isEmpty ? "plain text" : trimmedLanguage
    let languageClass = trimmedLanguage.isEmpty ? "" : #" class="language-\#(escapeHTMLAttribute(trimmedLanguage))""#
    let body = escapeHTML(content)

    return """
    <div class="codeblock">
      <div class="codeblock-header">
        <span class="codeblock-lang">\(escapeHTML(label))</span>
        <button type="button" class="codeblock-copy" aria-label="Copy code" title="Copy code"></button>
      </div>
      <pre><code\(languageClass)>\(body)</code></pre>
    </div>
    """
  }

  private static func markdownTable(
    from lines: [String],
    startingAt index: Int,
    baseURL: URL?
  ) -> (html: String, nextIndex: Int)? {
    guard
      index + 1 < lines.count,
      let headers = tableCells(from: lines[index]),
      let alignments = tableAlignments(from: lines[index + 1]),
      !headers.isEmpty,
      alignments.count == headers.count
    else {
      return nil
    }

    var rows: [[String]] = []
    var nextIndex = index + 2
    while nextIndex < lines.count, let cells = tableCells(from: lines[nextIndex]), !cells.isEmpty {
      rows.append(normalizedTableCells(cells, count: headers.count))
      nextIndex += 1
    }

    let headerHTML = zip(headers, alignments)
      .map { cell, alignment in
        "<th\(tableAlignmentAttribute(alignment))>\(renderInline(cell, baseURL: baseURL))</th>"
      }
      .joined()

    let bodyHTML = rows.map { row in
      let cells = zip(row, alignments)
        .map { cell, alignment in
          "<td\(tableAlignmentAttribute(alignment))>\(renderInline(cell, baseURL: baseURL))</td>"
        }
        .joined()
      return "<tr>\(cells)</tr>"
    }
    .joined(separator: "\n")

    let body = bodyHTML.isEmpty ? "" : "\n<tbody>\n\(bodyHTML)\n</tbody>"

    return (
      """
      <table>
      <thead>
      <tr>\(headerHTML)</tr>
      </thead>\(body)
      </table>
      """,
      nextIndex
    )
  }

  private static func tableCells(from line: String) -> [String]? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.contains("|") else { return nil }

    var content = trimmed
    if content.first == "|" {
      content.removeFirst()
    }
    if content.last == "|" {
      content.removeLast()
    }

    let cells = content.split(separator: "|", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
    return cells.count >= 2 ? cells : nil
  }

  private static func tableAlignments(from line: String) -> [TableAlignment]? {
    guard let cells = tableCells(from: line) else { return nil }
    let alignments = cells.map { cell -> TableAlignment? in
      guard firstMatch(in: cell, pattern: #"^:?-{3,}:?$"#) != nil else {
        return nil
      }

      if cell.hasPrefix(":"), cell.hasSuffix(":") {
        return .center
      }
      if cell.hasSuffix(":") {
        return .right
      }
      return .left
    }

    guard alignments.allSatisfy({ $0 != nil }) else { return nil }
    return alignments.compactMap { $0 }
  }

  private static func normalizedTableCells(_ cells: [String], count: Int) -> [String] {
    if cells.count == count {
      return cells
    }
    if cells.count > count {
      return Array(cells.prefix(count))
    }
    return cells + Array(repeating: "", count: count - cells.count)
  }

  private static func tableAlignmentAttribute(_ alignment: TableAlignment) -> String {
    switch alignment {
    case .left:
      return ""
    case .center:
      return #" style="text-align: center""#
    case .right:
      return #" style="text-align: right""#
    }
  }

  private static func isRawHTMLBlockStart(_ trimmed: String) -> Bool {
    let lowercased = trimmed.lowercased()
    return lowercased.hasPrefix("<p")
      || lowercased.hasPrefix("<div")
      || lowercased.hasPrefix("<section")
      || lowercased.hasPrefix("<figure")
      || lowercased.hasPrefix("<table")
      || lowercased.hasPrefix("<details")
      || lowercased.hasPrefix("<summary")
      || lowercased.hasPrefix("<h1")
      || lowercased.hasPrefix("<h2")
      || lowercased.hasPrefix("<h3")
      || lowercased.hasPrefix("<h4")
      || lowercased.hasPrefix("<h5")
      || lowercased.hasPrefix("<h6")
      || lowercased.hasPrefix("<img")
      || lowercased.hasPrefix("<a")
  }

  private static func collectRawHTMLBlock(from lines: [String], startingAt index: Int) -> (html: String, nextIndex: Int) {
    let start = lines[index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let closingTag: String?

    if start.hasPrefix("<p") {
      closingTag = "</p>"
    } else if start.hasPrefix("<div") {
      closingTag = "</div>"
    } else if start.hasPrefix("<section") {
      closingTag = "</section>"
    } else if start.hasPrefix("<figure") {
      closingTag = "</figure>"
    } else if start.hasPrefix("<table") {
      closingTag = "</table>"
    } else if start.hasPrefix("<details") {
      closingTag = "</details>"
    } else if start.hasPrefix("<summary") {
      closingTag = "</summary>"
    } else {
      closingTag = nil
    }

    guard let closingTag, !start.contains(closingTag) else {
      return (lines[index], index + 1)
    }

    var block = [lines[index]]
    var nextIndex = index + 1
    while nextIndex < lines.count {
      block.append(lines[nextIndex])
      if lines[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains(closingTag) {
        nextIndex += 1
        break
      }
      nextIndex += 1
    }

    return (block.joined(separator: "\n"), nextIndex)
  }

  private static func markdownHeading(from trimmed: String) -> (level: Int, text: String)? {
    let match = firstMatch(in: trimmed, pattern: #"^(#{1,6})\s+(.+)$"#)
    guard
      let match,
      let markerRange = Range(match.range(at: 1), in: trimmed),
      let textRange = Range(match.range(at: 2), in: trimmed)
    else { return nil }

    return (trimmed[markerRange].count, String(trimmed[textRange]))
  }

  private static func unorderedListItem(from trimmed: String) -> String? {
    let match = firstMatch(in: trimmed, pattern: #"^[-*+]\s+(.+)$"#)
    guard let match, let range = Range(match.range(at: 1), in: trimmed) else { return nil }
    return String(trimmed[range])
  }

  private static func orderedListItem(from trimmed: String) -> String? {
    let match = firstMatch(in: trimmed, pattern: #"^\d+[.)]\s+(.+)$"#)
    guard let match, let range = Range(match.range(at: 1), in: trimmed) else { return nil }
    return String(trimmed[range])
  }

  private static func renderInline(_ markdown: String, baseURL: URL?) -> String {
    var html = escapeHTML(markdown)

    html = replacingMatches(in: html, pattern: #"`([^`]+)`"#) { match in
      "<code>\(match.capture(1, in: html) ?? "")</code>"
    }
    html = replacingMatches(in: html, pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) { match in
      let alt = match.capture(1, in: html) ?? ""
      let source = match.capture(2, in: html) ?? ""
      let previewSource = previewImageSource(for: source, baseURL: baseURL) ?? source
      return #"<img src="\#(escapeHTMLAttribute(previewSource))" alt="\#(escapeHTMLAttribute(alt))">"#
    }
    html = replacingMatches(in: html, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) { match in
      let label = match.capture(1, in: html) ?? ""
      let destination = match.capture(2, in: html) ?? ""
      return #"<a href="\#(escapeHTMLAttribute(destination))">\#(label)</a>"#
    }
    html = replacingMatches(in: html, pattern: #"\*\*([^*]+)\*\*"#) { match in
      "<strong>\(match.capture(1, in: html) ?? "")</strong>"
    }
    html = replacingMatches(in: html, pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#) { match in
      "<em>\(match.capture(1, in: html) ?? "")</em>"
    }

    return html
  }

  private static func escapeHTML(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }

  private static func escapeHTMLAttribute(_ text: String) -> String {
    escapeHTML(text)
      .replacingOccurrences(of: "\"", with: "&quot;")
  }

  private static func previewImageSource(for source: String, baseURL: URL?) -> String? {
    guard
      let baseURL,
      baseURL.isFileURL,
      let fileURL = localImageURL(for: unescapeHTMLAttribute(source), baseURL: baseURL),
      let mimeType = imageMIMEType(for: fileURL.pathExtension),
      let data = try? Data(contentsOf: fileURL)
    else {
      return nil
    }

    return "data:\(mimeType);base64,\(data.base64EncodedString())"
  }

  private static func localImageURL(for source: String, baseURL: URL) -> URL? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    let bareSource = trimmingMarkdownDestinationDelimiters(from: trimmed)
    guard
      !bareSource.isEmpty,
      !bareSource.hasPrefix("/"),
      !bareSource.hasPrefix("//"),
      URLComponents(string: bareSource)?.scheme == nil
    else {
      return nil
    }

    let path = bareSource.split(separator: "#", maxSplits: 1).first.map(String.init) ?? bareSource
    let pathWithoutQuery = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
    guard !pathWithoutQuery.isEmpty else { return nil }

    let decodedPath = pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery
    let rootURL = baseURL.standardizedFileURL.resolvingSymlinksInPath()
    let fileURL = URL(fileURLWithPath: decodedPath, relativeTo: rootURL)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"

    guard
      fileURL.path.hasPrefix(rootPath),
      FileManager.default.fileExists(atPath: fileURL.path)
    else {
      return nil
    }

    return fileURL
  }

  private static func trimmingMarkdownDestinationDelimiters(from source: String) -> String {
    guard source.hasPrefix("<"), source.hasSuffix(">"), source.count >= 2 else {
      return source
    }

    return String(source.dropFirst().dropLast())
  }

  private static func imageMIMEType(for pathExtension: String) -> String? {
    switch pathExtension.lowercased() {
    case "png":
      return "image/png"
    case "jpg", "jpeg":
      return "image/jpeg"
    case "gif":
      return "image/gif"
    case "webp":
      return "image/webp"
    case "svg":
      return "image/svg+xml"
    case "bmp":
      return "image/bmp"
    case "tif", "tiff":
      return "image/tiff"
    case "ico":
      return "image/x-icon"
    default:
      return nil
    }
  }

  private static func unescapeHTMLAttribute(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&amp;", with: "&")
  }

  private static func firstMatch(in text: String, pattern: String) -> NSTextCheckingResult? {
    regularExpression(for: pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
  }

  private static func replacingMatches(
    in text: String,
    pattern: String,
    transform: (NSTextCheckingResult) -> String
  ) -> String {
    let regex = regularExpression(for: pattern)
    var result = ""
    var currentIndex = text.startIndex

    for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
      guard let matchRange = Range(match.range, in: text) else { continue }
      result += text[currentIndex..<matchRange.lowerBound]
      result += transform(match)
      currentIndex = matchRange.upperBound
    }

    result += text[currentIndex...]
    return result
  }

  private static func regularExpression(for pattern: String) -> NSRegularExpression {
    do {
      return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    } catch {
      preconditionFailure("Invalid regular expression: \(pattern)")
    }
  }
}

private extension NSTextCheckingResult {
  func capture(_ index: Int, in text: String) -> String? {
    guard index < numberOfRanges, let range = Range(range(at: index), in: text) else {
      return nil
    }
    return String(text[range])
  }
}

private struct MarkdownWebPreview: NSViewRepresentable {
  let markdown: String
  let baseURL: URL?

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.allowsMagnification = true
    webView.underPageBackgroundColor = .clear
    context.coordinator.webView = webView
    loadPreview(in: webView, coordinator: context.coordinator)
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {
    loadPreview(in: webView, coordinator: context.coordinator)
  }

  private func loadPreview(in webView: WKWebView, coordinator: Coordinator) {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: baseURL)
    guard html != coordinator.currentHTML else { return }

    coordinator.currentHTML = html
    webView.loadHTMLString(html, baseURL: baseURL)
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    weak var webView: WKWebView?
    var currentHTML = ""

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
        decisionHandler(.allow)
        return
      }

      if url.fragment != nil, url.scheme == "file" || url.scheme == "about" {
        decisionHandler(.allow)
      } else {
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
      }
    }
  }
}
