import AppKit
import Foundation
import SwiftUI
import WebKit

struct MarkdownPreview: View {
  let markdown: String
  let fileURL: URL?
  @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

  var body: some View {
    MarkdownWebPreview(
      markdown: markdown,
      documentURL: fileURL,
      baseURL: baseURL,
      appearanceToken: appearanceRaw
    )
      .background(Color(nsColor: .textBackgroundColor))
  }

  private var baseURL: URL? {
    fileURL.map { URL(fileURLWithPath: $0.deletingLastPathComponent().path, isDirectory: true) }
  }
}

struct MarkdownPreviewHTMLRenderer {
  enum RenderMode {
    case preview
    case export
    case print
    case richText

    var isPreview: Bool {
      self == .preview
    }

    var rendersMermaid: Bool {
      self == .preview || self == .export || self == .print
    }

    var isRichText: Bool {
      self == .richText
    }
  }

  private enum TableAlignment {
    case left
    case center
    case right
  }

  static func htmlDocument(
    for markdown: String,
    baseURL: URL?,
    mode: RenderMode = .preview
  ) -> String {
    let baseURL = baseURL.map { URL(fileURLWithPath: $0.path, isDirectory: true) }
    let body = renderBodyHTML(for: markdown, baseURL: baseURL, mode: mode)
    let baseElement = baseURL.map { #"<base href="\#($0.absoluteString)">"# } ?? ""
    let bodyClass = mode.isPreview ? "" : #" class="export-document""#
    let exportStyles = mode.isPreview ? "" : (mode.isRichText ? richTextDocumentStyles : exportDocumentStyles)
    let hasMath = !mode.isRichText && (body.contains("class=\"math-inline\"") || body.contains("class=\"math-block\""))
    let hasHighlightableCode = !mode.isRichText && body.contains("<code class=\"language-")
    let hasFootnoteLinks = !mode.isRichText && body.contains("data-scroll=")
    let script = [
      mode.isPreview ? copyButtonScript : "",
      hasFootnoteLinks ? footnoteScript : "",
      mode.rendersMermaid && containsMermaidFence(in: markdown) ? mermaidScript : "",
      hasMath ? (mathAssets ?? "") : "",
      hasHighlightableCode ? (highlightAssets ?? "") : ""
    ]
    .filter { !$0.isEmpty }
    .joined(separator: "\n")

    return """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
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
          --preview-font-size: clamp(16px, calc(14.2px + 0.22vw), 20px);
          --preview-content-width: clamp(720px, 70vw, 62em);
          --preview-inline-padding: clamp(18px, 2.2vw, 36px);
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
          font: var(--preview-font-size)/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
        }

        body {
          box-sizing: border-box;
          margin: 0;
          padding: 0;
          overflow-wrap: break-word;
        }

        .content {
          box-sizing: border-box;
          width: min(100%, var(--preview-content-width));
          margin: 0 auto;
          padding: 8px var(--preview-inline-padding) 20px;
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

        li.task-list-item {
          list-style: none;
          margin-left: -1.4em;
        }

        li.task-list-item input {
          margin: 0 0.4em 0 0;
          vertical-align: baseline;
        }

        .math-block {
          margin: 1em 0;
          overflow-x: auto;
          text-align: center;
        }

        sup.footnote-ref {
          font-size: 0.75em;
          line-height: 0;
        }

        section.footnotes {
          margin-top: 2em;
          font-size: 0.9em;
          color: var(--muted);
        }

        section.footnotes hr {
          border: 0;
          border-top: 1px solid var(--border);
          margin: 0 0 0.8em;
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

        pre.mermaid {
          overflow-x: auto;
          padding: 12px 0;
          border-radius: 0;
          background: transparent;
          text-align: center;
        }

        .mermaid svg {
          max-width: 100%;
          height: auto;
        }

        @media (prefers-color-scheme: dark) {
          .mermaid .flowchart-link,
          .mermaid .edgePath path,
          .mermaid .messageLine0,
          .mermaid .messageLine1,
          .mermaid .actor-line,
          .mermaid line,
          .mermaid polyline {
            stroke: #d6dde8 !important;
          }

          .mermaid marker path {
            fill: #d6dde8 !important;
            stroke: #d6dde8 !important;
          }
        }

        blockquote {
          padding-left: 1em;
          color: var(--muted);
          border-left: 0.25em solid var(--border);
        }

        table {
          width: 100%;
          max-width: 100%;
          table-layout: fixed;
          border-collapse: collapse;
        }

        th,
        td {
          padding: 6px 13px;
          border: 1px solid var(--border);
          box-sizing: border-box;
          overflow-wrap: anywhere;
          word-break: break-word;
          vertical-align: top;
        }

        th {
          font-weight: 650;
        }

        \(exportStyles)
      </style>
    </head>
    <body\(bodyClass)>
      <main class="content">
        \(body)
      </main>
      \(script)
    </body>
    </html>
    """
  }

  /// Only scripts that carry this per-launch value may run, so scripts written into a
  /// document (raw HTML) are blocked even if one slipped past the sanitizer.
  private static let scriptNonce = UUID().uuidString

  private static let contentSecurityPolicy =
    "default-src 'none'; script-src 'nonce-\(scriptNonce)' 'unsafe-eval'; "
    + "style-src 'unsafe-inline'; img-src data: http: https: file:; font-src data:; "
    + "connect-src 'none'; form-action 'none'; frame-src 'none'; object-src 'none'; media-src 'none'"

  private static let footnoteScript = """
      <script nonce="\(scriptNonce)">
        document.addEventListener('click', function (event) {
          var link = event.target.closest('a[data-scroll]');
          if (!link) return;
          event.preventDefault();
          var target = document.getElementById(link.getAttribute('data-scroll'));
          if (target) target.scrollIntoView();
        });
      </script>
  """

  private static let exportDocumentStyles = """
        .export-document {
          --text: #111111;
          --muted: #646464;
          --border: #d8d8d8;
          --code-bg: #f5f5f5;
          --page-bg: #ffffff;
          --link: #0757b8;
          background: #ffffff;
          color: #111111;
          font-size: 15px;
          line-height: 1.48;
        }

        .export-document .content {
          max-width: 760px;
          padding: 42px 48px 54px;
        }

        .export-document h1,
        .export-document h2,
        .export-document h3,
        .export-document h4,
        .export-document h5,
        .export-document h6 {
          margin: 20px 0 9px;
        }

        .export-document h1 { font-size: 2em; }
        .export-document h2 { font-size: 1.46em; }
        .export-document h3 { font-size: 1.22em; }

        .export-document p,
        .export-document ul,
        .export-document ol,
        .export-document blockquote,
        .export-document pre,
        .export-document table {
          margin-bottom: 12px;
        }

        .export-document ul,
        .export-document ol {
          padding-left: 1.45em;
        }

        .export-document li + li {
          margin-top: 4px;
        }

        .export-document a {
          color: #0757b8;
        }

        .export-document .codeblock-header {
          background: rgba(0, 0, 0, 0.025);
        }

        .export-document pre {
          white-space: pre-wrap;
          overflow-wrap: anywhere;
        }

        .export-document th,
        .export-document td {
          padding: 7px 10px;
          line-height: 1.34;
        }

        @media print {
          @page {
            margin: 0.72in;
          }

          html,
          body {
            background: #ffffff;
            color: #111111;
          }

          .export-document .content {
            max-width: none;
            padding: 0;
          }

          a {
            color: #111111;
          }

          h1,
          h2,
          h3,
          h4,
          h5,
          h6,
          blockquote,
          pre,
          table {
            break-inside: avoid;
          }

          pre,
          code {
            background: #f4f4f4;
          }
        }
  """

  private static let richTextDocumentStyles = """
        .export-document {
          --text: #111111;
          --muted: #646464;
          --border: #cfcfcf;
          --code-bg: #f5f5f5;
          --page-bg: #ffffff;
          --link: #0757b8;
          background: #ffffff;
          color: #111111;
          font-size: 13px;
          line-height: 1.38;
        }

        .export-document .content {
          width: 6.45in;
          max-width: 6.45in;
          margin: 0;
          padding: 0;
        }

        .export-document h1,
        .export-document h2,
        .export-document h3,
        .export-document h4,
        .export-document h5,
        .export-document h6 {
          margin: 13px 0 6px;
          line-height: 1.18;
        }

        .export-document h1 { font-size: 1.75em; }
        .export-document h2 { font-size: 1.38em; }
        .export-document h3 { font-size: 1.13em; }

        .export-document p,
        .export-document ul,
        .export-document ol,
        .export-document blockquote,
        .export-document pre,
        .export-document table {
          margin-top: 0;
          margin-bottom: 8px;
        }

        .export-document ul,
        .export-document ol {
          padding-left: 1.25em;
        }

        .export-document table {
          width: 6.45in;
          max-width: 6.45in;
          table-layout: fixed;
        }

        .export-document th,
        .export-document td {
          padding: 4px 6px;
          font-size: 0.92em;
          line-height: 1.24;
          overflow-wrap: anywhere;
          word-break: break-word;
        }

        .export-document pre {
          white-space: pre-wrap;
          overflow-wrap: anywhere;
        }
  """

  private static let copyButtonScript = """
      <script nonce="\(scriptNonce)">
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
  """

  private static var mermaidScript: String {
    guard let source = mermaidTinySource else { return "" }

    return """
      <script nonce="\(scriptNonce)">
        \(source)
        (function () {
          document.body.dataset.mermaidReady = 'pending';
          if (!window.mermaid) {
            document.body.dataset.mermaidReady = 'unavailable';
            return;
          }

          var isDark = window.matchMedia &&
            window.matchMedia('(prefers-color-scheme: dark)').matches;
          mermaid.initialize({
            startOnLoad: false,
            securityLevel: 'strict',
            theme: isDark ? 'dark' : 'default',
            themeVariables: isDark ? {
              lineColor: '#d6dde8',
              signalColor: '#d6dde8',
              signalTextColor: '#f2f2f2'
            } : {
              lineColor: '#24292f',
              signalColor: '#24292f'
            }
          });

          var rendering = mermaid.run({
            querySelector: '.mermaid',
            suppressErrors: true
          });
          Promise.resolve(rendering).then(function () {
            document.body.dataset.mermaidReady = 'ready';
          }, function () {
            document.body.dataset.mermaidReady = 'failed';
          });
        })();
      </script>
    """
  }

  private static let mermaidTinySource: String? = {
    let url = Bundle.main.url(
      forResource: "mermaid-tiny.min",
      withExtension: "js",
      subdirectory: "Mermaid"
    ) ?? Bundle.main.url(forResource: "mermaid-tiny.min", withExtension: "js")

    guard let url else {
      return nil
    }

    return try? String(contentsOf: url, encoding: .utf8)
  }()

  private static func renderBodyHTML(
    for markdown: String,
    baseURL: URL?,
    mode: RenderMode
  ) -> String {
    let normalizedLines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")
    let extracted = extractFootnoteDefinitions(from: normalizedLines)
    let lines = extracted.lines
    let footnotes = FootnoteIndex(definitions: extracted.definitions)

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
      output.append(
        "<p>\(renderInline(paragraph.joined(separator: " "), baseURL: baseURL, mode: mode, footnotes: footnotes))</p>"
      )
      paragraph.removeAll()
    }

    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if var fence = codeFence {
        if trimmed.hasPrefix("```") {
          output.append(renderCodeBlock(language: fence.language, content: fence.lines.joined(separator: "\n"), mode: mode))
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

      if let math = mathBlock(from: lines, startingAt: index) {
        flushParagraph()
        closeList()
        output.append(mathBlockHTML(tex: math.tex, mode: mode))
        index = math.nextIndex
        continue
      }

      if isRawHTMLBlockStart(trimmed) {
        flushParagraph()
        closeList()
        let rawBlock = collectRawHTMLBlock(from: lines, startingAt: index)
        output.append(renderRawHTML(rawBlock.html, baseURL: baseURL, mode: mode))
        index = rawBlock.nextIndex
        continue
      }

      if let table = markdownTable(from: lines, startingAt: index, baseURL: baseURL, mode: mode) {
        flushParagraph()
        closeList()
        output.append(table.html)
        index = table.nextIndex
        continue
      }

      if let heading = markdownHeading(from: trimmed) {
        flushParagraph()
        closeList()
        output.append("<h\(heading.level)>\(renderInline(heading.text, baseURL: baseURL, mode: mode, footnotes: footnotes))</h\(heading.level)>")
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
        if let task = taskListItem(from: item) {
          let box = taskCheckbox(checked: task.checked, mode: mode)
          output.append(
            "<li class=\"task-list-item\">\(box) \(renderInline(task.text, baseURL: baseURL, mode: mode, footnotes: footnotes))</li>"
          )
        } else {
          output.append("<li>\(renderInline(item, baseURL: baseURL, mode: mode, footnotes: footnotes))</li>")
        }
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
        output.append("<li>\(renderInline(item, baseURL: baseURL, mode: mode, footnotes: footnotes))</li>")
        index += 1
        continue
      }

      if trimmed.hasPrefix(">") {
        flushParagraph()
        closeList()
        let quote = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        output.append("<blockquote><p>\(renderInline(String(quote), baseURL: baseURL, mode: mode, footnotes: footnotes))</p></blockquote>")
        index += 1
        continue
      }

      closeList()
      paragraph.append(trimmed)
      index += 1
    }

    if let fence = codeFence {
      output.append(renderCodeBlock(language: fence.language, content: fence.lines.joined(separator: "\n"), mode: mode))
    }
    flushParagraph()
    closeList()

    if !footnotes.order.isEmpty {
      let items = footnotes.order.map { id -> String in
        let anchor = footnoteAnchor(for: id)
        let text = renderInline(footnotes.definitions[id] ?? "", baseURL: baseURL, mode: mode)
        let back = footnoteLink(
          anchor: "fnref-\(anchor)",
          label: "↩",
          className: "footnote-backref"
        )
        return "<li id=\"fn-\(anchor)\">\(text) \(back)</li>"
      }
      output.append(
        "<section class=\"footnotes\"><hr><ol>\n\(items.joined(separator: "\n"))\n</ol></section>"
      )
    }

    return output.joined(separator: "\n")
  }

  private final class FootnoteIndex {
    let definitions: [String: String]
    private(set) var order: [String] = []

    init(definitions: [String: String]) {
      self.definitions = definitions
    }

    func number(for id: String) -> Int? {
      guard definitions[id] != nil else { return nil }
      if let existing = order.firstIndex(of: id) { return existing + 1 }
      order.append(id)
      return order.count
    }
  }

  /// Pulls `[^id]: text` definitions out of the document, skipping fenced code.
  private static func extractFootnoteDefinitions(
    from lines: [String]
  ) -> (lines: [String], definitions: [String: String]) {
    var remaining: [String] = []
    var definitions: [String: String] = [:]
    var inFence = false
    var currentID: String?

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if trimmed.hasPrefix("```") {
        inFence.toggle()
        currentID = nil
        remaining.append(line)
        continue
      }

      if inFence {
        remaining.append(line)
        continue
      }

      if
        let match = firstMatch(in: trimmed, pattern: #"^\[\^([^\]\s]+)\]:\s*(.*)$"#),
        let id = match.capture(1, in: trimmed)
      {
        definitions[id] = match.capture(2, in: trimmed) ?? ""
        currentID = id
        continue
      }

      if let id = currentID, !trimmed.isEmpty, line.hasPrefix("    ") || line.hasPrefix("\t") {
        definitions[id, default: ""] += " " + trimmed
        continue
      }

      currentID = nil
      remaining.append(line)
    }

    return (remaining, definitions)
  }

  private static func footnoteAnchor(for id: String) -> String {
    String(id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" })
  }

  private static func footnoteLink(anchor: String, label: String, className: String) -> String {
    let target = anchor.hasPrefix("fnref-") ? anchor : "fn-\(anchor)"
    return "<a class=\"\(className)\" href=\"#\(target)\" data-scroll=\"\(target)\">\(label)</a>"
  }

  private static func taskListItem(from item: String) -> (checked: Bool, text: String)? {
    guard
      let match = firstMatch(in: item, pattern: #"^\[([ x])\]\s+(.+)$"#),
      let marker = match.capture(1, in: item),
      let text = match.capture(2, in: item)
    else { return nil }

    return (marker.lowercased() == "x", text)
  }

  private static func taskCheckbox(checked: Bool, mode: RenderMode) -> String {
    if mode.isRichText {
      return checked ? "\u{2611}" : "\u{2610}"
    }
    return checked
      ? "<input type=\"checkbox\" checked disabled>"
      : "<input type=\"checkbox\" disabled>"
  }

  private static func renderCodeBlock(language: String, content: String, mode: RenderMode) -> String {
    let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
    if mode.rendersMermaid && isMermaidLanguage(trimmedLanguage) {
      return #"<pre class="mermaid">\#(escapeHTML(content))</pre>"#
    }

    let label = trimmedLanguage.isEmpty ? "plain text" : trimmedLanguage
    let languageClass = trimmedLanguage.isEmpty ? "" : #" class="language-\#(escapeHTMLAttribute(trimmedLanguage))""#
    let body = escapeHTML(content)
    let copyButton = mode.isPreview
      ? #"<button type="button" class="codeblock-copy" aria-label="Copy code" title="Copy code"></button>"#
      : ""
    let header = mode.isPreview || !trimmedLanguage.isEmpty
      ? """
        <div class="codeblock-header">
          <span class="codeblock-lang">\(escapeHTML(label))</span>
          \(copyButton)
        </div>
      """
      : ""

    return """
    <div class="codeblock">
      \(header)
      <pre><code\(languageClass)>\(body)</code></pre>
    </div>
    """
  }

  private static func containsMermaidFence(in markdown: String) -> Bool {
    let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")

    var isInFence = false
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.hasPrefix("```") else { continue }

      if isInFence {
        isInFence = false
      } else {
        let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        if isMermaidLanguage(language) {
          return true
        }
        isInFence = true
      }
    }

    return false
  }

  private static func isMermaidLanguage(_ language: String) -> Bool {
    language.compare("mermaid", options: [.caseInsensitive]) == .orderedSame
  }

  private static func markdownTable(
    from lines: [String],
    startingAt index: Int,
    baseURL: URL?,
    mode: RenderMode
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
        "<th\(tableCellStyleAttribute(alignment, columnCount: headers.count))>\(renderInline(cell, baseURL: baseURL, mode: mode, imageWidth: tableImageWidth(for: mode)))</th>"
      }
      .joined()

    let bodyHTML = rows.map { row in
      let cells = zip(row, alignments)
        .map { cell, alignment in
          "<td\(tableCellStyleAttribute(alignment, columnCount: headers.count))>\(renderInline(cell, baseURL: baseURL, mode: mode, imageWidth: tableImageWidth(for: mode)))</td>"
        }
        .joined()
      return "<tr>\(cells)</tr>"
    }
    .joined(separator: "\n")

    let body = bodyHTML.isEmpty ? "" : "\n<tbody>\n\(bodyHTML)\n</tbody>"

    return (
      """
      <table width="100%" style="width: 100%; max-width: 100%; table-layout: fixed;">
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

  private static func tableCellStyleAttribute(_ alignment: TableAlignment, columnCount: Int) -> String {
    let width = columnCount > 0 ? 100.0 / Double(columnCount) : 100.0
    let textAlignment: String
    switch alignment {
    case .left:
      textAlignment = "left"
    case .center:
      textAlignment = "center"
    case .right:
      textAlignment = "right"
    }

    return #" style="text-align: \#(textAlignment); width: \#(String(format: "%.4g", width))%; overflow-wrap: anywhere; word-break: break-word; vertical-align: top;""#
  }

  private static func tableImageWidth(for mode: RenderMode) -> Int? {
    mode.isRichText ? 220 : nil
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

  private static func renderRawHTML(_ rawHTML: String, baseURL: URL?, mode: RenderMode) -> String {
    let html = sanitizeRawHTML(rawHTML)
    return replacingMatches(in: html, pattern: #"<img\b[^>]*\bsrc\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)[^>]*>"#) { match in
      guard let tagRange = Range(match.range, in: html) else { return "" }
      var tag = String(html[tagRange])
      guard
        let source = match.capture(1, in: html),
        let rewrittenSource = previewImageSource(
          for: unquotedHTMLAttributeValue(source),
          baseURL: baseURL
        )
      else {
        return tag
      }

      let quote: Character? = source.first == "\"" || source.first == "'" ? source.first : nil
      let escapedSource = escapeHTMLAttribute(rewrittenSource)
      let replacement = quote.map { "\($0)\(escapedSource)\($0)" } ?? escapedSource
      tag = tag.replacingOccurrences(of: source, with: replacement)

      if !tag.lowercased().contains("style=") {
        let sizeAttributes = imageAttributes(for: mode, width: nil)
        tag = String(tag.dropLast()) + sizeAttributes + ">"
      }

      return tag
    }
  }

  // MARK: Raw HTML sanitizing

  private static let allowedHTMLTags: Set<String> = [
    "a", "abbr", "b", "blockquote", "br", "caption", "center", "code", "dd", "del", "details", "div",
    "dl", "dt", "em", "figcaption", "figure", "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "img",
    "ins", "kbd", "li", "mark", "ol", "p", "picture", "pre", "s", "section", "small", "source",
    "span", "strong", "sub", "summary", "sup", "table", "tbody", "td", "tfoot", "th", "thead", "tr",
    "u", "ul"
  ]

  private static let voidHTMLTags: Set<String> = ["br", "hr", "img", "source"]

  private static let globalHTMLAttributes: Set<String> = ["align", "title", "lang", "dir"]

  private static let tagHTMLAttributes: [String: Set<String>] = [
    "a": ["href"],
    "img": ["src", "alt", "width", "height"],
    "source": ["srcset", "media", "type"],
    "td": ["colspan", "rowspan", "valign", "width"],
    "th": ["colspan", "rowspan", "valign", "width"],
    "table": ["width"],
    "details": ["open"],
    "ol": ["start", "type"],
    "li": ["value"]
  ]

  /// Keeps README-style block HTML (headings, images, tables, details) and drops everything
  /// else: scripts and styles with their contents, unknown tags (shown as text), event
  /// handlers, inline styles, and any link or image address that is not http, https,
  /// mailto, a relative path, or an embedded image.
  private static func sanitizeRawHTML(_ html: String) -> String {
    let withoutActiveElements = removingActiveElements(from: html)
    let regex = regularExpression(for: htmlTagPattern)
    var result = ""
    var cursor = withoutActiveElements.startIndex

    for match in regex.matches(in: withoutActiveElements, range: NSRange(withoutActiveElements.startIndex..., in: withoutActiveElements)) {
      guard let range = Range(match.range, in: withoutActiveElements) else { continue }
      result += withoutActiveElements[cursor..<range.lowerBound].replacingOccurrences(of: "<", with: "&lt;")

      let isClosing = match.capture(1, in: withoutActiveElements) == "/"
      let name = (match.capture(2, in: withoutActiveElements) ?? "").lowercased()
      if allowedHTMLTags.contains(name) {
        if isClosing {
          result += voidHTMLTags.contains(name) ? "" : "</\(name)>"
        } else {
          let attributes = sanitizedAttributes(match.capture(3, in: withoutActiveElements) ?? "", tag: name)
          result += "<\(name)\(attributes)>"
        }
      } else {
        result += escapeHTML(String(withoutActiveElements[range]))
      }
      cursor = range.upperBound
    }

    result += withoutActiveElements[cursor...].replacingOccurrences(of: "<", with: "&lt;")
    return result
  }

  private static let htmlTagPattern = #"<(/?)([a-zA-Z][a-zA-Z0-9]*)((?:[^>"']|"[^"]*"|'[^']*')*)>"#

  /// Elements whose contents are text to the parser; they end at the first matching close tag.
  private static let rawTextHTMLTags: Set<String> = ["script", "style", "iframe", "noscript"]

  /// Elements that can nest, so their end is found by counting open and close tags.
  private static let nestableActiveHTMLTags: Set<String> = ["svg", "template", "form", "object"]

  /// Removes active elements together with everything inside them. Nested elements of the
  /// same kind are counted, and an element that is never closed removes the rest of the
  /// block, so nothing after an unclosed `<svg>` or `<script>` survives.
  private static func removingActiveElements(from html: String) -> String {
    let matches = regularExpression(for: htmlTagPattern)
      .matches(in: html, range: NSRange(html.startIndex..., in: html))

    func details(_ match: NSTextCheckingResult) -> (range: Range<String.Index>, name: String, closing: Bool, selfClosing: Bool)? {
      guard let range = Range(match.range, in: html) else { return nil }
      let attributes = match.capture(3, in: html) ?? ""
      return (
        range,
        (match.capture(2, in: html) ?? "").lowercased(),
        match.capture(1, in: html) == "/",
        attributes.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/")
      )
    }

    var result = ""
    var cursor = html.startIndex
    var index = 0

    while index < matches.count {
      guard let opening = details(matches[index]) else { index += 1; continue }
      let isRawText = rawTextHTMLTags.contains(opening.name)
      let isNestable = nestableActiveHTMLTags.contains(opening.name)
      guard !opening.closing, isRawText || isNestable || opening.name == "embed" else { index += 1; continue }

      result += html[cursor..<opening.range.lowerBound]

      if opening.name == "embed" || opening.selfClosing {
        cursor = opening.range.upperBound
        index += 1
        continue
      }

      var depth = 1
      var scan = index + 1
      var end: String.Index?
      while scan < matches.count {
        defer { scan += 1 }
        guard let next = details(matches[scan]), next.name == opening.name else { continue }
        if isRawText {
          if next.closing { end = next.range.upperBound; break }
        } else if next.closing {
          depth -= 1
          if depth == 0 { end = next.range.upperBound; break }
        } else if !next.selfClosing {
          depth += 1
        }
      }

      if let end {
        cursor = end
        index = scan + 1
      } else {
        cursor = html.endIndex
        index = matches.count
      }
    }

    if cursor < html.endIndex { result += html[cursor...] }
    return result
  }

  private static func sanitizedAttributes(_ raw: String, tag: String) -> String {
    let allowed = globalHTMLAttributes.union(tagHTMLAttributes[tag] ?? [])
    let regex = regularExpression(
      for: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'<>=`]+)))?"#
    )
    var output = ""

    for match in regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
      let name = (match.capture(1, in: raw) ?? "").lowercased()
      guard allowed.contains(name) else { continue }

      let rawValue = match.capture(2, in: raw) ?? match.capture(3, in: raw) ?? match.capture(4, in: raw)
      guard let rawValue else {
        if name == "open" { output += " open" }
        continue
      }

      let value = decodingHTMLEntities(rawValue)
      switch name {
      case "href":
        guard isSafeURL(value, schemes: ["http", "https", "mailto"], allowImageData: false) else { continue }
      case "src":
        guard isSafeURL(value, schemes: ["http", "https"], allowImageData: true) else { continue }
      case "srcset":
        let candidates = value.split(separator: ",").map {
          String($0).trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init) ?? ""
        }
        guard candidates.allSatisfy({ isSafeURL($0, schemes: ["http", "https"], allowImageData: true) }) else { continue }
      case "title", "alt", "lang", "dir", "align", "valign", "media", "type":
        break
      default:
        guard value.range(of: #"^[0-9a-zA-Z%.\- ]{0,40}$"#, options: .regularExpression) != nil else { continue }
      }

      output += " \(name)=\"\(escapeHTMLAttribute(value))\""
    }

    return output
  }

  private static func decodingHTMLEntities(_ text: String) -> String {
    var result = replacingMatches(in: text, pattern: #"&#x([0-9a-f]+);?"#) { match in
      scalarString(match.capture(1, in: text), radix: 16)
    }
    let afterHex = result
    result = replacingMatches(in: afterHex, pattern: #"&#([0-9]+);?"#) { match in
      scalarString(match.capture(1, in: afterHex), radix: 10)
    }
    for (entity, character) in [
      ("&colon;", ":"), ("&tab;", "\t"), ("&newline;", "\n"), ("&lt;", "<"),
      ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")
    ] {
      result = result.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
    }
    return result
  }

  private static func scalarString(_ digits: String?, radix: Int) -> String {
    guard
      let digits,
      let value = UInt32(digits, radix: radix),
      let scalar = Unicode.Scalar(value)
    else { return "" }
    return String(Character(scalar))
  }

  /// True for relative paths, fragments, and addresses whose scheme is in `schemes`
  /// (or an embedded raster image when `allowImageData`). Whitespace and control
  /// characters are ignored when reading the scheme, as browsers do.
  private static func isSafeURL(_ value: String, schemes: Set<String>, allowImageData: Bool) -> Bool {
    let cleaned = String(
      String.UnicodeScalarView(decodingHTMLEntities(value).unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F })
    ).lowercased()

    guard let colon = cleaned.firstIndex(of: ":") else { return true }
    let scheme = String(cleaned[..<colon])
    if scheme.contains("/") || scheme.contains("?") || scheme.contains("#") { return true }
    if schemes.contains(scheme) { return true }
    if allowImageData, scheme == "data" {
      return cleaned.range(of: #"^data:image/(png|jpe?g|gif|webp)[;,]"#, options: .regularExpression) != nil
    }
    return false
  }

  private static func unquotedHTMLAttributeValue(_ source: String) -> String {
    guard
      source.count >= 2,
      let first = source.first,
      let last = source.last,
      (first == "\"" && last == "\"") || (first == "'" && last == "'")
    else {
      return source
    }

    return String(source.dropFirst().dropLast())
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

  private static func renderInline(
    _ markdown: String,
    baseURL: URL?,
    mode: RenderMode,
    imageWidth: Int? = nil,
    footnotes: FootnoteIndex? = nil
  ) -> String {
    // The placeholder markers below are private-use characters; drop them from the input
    // so document text can never collide with a placeholder.
    var html = escapeHTML(markdown)
      .replacingOccurrences(of: "\u{E000}", with: "")
      .replacingOccurrences(of: "\u{E001}", with: "")

    // Code spans and math are swapped for placeholders so the emphasis and
    // link rules below cannot rewrite their contents.
    var protectedSegments: [String] = []
    var protectedPlain: [String] = []
    func protect(_ segment: String, plain: String) -> String {
      protectedSegments.append(segment)
      protectedPlain.append(plain)
      return "\u{E000}\(protectedSegments.count - 1)\u{E001}"
    }

    // Attribute values must never receive the HTML of a protected segment, so they get
    // the segment's original text instead, decoded once and escaped once.
    func attributeText(_ text: String) -> String {
      let plain = replacingMatches(in: text, pattern: "\u{E000}(\\d+)\u{E001}") { match in
        guard
          let digits = match.capture(1, in: text),
          let index = Int(digits),
          protectedPlain.indices.contains(index)
        else { return "" }
        return protectedPlain[index]
      }
      return unescapeHTMLAttribute(plain)
    }

    html = replacingMatches(in: html, pattern: #"`([^`]+)`"#) { match in
      let inner = match.capture(1, in: html) ?? ""
      return protect("<code>\(inner)</code>", plain: "`\(inner)`")
    }
    html = replacingMatches(in: html, pattern: #"(?<![\\$\d])\$(?!\s)([^$\n]+?)(?<!\s)\$(?!\d)"#) { match in
      let tex = match.capture(1, in: html) ?? ""
      return protect(inlineMathHTML(escapedTeX: tex, mode: mode), plain: "$\(tex)$")
    }
    html = replacingMatches(in: html, pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) { match in
      let alt = attributeText(match.capture(1, in: html) ?? "")
      let source = attributeText(match.capture(2, in: html) ?? "")
      guard isSafeURL(source, schemes: ["http", "https"], allowImageData: true) else {
        return escapeHTMLAttribute(alt)
      }
      let previewSource = previewImageSource(for: source, baseURL: baseURL) ?? source
      let sizeAttributes = imageAttributes(for: mode, width: imageWidth)
      return #"<img src="\#(escapeHTMLAttribute(previewSource))" alt="\#(escapeHTMLAttribute(alt))"\#(sizeAttributes)>"#
    }
    html = replacingMatches(in: html, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) { match in
      let label = match.capture(1, in: html) ?? ""
      let destination = attributeText(match.capture(2, in: html) ?? "")
      guard isSafeURL(destination, schemes: ["http", "https", "mailto"], allowImageData: false) else {
        return label
      }
      return #"<a href="\#(escapeHTMLAttribute(destination))">\#(label)</a>"#
    }
    html = replacingMatches(in: html, pattern: #"\*\*([^*]+)\*\*"#) { match in
      "<strong>\(match.capture(1, in: html) ?? "")</strong>"
    }
    html = replacingMatches(in: html, pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#) { match in
      "<em>\(match.capture(1, in: html) ?? "")</em>"
    }
    html = replacingMatches(in: html, pattern: #"~~([^~]+)~~"#) { match in
      "<del>\(match.capture(1, in: html) ?? "")</del>"
    }

    if let footnotes {
      html = replacingMatches(in: html, pattern: #"\[\^([^\]\s]+)\]"#) { match in
        guard
          let id = match.capture(1, in: html),
          let number = footnotes.number(for: id)
        else {
          return match.capture(0, in: html) ?? ""
        }

        let anchor = footnoteAnchor(for: id)
        let link = footnoteLink(anchor: anchor, label: "\(number)", className: "footnote-link")
          .replacingOccurrences(of: "<a ", with: "<a id=\"fnref-\(anchor)\" ")
        return "<sup class=\"footnote-ref\">\(link)</sup>"
      }
    }

    return replacingMatches(in: html, pattern: "\u{E000}(\\d+)\u{E001}") { match in
      guard
        let text = match.capture(1, in: html),
        let index = Int(text),
        protectedSegments.indices.contains(index)
      else {
        return match.capture(0, in: html) ?? ""
      }
      return protectedSegments[index]
    }
  }

  private static func inlineMathHTML(escapedTeX: String, mode: RenderMode) -> String {
    if mode.isRichText {
      return "<span class=\"math-inline\">$\(escapedTeX)$</span>"
    }
    let tex = escapeHTMLAttribute(unescapeHTMLAttribute(escapedTeX))
    return "<span class=\"math-inline\" data-tex=\"\(tex)\">$\(escapedTeX)$</span>"
  }

  private static func mathBlockHTML(tex: String, mode: RenderMode) -> String {
    if mode.isRichText {
      return "<p class=\"math-block\">$$\(escapeHTML(tex))$$</p>"
    }
    return "<div class=\"math-block\" data-tex=\"\(escapeHTMLAttribute(tex))\">$$\(escapeHTML(tex))$$</div>"
  }

  /// A `$$ ... $$` display block starting at `index`, on one line or spanning lines.
  private static func mathBlock(
    from lines: [String],
    startingAt index: Int
  ) -> (tex: String, nextIndex: Int)? {
    let first = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
    guard first.hasPrefix("$$") else { return nil }

    let afterOpening = String(first.dropFirst(2))
    if afterOpening.hasSuffix("$$"), afterOpening.count >= 2 {
      let tex = String(afterOpening.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
      return tex.isEmpty ? nil : (tex, index + 1)
    }

    var parts = [afterOpening]
    var cursor = index + 1
    while cursor < lines.count {
      let trimmed = lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasSuffix("$$") {
        parts.append(String(trimmed.dropLast(2)))
        let tex = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return tex.isEmpty ? nil : (tex, cursor + 1)
      }
      if trimmed.isEmpty { return nil }
      parts.append(trimmed)
      cursor += 1
    }
    return nil
  }

  private static let highlightAssets: String? = {
    func text(_ name: String, _ ext: String) -> String? {
      let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Highlight")
        ?? Bundle.main.url(forResource: name, withExtension: ext)
      return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    guard
      let script = text("highlight.min", "js"),
      let light = text("github.min", "css"),
      let dark = text("github-dark.min", "css")
    else {
      return nil
    }

    return """
      <style>
        \(light)
        @media (prefers-color-scheme: dark) { \(dark) }
        .codeblock pre code.hljs { background: transparent; padding: 0; }
      </style>
      <script nonce="\(scriptNonce)">
        \(script)
        (function () {
          if (!window.hljs) { return; }
          document.querySelectorAll('.codeblock pre code[class*="language-"]').forEach(function (element) {
            var match = /(?:^|\\s)language-([^\\s]+)/.exec(element.className);
            if (!match || !hljs.getLanguage(match[1])) { return; }
            try { hljs.highlightElement(element); } catch (error) {}
          });
        })();
      </script>
    """
  }()

  private static let mathAssets: String? = {
    func text(_ name: String, _ ext: String) -> String? {
      let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Math")
        ?? Bundle.main.url(forResource: name, withExtension: ext)
      return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    guard let script = text("katex.min", "js"), let styles = text("katex.inline.min", "css") else {
      return nil
    }

    return """
      <style>\(styles)</style>
      <script nonce="\(scriptNonce)">
        \(script)
        (function () {
          if (!window.katex) { return; }
          document.querySelectorAll('.math-inline, .math-block').forEach(function (element) {
            try {
              katex.render(element.getAttribute('data-tex') || '', element, {
                throwOnError: false,
                strict: false,
                displayMode: element.classList.contains('math-block')
              });
            } catch (error) {}
          });
        })();
      </script>
    """
  }()

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

  private static func imageAttributes(for mode: RenderMode, width: Int?) -> String {
    if mode.isRichText, let width {
      return #" width="\#(width)" style="max-width: \#(width)px; height: auto;""#
    }

    return #" style="max-width: 100%; height: auto;""#
  }

  static func localImageURLs(for markdown: String, baseURL: URL?) -> [URL] {
    guard let baseURL, baseURL.isFileURL else { return [] }

    var urls: [URL] = []
    var seenPaths = Set<String>()

    func appendImageURL(for source: String) {
      guard let fileURL = localImageURL(for: unescapeHTMLAttribute(source), baseURL: baseURL) else {
        return
      }

      if seenPaths.insert(fileURL.path).inserted {
        urls.append(fileURL)
      }
    }

    let markdownImageRegex = regularExpression(for: #"!\[[^\]]*\]\(([^)]+)\)"#)
    for match in markdownImageRegex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)) {
      guard let source = match.capture(1, in: markdown) else { continue }
      appendImageURL(for: source)
    }

    let rawHTMLImageRegex = regularExpression(for: #"<img\b[^>]*\bsrc\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)[^>]*>"#)
    for match in rawHTMLImageRegex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)) {
      guard let source = match.capture(1, in: markdown) else { continue }
      appendImageURL(for: unquotedHTMLAttributeValue(source))
    }

    return urls
  }

  private static func previewImageSource(for source: String, baseURL: URL?) -> String? {
    guard
      let baseURL,
      baseURL.isFileURL,
      let fileURL = localImageURL(for: unescapeHTMLAttribute(source), baseURL: baseURL),
      let mimeType = imageMIMEType(for: fileURL.pathExtension),
      let data = localImageData(for: fileURL)
    else {
      return nil
    }

    return "data:\(mimeType);base64,\(data.base64EncodedString())"
  }

  private static func localImageData(for fileURL: URL) -> Data? {
    if let data = MarkdownFolderAccessStore.shared.data(for: fileURL) {
      return data
    }

    return try? Data(contentsOf: fileURL)
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

    guard fileURL.path.hasPrefix(rootPath) else {
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
    options: NSRegularExpression.Options = [.caseInsensitive],
    transform: (NSTextCheckingResult) -> String
  ) -> String {
    let regex = regularExpression(for: pattern, options: options)
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

  private static func regularExpression(
    for pattern: String,
    options: NSRegularExpression.Options = [.caseInsensitive]
  ) -> NSRegularExpression {
    do {
      return try NSRegularExpression(pattern: pattern, options: options)
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
  let documentURL: URL?
  let baseURL: URL?
  let appearanceToken: String

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
    requestFolderAccessIfNeeded(in: webView, coordinator: coordinator)

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: baseURL)
    guard
      html != coordinator.currentHTML
        || appearanceToken != coordinator.currentAppearanceToken
    else {
      return
    }

    coordinator.currentHTML = html
    coordinator.currentAppearanceToken = appearanceToken
    webView.loadHTMLString(html, baseURL: baseURL)
  }

  private func requestFolderAccessIfNeeded(in webView: WKWebView, coordinator: Coordinator) {
    guard let documentURL, let baseURL else { return }

    let folderPath = documentURL.deletingLastPathComponent()
      .standardizedFileURL
      .resolvingSymlinksInPath()
      .path
    if coordinator.accessibleFolderPaths.contains(folderPath) { return }

    let imageURLs = MarkdownPreviewHTMLRenderer.localImageURLs(for: markdown, baseURL: baseURL)
    let inaccessibleImageURLs = MarkdownFolderAccessStore.shared.imageURLsNeedingFolderAccess(imageURLs)
    if inaccessibleImageURLs.isEmpty {
      coordinator.accessibleFolderPaths.insert(folderPath)
      return
    }

    guard coordinator.requestedFolderAccessPaths.insert(folderPath).inserted else { return }

    coordinator.folderAccessTask?.cancel()
    coordinator.folderAccessTask = Task { @MainActor [weak webView, weak coordinator] in
      guard let webView, let coordinator, !Task.isCancelled else { return }

      let didGrantAccess = await MarkdownFolderAccessStore.shared.requestAccess(
        toFolderContaining: inaccessibleImageURLs,
        documentURL: documentURL,
        window: webView.window ?? NSApp.keyWindow
      )
      guard !Task.isCancelled else { return }

      coordinator.folderAccessTask = nil
      if didGrantAccess {
        coordinator.accessibleFolderPaths.insert(folderPath)
        coordinator.currentHTML = ""
        loadPreview(in: webView, coordinator: coordinator)
      }
    }
  }

  final class Coordinator: NSObject, WKNavigationDelegate {
    weak var webView: WKWebView?
    var currentHTML = ""
    var currentAppearanceToken = ""
    var folderAccessTask: Task<Void, Never>?
    var requestedFolderAccessPaths = Set<String>()
    var accessibleFolderPaths = Set<String>()

    deinit {
      folderAccessTask?.cancel()
    }

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
