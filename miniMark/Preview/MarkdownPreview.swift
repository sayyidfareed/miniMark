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
    // Only the live preview and printing load the page from the document's folder. An exported
    // HTML or rich-text file must not carry the author's local folder path.
    let usesBaseElement = mode == .preview || mode == .print
    let baseElement = usesBaseElement ? (baseURL.map { #"<base href="\#(escapeHTMLAttribute($0.absoluteString))">"# } ?? "") : ""
    let bodyClass = mode.isPreview ? "" : #" class="export-document""#
    let exportStyles = mode.isPreview ? "" : (mode.isRichText ? richTextDocumentStyles : exportDocumentStyles)
    // The preview follows the app's appearance; exported, printed and rich-text documents are always light.
    let colorScheme = mode.isPreview ? "light dark" : "light"
    let darkStyles = mode.isPreview ? previewDarkStyles : ""
    let hasMath = !mode.isRichText && (body.contains("class=\"math-inline\"") || body.contains("class=\"math-block\""))
    let hasHighlightableCode = !mode.isRichText && body.contains("<code class=\"language-")
    let hasFootnoteLinks = !mode.isRichText && body.contains("data-scroll=")
    let script = [
      mode.isPreview ? copyButtonScript : "",
      hasFootnoteLinks ? footnoteScript : "",
      mode.rendersMermaid && containsMermaidFence(in: markdown) ? mermaidScript(for: mode) : "",
      hasMath ? (mathAssets ?? "") : "",
      hasHighlightableCode ? (highlightAssets(for: mode) ?? "") : ""
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
          color-scheme: \(colorScheme);
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

        hr {
          height: 0;
          margin: 1.4em 0;
          border: 0;
          border-top: 1px solid var(--border);
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

        \(darkStyles)
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

  /// Dark-appearance rules, used only by the live preview. Exported, printed and rich-text
  /// documents are always light, so they never carry these.
  private static let previewDarkStyles = """
        @media (prefers-color-scheme: dark) {
          :root {
            --text: #f2f2f2;
            --muted: #a6a6a6;
            --border: #3f3f3f;
            --code-bg: #242424;
            --page-bg: #1e1e1e;
            --link: #6aa7ff;
          }

          .codeblock-header {
            background: rgba(255, 255, 255, 0.04);
          }

          .codeblock-copy:hover {
            background: rgba(255, 255, 255, 0.08);
          }

          .codeblock-copy.is-copied {
            color: #4ac26b;
          }

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

  /// The diagram theme is chosen once per page load. The live preview reads the current appearance
  /// and is reloaded by `MarkdownWebPreview` whenever its effective appearance changes (System mode
  /// following macOS light and dark included). Export, print and rich text always draw light diagrams.
  private static func mermaidScript(for mode: RenderMode) -> String {
    guard let source = mermaidTinySource else { return "" }

    let isDarkExpression = mode.isPreview
      ? "!!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches)"
      : "false"

    return """
      <script nonce="\(scriptNonce)">
        \(source)
        (function () {
          document.body.dataset.mermaidReady = 'pending';
          if (!window.mermaid) {
            document.body.dataset.mermaidReady = 'unavailable';
            return;
          }

          var nodes = Array.prototype.slice.call(document.querySelectorAll('.mermaid'));
          var isDark = \(isDarkExpression);
          try {
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
            Promise.resolve(mermaid.run({ nodes: nodes, suppressErrors: true })).then(function () {
              document.body.dataset.mermaidReady = 'ready';
            }, function () {
              document.body.dataset.mermaidReady = 'failed';
            });
          } catch (error) {
            document.body.dataset.mermaidReady = 'failed';
          }
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

    let context = RenderContext(baseURL: baseURL, mode: mode, footnotes: footnotes)
    var output: [String] = []
    var bodyLines = lines

    if let frontMatter = yamlFrontMatter(in: bodyLines) {
      output.append(renderCodeBlock(language: "yaml", content: frontMatter.content, mode: mode))
      bodyLines = Array(bodyLines[frontMatter.nextIndex...])
    }

    output += renderBlocks(bodyLines, context: context)

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

  // MARK: Blocks

  /// Marks a hard line break inside paragraph text until inline rendering turns it into `<br>`.
  /// A private-use character, removed from document text so it can never come from the document.
  private static let hardBreakMarker = "\u{E002}"

  /// State shared by every block of one document: render settings, footnote numbering and the
  /// heading anchors already handed out.
  private final class RenderContext {
    let baseURL: URL?
    let mode: RenderMode
    let footnotes: FootnoteIndex
    private var usedHeadingIDs = Set<String>()

    init(baseURL: URL?, mode: RenderMode, footnotes: FootnoteIndex) {
      self.baseURL = baseURL
      self.mode = mode
      self.footnotes = footnotes
    }

    func inline(_ markdown: String, hardBreaks: Bool = false) -> String {
      MarkdownPreviewHTMLRenderer.renderInline(
        markdown,
        baseURL: baseURL,
        mode: mode,
        footnotes: footnotes,
        hardBreaks: hardBreaks
      )
    }

    /// GitHub-style anchors: `## Hello, World!` becomes `hello-world`; repeats get `-1`, `-2`, ...
    func uniqueHeadingID(forHTML html: String) -> String? {
      let base = MarkdownPreviewHTMLRenderer.headingSlug(fromHTML: html)
      guard !base.isEmpty else { return nil }

      var candidate = base
      var suffix = 1
      while usedHeadingIDs.contains(candidate) {
        candidate = "\(base)-\(suffix)"
        suffix += 1
      }
      usedHeadingIDs.insert(candidate)
      return candidate
    }
  }

  /// Renders a run of lines as block HTML. Block quotes and list items call this again for their
  /// own contents. `tight` leaves paragraphs unwrapped, as in a list without blank lines.
  private static func renderBlocks(_ lines: [String], context: RenderContext, tight: Bool = false) -> [String] {
    var output: [String] = []
    var paragraph: [String] = []
    var index = 0

    func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      let html = paragraphHTML(paragraph, context: context)
      output.append(tight ? html : "<p>\(html)</p>")
      paragraph.removeAll()
    }

    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if let fence = codeFenceOpening(trimmed) {
        flushParagraph()
        var content: [String] = []
        var cursor = index + 1
        while cursor < lines.count, !isCodeFenceClosing(lines[cursor], for: fence) {
          content.append(lines[cursor])
          cursor += 1
        }
        output.append(renderCodeBlock(language: fence.info, content: content.joined(separator: "\n"), mode: context.mode))
        index = min(cursor + 1, lines.count)
        continue
      }

      if trimmed.isEmpty {
        flushParagraph()
        index += 1
        continue
      }

      if !paragraph.isEmpty, let level = setextHeadingLevel(trimmed) {
        let text = paragraph.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        paragraph.removeAll()
        output.append(headingHTML(level: level, text: text, context: context))
        index += 1
        continue
      }

      if isThematicBreak(trimmed) {
        flushParagraph()
        output.append("<hr>")
        index += 1
        continue
      }

      if let math = mathBlock(from: lines, startingAt: index) {
        flushParagraph()
        output.append(mathBlockHTML(tex: math.tex, mode: context.mode))
        index = math.nextIndex
        continue
      }

      if isRawHTMLBlockStart(trimmed) {
        flushParagraph()
        let rawBlock = collectRawHTMLBlock(from: lines, startingAt: index)
        let html = renderRawHTML(rawBlock.html, baseURL: context.baseURL, mode: context.mode)
        if !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          output.append(html)
        }
        index = rawBlock.nextIndex
        continue
      }

      if let table = markdownTable(from: lines, startingAt: index, baseURL: context.baseURL, mode: context.mode) {
        flushParagraph()
        output.append(table.html)
        index = table.nextIndex
        continue
      }

      if let heading = markdownHeading(from: trimmed) {
        flushParagraph()
        output.append(headingHTML(level: heading.level, text: heading.text, context: context))
        index += 1
        continue
      }

      if trimmed.hasPrefix(">") {
        flushParagraph()
        let quote = collectBlockquote(from: lines, startingAt: index)
        let inner = renderBlocks(quote.lines, context: context).joined(separator: "\n")
        output.append("<blockquote>\(inner)</blockquote>")
        index = quote.nextIndex
        continue
      }

      if listItem(in: line) != nil {
        flushParagraph()
        let list = renderList(from: lines, startingAt: index, context: context)
        output.append(list.html)
        index = list.nextIndex
        continue
      }

      paragraph.append(line)
      index += 1
    }

    flushParagraph()
    return output
  }

  /// Joins paragraph lines with spaces. A line ending in two spaces or a backslash ends with a hard break.
  private static func paragraphHTML(_ lines: [String], context: RenderContext) -> String {
    var parts: [String] = []
    for (offset, rawLine) in lines.enumerated() {
      var line = rawLine.replacingOccurrences(of: hardBreakMarker, with: "")
      var breaksAfter = false
      if offset < lines.count - 1 {
        let trailingBackslashes = line.reversed().prefix(while: { $0 == "\\" }).count
        if line.hasSuffix("  ") {
          breaksAfter = true
        } else if trailingBackslashes % 2 == 1 {
          line.removeLast()
          breaksAfter = true
        }
      }
      let text = line.trimmingCharacters(in: .whitespaces)
      parts.append(breaksAfter ? text + hardBreakMarker : text)
    }
    return context.inline(parts.joined(separator: " "), hardBreaks: true)
  }

  private static func headingHTML(level: Int, text: String, context: RenderContext) -> String {
    let inner = context.inline(text)
    let idAttribute = context.uniqueHeadingID(forHTML: inner)
      .map { #" id="\#(escapeHTMLAttribute($0))""# } ?? ""
    return "<h\(level)\(idAttribute)>\(inner)</h\(level)>"
  }

  /// The heading's visible text, lowercased, with spaces turned into hyphens and punctuation dropped.
  private static func headingSlug(fromHTML html: String) -> String {
    let text = html
      .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"&(#[0-9]+|#x[0-9a-fA-F]+|[a-zA-Z]+);"#, with: "", options: .regularExpression)
      .lowercased()

    var slug = ""
    for scalar in text.unicodeScalars {
      if scalar == " " {
        slug += "-"
      } else if scalar == "-" || scalar == "_" || CharacterSet.alphanumerics.contains(scalar) {
        slug.unicodeScalars.append(scalar)
      }
    }
    return slug
  }

  /// `---`, `***` or `___` (three or more, spaces allowed between them).
  private static func isThematicBreak(_ trimmed: String) -> Bool {
    guard let marker = trimmed.first, marker == "-" || marker == "*" || marker == "_" else { return false }
    var count = 0
    for character in trimmed {
      if character == marker {
        count += 1
      } else if character != " " && character != "\t" {
        return false
      }
    }
    return count >= 3
  }

  /// A `===` or `---` line under paragraph text makes that text a level 1 or level 2 heading.
  private static func setextHeadingLevel(_ trimmed: String) -> Int? {
    guard
      let marker = trimmed.first,
      marker == "=" || marker == "-",
      trimmed.allSatisfy({ $0 == marker })
    else { return nil }
    return marker == "=" ? 1 : 2
  }

  /// YAML front matter (`---` / `key: value` lines / `---`) at the very top is shown as a code block
  /// instead of being read as a rule and a heading.
  private static func yamlFrontMatter(in lines: [String]) -> (content: String, nextIndex: Int)? {
    guard
      lines.count >= 3,
      lines[0].trimmingCharacters(in: .whitespaces) == "---",
      firstMatch(in: lines[1], pattern: #"^[A-Za-z0-9_][A-Za-z0-9_ -]*:(\s|$)"#) != nil
    else { return nil }

    for index in 2..<lines.count {
      let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
      if trimmed == "---" || trimmed == "..." {
        return (lines[1..<index].joined(separator: "\n"), index + 1)
      }
    }
    return nil
  }

  /// True when the line begins a block other than a paragraph, so it cannot continue one lazily.
  private static func startsBlock(_ lines: [String], at index: Int) -> Bool {
    let line = lines[index]
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    return codeFenceOpening(trimmed) != nil
      || isThematicBreak(trimmed)
      || markdownHeading(from: trimmed) != nil
      || trimmed.hasPrefix(">")
      || trimmed.hasPrefix("$$")
      || isRawHTMLBlockStart(trimmed)
      || listItem(in: line) != nil
      || isTableStart(lines, at: index)
  }

  private static func isTableStart(_ lines: [String], at index: Int) -> Bool {
    guard
      index + 1 < lines.count,
      let headers = tableCells(from: lines[index]),
      let alignments = tableAlignments(from: lines[index + 1])
    else { return false }
    return !headers.isEmpty && headers.count == alignments.count
  }

  /// Consecutive `>` lines with the markers removed, plus plain lines that lazily continue the
  /// quoted paragraph. Nested `>>` quotes are handled when the contents are rendered.
  private static func collectBlockquote(from lines: [String], startingAt start: Int) -> (lines: [String], nextIndex: Int) {
    var inner: [String] = []
    var index = start

    while index < lines.count {
      let line = lines[index]
      let content = line.drop(while: { $0 == " " || $0 == "\t" })
      if content.first == ">" {
        var rest = content.dropFirst()
        if rest.first == " " || rest.first == "\t" {
          rest = rest.dropFirst()
        }
        inner.append(String(rest))
        index += 1
        continue
      }

      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard
        !trimmed.isEmpty,
        let last = inner.last?.trimmingCharacters(in: .whitespaces),
        !last.isEmpty,
        markdownHeading(from: last) == nil,
        setextHeadingLevel(trimmed) == nil,
        !startsBlock(lines, at: index),
        !hasOpenCodeFence(inner)
      else { break }

      inner.append(trimmed)
      index += 1
    }

    return (inner, index)
  }

  // MARK: Lists

  private struct ListItemMarker {
    let indent: Int
    let ordered: Bool
    let number: Int
    let contentIndent: Int
    let content: String
  }

  /// `- item`, `* item`, `+ item`, `1. item` or `1) item`, with its indentation (tabs count to the next
  /// multiple of four columns).
  private static func listItem(in line: String) -> ListItemMarker? {
    let expanded = expandingLeadingTabs(line)
    guard
      let match = firstMatch(in: expanded, pattern: #"^( *)([-*+]|\d{1,9}[.)])([ \t]+)(\S.*)$"#),
      let indentText = match.capture(1, in: expanded),
      let marker = match.capture(2, in: expanded),
      let spacing = match.capture(3, in: expanded),
      let content = match.capture(4, in: expanded),
      !isThematicBreak(expanded.trimmingCharacters(in: .whitespaces))
    else { return nil }

    let ordered = marker.first?.isNumber == true
    let number = ordered ? (Int(marker.dropLast()) ?? 1) : 1
    let spaces = spacing.count > 4 ? 1 : spacing.count
    return ListItemMarker(
      indent: indentText.count,
      ordered: ordered,
      number: number,
      contentIndent: indentText.count + marker.count + spaces,
      content: content
    )
  }

  private static func expandingLeadingTabs(_ line: String) -> String {
    guard line.first == " " || line.first == "\t" else { return line }

    var prefix = ""
    var column = 0
    var rest = Substring(line)
    while let character = rest.first, character == " " || character == "\t" {
      if character == "\t" {
        let width = 4 - column % 4
        prefix += String(repeating: " ", count: width)
        column += width
      } else {
        prefix += " "
        column += 1
      }
      rest = rest.dropFirst()
    }
    return prefix + rest
  }

  private static func leadingIndent(of line: String) -> Int {
    expandingLeadingTabs(line).prefix(while: { $0 == " " }).count
  }

  private static func removingIndent(_ columns: Int, from line: String) -> String {
    let expanded = expandingLeadingTabs(line)
    let removable = min(columns, expanded.prefix(while: { $0 == " " }).count)
    return String(expanded.dropFirst(removable))
  }

  /// One list starting at `start`. Lines indented two or more columns past the marker (or by a tab)
  /// belong to the current item, which gives nested lists and multi-paragraph items. Blank lines
  /// between items keep one list (and make it loose); an ordered list starts at its first number.
  private static func renderList(
    from lines: [String],
    startingAt start: Int,
    context: RenderContext
  ) -> (html: String, nextIndex: Int) {
    guard let first = listItem(in: lines[start]) else {
      return (renderBlocks([lines[start]], context: context).joined(separator: "\n"), start + 1)
    }

    var items: [(marker: ListItemMarker, lines: [String])] = []
    var currentMarker = first
    var currentLines = [first.content]
    var pendingBlankLines = 0
    var isLoose = false
    var index = start + 1

    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if trimmed.isEmpty {
        pendingBlankLines += 1
        index += 1
        continue
      }

      let indent = leadingIndent(of: line)
      if indent >= currentMarker.indent + 2 {
        if pendingBlankLines > 0 {
          if !hasOpenCodeFence(currentLines) {
            isLoose = true
          }
          currentLines.append(contentsOf: Array(repeating: "", count: pendingBlankLines))
        }
        currentLines.append(removingIndent(min(indent, currentMarker.contentIndent), from: line))
        pendingBlankLines = 0
        index += 1
        continue
      }

      if let marker = listItem(in: line), marker.ordered == first.ordered {
        if pendingBlankLines > 0 {
          isLoose = true
        }
        items.append((marker: currentMarker, lines: currentLines))
        currentMarker = marker
        currentLines = [marker.content]
        pendingBlankLines = 0
        index += 1
        continue
      }

      // A plain line straight after an item continues that item's text (lazy continuation).
      if
        pendingBlankLines == 0,
        setextHeadingLevel(trimmed) == nil,
        !startsBlock(lines, at: index),
        !hasOpenCodeFence(currentLines)
      {
        currentLines.append(trimmed)
        index += 1
        continue
      }

      break
    }
    items.append((marker: currentMarker, lines: currentLines))

    let tag = first.ordered ? "ol" : "ul"
    let startAttribute = first.ordered && first.number != 1 ? #" start="\#(first.number)""# : ""
    var html = ["<\(tag)\(startAttribute)>"]

    for item in items {
      var itemLines = item.lines
      var checkbox: String?
      if let task = taskListItem(from: itemLines[0]) {
        checkbox = taskCheckbox(checked: task.checked, mode: context.mode)
        itemLines[0] = task.text
      }

      var inner = renderBlocks(itemLines, context: context, tight: !isLoose).joined(separator: "\n")
      if let checkbox {
        if inner.hasPrefix("<p>") {
          inner = "<p>\(checkbox) " + String(inner.dropFirst(3))
        } else {
          inner = "\(checkbox) \(inner)"
        }
        html.append("<li class=\"task-list-item\">\(inner)</li>")
      } else {
        html.append("<li>\(inner)</li>")
      }
    }

    html.append("</\(tag)>")
    return (html.joined(separator: "\n"), index)
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
    var openFence: CodeFence?
    var currentID: String?

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if let fence = openFence {
        if isCodeFenceClosing(line, for: fence) { openFence = nil }
        remaining.append(line)
        continue
      }

      if let fence = codeFenceOpening(trimmed) {
        openFence = fence
        currentID = nil
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

    var openFence: CodeFence?
    for line in lines {
      if let fence = openFence {
        if isCodeFenceClosing(line, for: fence) { openFence = nil }
        continue
      }

      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let fence = codeFenceOpening(trimmed) else { continue }
      if isMermaidLanguage(fence.info) {
        return true
      }
      openFence = fence
    }

    return false
  }

  // MARK: Code fences

  private struct CodeFence {
    let character: Character
    let length: Int
    let info: String
  }

  /// A fence of three or more backticks or tildes. A backtick fence's info string may not contain
  /// a backtick, so a line such as ```` ```code``` ```` stays inline code.
  private static func codeFenceOpening(_ trimmed: String) -> CodeFence? {
    guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
    let length = trimmed.prefix(while: { $0 == first }).count
    guard length >= 3 else { return nil }
    let info = String(trimmed.dropFirst(length)).trimmingCharacters(in: .whitespaces)
    if first == "`", info.contains("`") { return nil }
    return CodeFence(character: first, length: length, info: info)
  }

  /// A fence closes only on a line of the same character that is at least as long as the opening.
  private static func isCodeFenceClosing(_ line: String, for fence: CodeFence) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    let length = trimmed.prefix(while: { $0 == fence.character }).count
    return length >= fence.length && length == trimmed.count
  }

  private static func hasOpenCodeFence(_ lines: [String]) -> Bool {
    var openFence: CodeFence?
    for line in lines {
      if let fence = openFence {
        if isCodeFenceClosing(line, for: fence) { openFence = nil }
      } else {
        openFence = codeFenceOpening(line.trimmingCharacters(in: .whitespacesAndNewlines))
      }
    }
    return openFence != nil
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
      guard firstMatch(in: cell, pattern: #"^:?-+:?$"#) != nil else {
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

  // MARK: Raw HTML blocks

  /// Elements whose opening or closing tag at the start of a line begins a raw HTML block.
  private static let rawHTMLBlockTags: Set<String> = [
    "blockquote", "br", "caption", "center", "dd", "details", "div", "dl", "dt", "figcaption", "figure",
    "h1", "h2", "h3", "h4", "h5", "h6", "hr", "li", "ol", "p", "picture", "pre", "section", "source",
    "summary", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul"
  ]

  /// Inline elements that READMEs commonly put on a line of their own.
  private static let rawHTMLInlineStartTags: Set<String> = ["a", "abbr", "img"]

  /// The tag a raw HTML block starts with. The name must match exactly (followed by whitespace,
  /// `>`, `/` or the end of the line), so `<picture>` and `<pre>` are not read as `<p>`.
  private static func rawHTMLStartTag(_ trimmed: String) -> (name: String, isClosing: Bool)? {
    guard
      trimmed.first == "<",
      let match = firstMatch(in: trimmed, pattern: #"^<(/?)([a-zA-Z][a-zA-Z0-9]*)(?=[\s/>]|$)"#),
      let name = match.capture(2, in: trimmed)?.lowercased()
    else { return nil }

    let isClosing = match.capture(1, in: trimmed) == "/"
    if rawHTMLBlockTags.contains(name) || name == "a" || name == "abbr" {
      return (name, isClosing)
    }
    if rawHTMLInlineStartTags.contains(name), !isClosing {
      return (name, isClosing)
    }
    return nil
  }

  private static func isRawHTMLBlockStart(_ trimmed: String) -> Bool {
    trimmed.hasPrefix("<!--") || rawHTMLStartTag(trimmed) != nil
  }

  /// The lines of a raw HTML block starting at `index`.
  ///
  /// - A comment runs to the line that closes it.
  /// - A closing tag (`</div>`) or an empty element (`<img>`, `<hr>`) stands on its own line, so a
  ///   stray closing tag never shows up as text.
  /// - `<pre>` keeps blank lines and ends where its nesting closes.
  /// - Any other element ends on the line where its own nesting closes (`<div>` inside `<div>` is
  ///   counted) or at a blank line, so Markdown between `<div>` and `</div>` with blank lines
  ///   around it still renders, as on GitHub.
  private static func collectRawHTMLBlock(from lines: [String], startingAt index: Int) -> (html: String, nextIndex: Int) {
    let first = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)

    if first.hasPrefix("<!--") {
      var cursor = index
      var text = String(first.dropFirst(4))
      while !text.contains("-->"), cursor + 1 < lines.count {
        cursor += 1
        text = lines[cursor]
      }
      return (lines[index...cursor].joined(separator: "\n"), cursor + 1)
    }

    guard let start = rawHTMLStartTag(first) else {
      return (lines[index], index + 1)
    }

    let standsAlone = start.isClosing || voidHTMLTags.contains(start.name)
    let keepsBlankLines = start.name == "pre"
    var block: [String] = []
    var pendingText = ""
    var depth = 0
    var cursor = index

    while cursor < lines.count {
      let line = lines[cursor]
      if cursor > index, !keepsBlankLines, line.trimmingCharacters(in: .whitespaces).isEmpty {
        break
      }
      block.append(line)
      cursor += 1

      // A tag whose attributes continue on the next line is counted once it is complete.
      pendingText += pendingText.isEmpty ? line : "\n" + line
      if hasUnterminatedTag(pendingText) { continue }
      depth += tagBalance(of: start.name, in: pendingText)
      pendingText = ""
      if standsAlone || depth <= 0 { break }
    }

    return (block.joined(separator: "\n"), cursor)
  }

  private static func hasUnterminatedTag(_ text: String) -> Bool {
    text.range(of: #"<[a-zA-Z/][^>]*$"#, options: .regularExpression) != nil
  }

  /// Opening minus closing tags named `name` (self-closed `<name/>` tags are not counted).
  private static func tagBalance(of name: String, in text: String) -> Int {
    var balance = 0
    for match in regularExpression(for: htmlTagPattern).matches(in: text, range: NSRange(text.startIndex..., in: text)) {
      guard (match.capture(2, in: text) ?? "").lowercased() == name else { continue }
      if match.capture(1, in: text) == "/" {
        balance -= 1
      } else if !(match.capture(3, in: text) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/") {
        balance += 1
      }
    }
    return balance
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
    // Comments are dropped first (an unclosed one hides the rest of the block); whatever is left
    // still goes through active-element removal and the allowlist below.
    let withoutComments = html.replacingOccurrences(of: #"<!--[\s\S]*?(?:-->|$)"#, with: "", options: .regularExpression)
    let withoutActiveElements = removingActiveElements(from: withoutComments)
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

      // Only svg is self-closing in HTML; "<script/>", "<form/>" and the rest still open an element.
      let closesItself = opening.selfClosing && opening.name == "svg"
      if opening.name == "embed" || closesItself {
        cursor = opening.range.upperBound
        index += 1
        continue
      }

      var depth = 1
      var scan = index + 1
      var end: String.Index?
      var endMatch = 0
      while scan < matches.count {
        if let next = details(matches[scan]), next.name == opening.name {
          if isRawText {
            if next.closing { end = next.range.upperBound; endMatch = scan; break }
          } else if next.closing {
            depth -= 1
            if depth == 0 { end = next.range.upperBound; endMatch = scan; break }
          } else if !(next.selfClosing && next.name == "svg") {
            depth += 1
          }
        }
        scan += 1
      }

      if let end {
        cursor = end
        index = endMatch + 1
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
    // An optional closing run of #s (`## Title ##`) is not part of the text.
    let match = firstMatch(in: trimmed, pattern: #"^(#{1,6})\s+(.+?)(?:\s+#+)?\s*$"#)
    guard
      let match,
      let markerRange = Range(match.range(at: 1), in: trimmed),
      let textRange = Range(match.range(at: 2), in: trimmed)
    else { return nil }

    return (trimmed[markerRange].count, String(trimmed[textRange]))
  }

  /// Inline Markdown to HTML. With `hardBreaks`, `hardBreakMarker` characters in `markdown` become
  /// `<br>`; otherwise they are removed like any other private-use marker.
  private static func renderInline(
    _ markdown: String,
    baseURL: URL?,
    mode: RenderMode,
    imageWidth: Int? = nil,
    footnotes: FootnoteIndex? = nil,
    hardBreaks: Bool = false
  ) -> String {
    // The placeholder markers below are private-use characters; drop them from the input
    // so document text can never collide with a placeholder.
    let source = hardBreaks ? markdown : markdown.replacingOccurrences(of: hardBreakMarker, with: "")
    var html = escapeHTML(source)
      .replacingOccurrences(of: "\u{E000}", with: "")
      .replacingOccurrences(of: "\u{E001}", with: "")

    // Code spans, math, escaped characters and generated tags are swapped for placeholders so
    // the emphasis and link rules below cannot rewrite their contents.
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
      return unescapeHTMLAttribute(plain).replacingOccurrences(of: hardBreakMarker, with: "")
    }

    func titleAttribute(_ title: String?) -> String {
      guard let title else { return "" }
      return #" title="\#(escapeHTMLAttribute(attributeText(title)))""#
    }

    // An escaped backtick (\`) does not open a code span.
    html = replacingMatches(in: html, pattern: #"(?<!\\)`([^`]+)`"#) { match in
      let inner = (match.capture(1, in: html) ?? "").replacingOccurrences(of: hardBreakMarker, with: "")
      return protect("<code>\(inner)</code>", plain: "`\(inner)`")
    }
    html = replacingMatches(in: html, pattern: #"(?<![\\$\d])\$(?!\s)([^$\n]+?)(?<!\s)\$(?!\d)"#) { match in
      let tex = (match.capture(1, in: html) ?? "").replacingOccurrences(of: hardBreakMarker, with: "")
      return protect(inlineMathHTML(escapedTeX: tex, mode: mode), plain: "$\(tex)$")
    }
    // Backslash escapes: `\*`, `\_`, `\[`, `\#` and the rest of ASCII punctuation stand for the
    // character itself. (`&`, `<` and `>` are already escaped to entities at this point.)
    html = replacingMatches(in: html, pattern: ##"\\(&amp;|&lt;|&gt;|[!"#$%'()*+,\-./:;=?@\[\\\]^_`{|}~])"##) { match in
      let character = match.capture(1, in: html) ?? ""
      return protect(character, plain: character)
    }

    let sizeAttributes = imageAttributes(for: mode, width: imageWidth)
    html = replacingInlineLinks(in: html, images: true) { altText, destination, title in
      let alt = attributeText(altText)
      let source = attributeText(destination)
      guard isSafeURL(source, schemes: ["http", "https"], allowImageData: true) else {
        return escapeHTMLAttribute(alt)
      }
      let previewSource = previewImageSource(for: source, baseURL: baseURL) ?? source
      return protect(
        #"<img src="\#(escapeHTMLAttribute(previewSource))" alt="\#(escapeHTMLAttribute(alt))"\#(titleAttribute(title))\#(sizeAttributes)>"#,
        plain: escapeHTML(alt)
      )
    }
    html = replacingInlineLinks(in: html, images: false) { label, destination, title in
      let href = attributeText(destination)
      guard isSafeURL(href, schemes: ["http", "https", "mailto"], allowImageData: false) else {
        return label
      }

      var attributes = #" href="\#(escapeHTMLAttribute(href))""# + titleAttribute(title)
      // Same-page links (`[Section](#section)`) scroll with the page script, wherever the page is opened from.
      if href.hasPrefix("#"), href.count > 1 {
        let fragment = String(href.dropFirst())
        attributes += #" data-scroll="\#(escapeHTMLAttribute(fragment.removingPercentEncoding ?? fragment))""#
      }
      return protect("<a\(attributes)>", plain: "") + label + protect("</a>", plain: "")
    }

    html = replacingMatches(in: html, pattern: #"\*\*(?!\s)([^*]+?)(?<!\s)\*\*"#) { match in
      "<strong>\(match.capture(1, in: html) ?? "")</strong>"
    }
    html = replacingMatches(in: html, pattern: #"(?<!\*)\*(?!\s)([^*]+?)(?<!\s)\*(?!\*)"#) { match in
      "<em>\(match.capture(1, in: html) ?? "")</em>"
    }
    // Underscores emphasize only at word boundaries, so snake_case_names stay as they are.
    html = replacingMatches(in: html, pattern: #"(?<![\p{L}\p{N}_])__(?![\s_])(.+?)(?<![\s_])__(?![\p{L}\p{N}_])"#) { match in
      "<strong>\(match.capture(1, in: html) ?? "")</strong>"
    }
    html = replacingMatches(in: html, pattern: #"(?<![\p{L}\p{N}_])_(?![\s_])(.+?)(?<![\s_])_(?![\p{L}\p{N}_])"#) { match in
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

    let restored = replacingMatches(in: html, pattern: "\u{E000}(\\d+)\u{E001}") { match in
      guard
        let text = match.capture(1, in: html),
        let index = Int(text),
        protectedSegments.indices.contains(index)
      else {
        return match.capture(0, in: html) ?? ""
      }
      return protectedSegments[index]
    }
    return hardBreaks ? restored.replacingOccurrences(of: hardBreakMarker, with: "<br>") : restored
  }

  /// Replaces each `[label](destination "title")` link (or `![alt](...)` image when `images`) found
  /// by scanning, so destinations may hold balanced parentheses and an optional title.
  private static func replacingInlineLinks(
    in text: String,
    images: Bool,
    transform: (_ label: String, _ destination: String, _ title: String?) -> String
  ) -> String {
    let characters = Array(text)
    var result = ""
    var index = 0

    while index < characters.count {
      let opens = images
        ? characters[index] == "!" && index + 1 < characters.count && characters[index + 1] == "["
        : characters[index] == "["
      if opens {
        let labelStart = index + (images ? 2 : 1)
        if
          let labelEnd = closingBracketIndex(in: characters, from: labelStart),
          labelEnd + 1 < characters.count,
          characters[labelEnd + 1] == "(",
          let tail = linkDestinationAndTitle(in: characters, from: labelEnd + 2)
        {
          let label = String(characters[labelStart..<labelEnd])
          // `[^1]` is a footnote reference, not a link label.
          if images || (!label.isEmpty && !label.hasPrefix("^")) {
            result += transform(label, tail.destination, tail.title)
            index = tail.end
            continue
          }
        }
      }
      result.append(characters[index])
      index += 1
    }

    return result
  }

  private static func closingBracketIndex(in characters: [Character], from start: Int) -> Int? {
    var depth = 1
    var index = start
    while index < characters.count {
      if characters[index] == "[" {
        depth += 1
      } else if characters[index] == "]" {
        depth -= 1
        if depth == 0 { return index }
      }
      index += 1
    }
    return nil
  }

  /// Reads `destination "title")` starting just after the `(`. A destination is either `<...>` or
  /// runs to whitespace with balanced parentheses; the title may be in `"`, `'` or `()`. When that
  /// shape does not fit, everything up to the matching `)` is the destination, so local file names
  /// with spaces keep working.
  private static func linkDestinationAndTitle(
    in characters: [Character],
    from start: Int
  ) -> (destination: String, title: String?, end: Int)? {
    let count = characters.count

    func isSpace(_ character: Character) -> Bool {
      character == " " || character == "\t" || character == "\n"
    }

    func hasSequence(_ sequence: String, at position: Int) -> Bool {
      var cursor = position
      for character in sequence {
        guard cursor < count, characters[cursor] == character else { return false }
        cursor += 1
      }
      return true
    }

    func wholeDestination() -> (destination: String, title: String?, end: Int)? {
      var depth = 0
      var cursor = start
      while cursor < count {
        if characters[cursor] == "(" {
          depth += 1
        } else if characters[cursor] == ")" {
          if depth == 0 {
            let destination = String(characters[start..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines)
            if destination.isEmpty { return nil }
            return (destination: destination, title: nil, end: cursor + 1)
          }
          depth -= 1
        }
        cursor += 1
      }
      return nil
    }

    var index = start
    while index < count, isSpace(characters[index]) { index += 1 }

    var destination = ""
    var pointy: (open: String, close: String)?
    if hasSequence("<", at: index) {
      pointy = ("<", ">")
    } else if hasSequence("&lt;", at: index) {
      pointy = ("&lt;", "&gt;")
    }
    if let pointy {
      var cursor = index + pointy.open.count
      while cursor < count, !hasSequence(pointy.close, at: cursor), characters[cursor] != "\n" { cursor += 1 }
      guard cursor < count, hasSequence(pointy.close, at: cursor) else { return wholeDestination() }
      destination = String(characters[(index + pointy.open.count)..<cursor])
      index = cursor + pointy.close.count
    } else {
      let destinationStart = index
      var depth = 0
      while index < count {
        let character = characters[index]
        if isSpace(character) { break }
        if character == "(" {
          depth += 1
        } else if character == ")" {
          if depth == 0 { break }
          depth -= 1
        }
        index += 1
      }
      destination = String(characters[destinationStart..<index])
    }

    let destinationEnd = index
    while index < count, isSpace(characters[index]) { index += 1 }

    var title: String?
    if index > destinationEnd, index < count, ["\"", "'", "("].contains(characters[index]) {
      let closing: Character = characters[index] == "(" ? ")" : characters[index]
      var cursor = index + 1
      while cursor < count, characters[cursor] != closing { cursor += 1 }
      guard cursor < count else { return wholeDestination() }
      title = String(characters[(index + 1)..<cursor])
      index = cursor + 1
      while index < count, isSpace(characters[index]) { index += 1 }
    }

    guard index < count, characters[index] == ")", !destination.isEmpty else {
      return wholeDestination()
    }
    return (destination, title, index + 1)
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

  private static let highlightSources: (script: String, light: String, dark: String)? = {
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

    return (script, light, dark)
  }()

  /// Code highlighting. Only the live preview carries the dark theme; other modes are always light.
  private static func highlightAssets(for mode: RenderMode) -> String? {
    guard let sources = highlightSources else { return nil }
    let darkTheme = mode.isPreview ? "@media (prefers-color-scheme: dark) { \(sources.dark) }" : ""

    return """
      <style>
        \(sources.light)
        \(darkTheme)
        .codeblock pre code.hljs { background: transparent; padding: 0; }
      </style>
      <script nonce="\(scriptNonce)">
        \(sources.script)
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
  }

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

    // Same reading of `![alt](destination "title")` as the renderer, so titles and parentheses
    // in file names are handled alike.
    _ = replacingInlineLinks(in: markdown, images: true) { _, destination, _ in
      appendImageURL(for: destination)
      return ""
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
    // Only images are ever embedded, so other files are never read or asked about.
    guard imageMIMEType(for: (decodedPath as NSString).pathExtension) != nil else { return nil }

    // Paths relative to the document, including ones that climb out of its folder
    // (`../assets/logo.png`). Whether the file may be read is decided by the sandbox and the
    // folders the user has granted (MarkdownFolderAccessStore); an unreadable one makes the
    // preview ask for its folder.
    let rootURL = baseURL.standardizedFileURL.resolvingSymlinksInPath()
    return URL(fileURLWithPath: decodedPath, relativeTo: rootURL)
      .standardizedFileURL
      .resolvingSymlinksInPath()
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

  /// Compiled patterns, reused across renders (the preview renders on every edit).
  private static let regularExpressionCache = NSCache<NSString, NSRegularExpression>()

  private static func regularExpression(
    for pattern: String,
    options: NSRegularExpression.Options = [.caseInsensitive]
  ) -> NSRegularExpression {
    let key = "\(options.rawValue)|\(pattern)" as NSString
    if let cached = regularExpressionCache.object(forKey: key) {
      return cached
    }

    do {
      let expression = try NSRegularExpression(pattern: pattern, options: options)
      regularExpressionCache.setObject(expression, forKey: key)
      return expression
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

/// What the preview's look depends on: the app's Appearance setting and whether the web view is
/// currently drawn light or dark (in System mode the second one follows macOS).
enum MarkdownPreviewAppearance {
  static func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }

  static func token(setting: String, appearance: NSAppearance) -> String {
    "\(setting)|\(isDark(appearance) ? "dark" : "light")"
  }
}

/// Reports when its effective appearance changes (for example macOS switching to dark mode while the
/// app follows the system), so the preview can be drawn again with the matching diagram theme.
private final class PreviewWebView: WKWebView {
  var effectiveAppearanceDidChange: ((WKWebView) -> Void)?

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    effectiveAppearanceDidChange?(self)
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

    let webView = PreviewWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.allowsMagnification = true
    webView.underPageBackgroundColor = .clear
    webView.effectiveAppearanceDidChange = { [weak coordinator = context.coordinator] webView in
      coordinator?.effectiveAppearanceDidChange(in: webView)
    }
    context.coordinator.webView = webView
    loadPreview(in: webView, coordinator: context.coordinator)
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {
    loadPreview(in: webView, coordinator: context.coordinator)
  }

  private func loadPreview(in webView: WKWebView, coordinator: Coordinator) {
    requestFolderAccessIfNeeded(in: webView, coordinator: coordinator)

    coordinator.appearanceSetting = appearanceToken
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(for: markdown, baseURL: baseURL)
    guard
      html != coordinator.currentHTML
        || coordinator.appearanceToken(for: webView) != coordinator.currentAppearanceToken
    else {
      return
    }

    coordinator.load(html, baseURL: baseURL, in: webView)
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
    var currentBaseURL: URL?
    var currentAppearanceToken = ""
    var appearanceSetting = ""
    var folderAccessTask: Task<Void, Never>?
    var requestedFolderAccessPaths = Set<String>()
    var accessibleFolderPaths = Set<String>()

    private var hasLoadedPage = false
    private var loadGeneration = 0
    /// Where the reader was before the page was replaced; restored once the new page has loaded.
    private var pendingScrollY: Double?

    deinit {
      folderAccessTask?.cancel()
    }

    func appearanceToken(for webView: WKWebView) -> String {
      MarkdownPreviewAppearance.token(setting: appearanceSetting, appearance: webView.effectiveAppearance)
    }

    /// Loads `html`, keeping the reader's scroll position from the page being replaced.
    func load(_ html: String, baseURL: URL?, in webView: WKWebView) {
      currentHTML = html
      currentBaseURL = baseURL
      currentAppearanceToken = appearanceToken(for: webView)
      loadGeneration += 1
      let generation = loadGeneration

      // Nothing to keep yet, or a position is already waiting for the page still loading.
      guard hasLoadedPage, pendingScrollY == nil else {
        hasLoadedPage = true
        webView.loadHTMLString(html, baseURL: baseURL)
        return
      }

      webView.evaluateJavaScript("window.scrollY") { [weak self, weak webView] result, _ in
        guard let self, let webView else { return }
        if self.pendingScrollY == nil {
          self.pendingScrollY = (result as? NSNumber)?.doubleValue ?? 0
        }
        // A newer page was requested meanwhile; it does the loading.
        guard generation == self.loadGeneration else { return }
        webView.loadHTMLString(self.currentHTML, baseURL: self.currentBaseURL)
      }
    }

    /// The light/dark look changed (System mode following macOS, or the Appearance menu): draw the
    /// page again so Mermaid diagrams pick the matching theme.
    func effectiveAppearanceDidChange(in webView: WKWebView) {
      guard hasLoadedPage, !currentHTML.isEmpty else { return }
      guard appearanceToken(for: webView) != currentAppearanceToken else { return }
      load(currentHTML, baseURL: currentBaseURL, in: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      guard let scrollY = pendingScrollY else { return }
      pendingScrollY = nil
      guard scrollY > 0, scrollY.isFinite else { return }
      webView.evaluateJavaScript("window.scrollTo(0, \(scrollY));", completionHandler: nil)
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
        return
      }
      decisionHandler(.cancel)
      // Documents can come from anywhere, so a link only ever opens a web page, an email or a file;
      // other schemes (which could start another app) are ignored.
      if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "file"].contains(scheme) {
        NSWorkspace.shared.open(url)
      }
    }
  }
}
