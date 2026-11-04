import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct MarkdownExportContext {
  let markdown: String
  let fileURL: URL?

  var baseURL: URL? {
    fileURL.map { URL(fileURLWithPath: $0.deletingLastPathComponent().path, isDirectory: true) }
  }

  var suggestedBaseName: String {
    let name = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    return name.isEmpty ? "Untitled" : name
  }
}

enum MarkdownExportFormat: CaseIterable {
  case txt
  case rtf
  case html

  var menuTitle: String {
    switch self {
    case .txt: return "TXT..."
    case .rtf: return "RTF..."
    case .html: return "HTML..."
    }
  }

  var fileExtension: String {
    switch self {
    case .txt: return "txt"
    case .rtf: return "rtf"
    case .html: return "html"
    }
  }

  var contentType: UTType {
    switch self {
    case .txt: return .plainText
    case .rtf: return .rtf
    case .html: return .html
    }
  }

  var documentType: NSAttributedString.DocumentType? {
    switch self {
    case .txt, .html:
      return nil
    case .rtf:
      return .rtf
    }
  }
}

private struct MarkdownExportContextKey: FocusedValueKey {
  typealias Value = MarkdownExportContext
}

extension FocusedValues {
  var markdownExportContext: MarkdownExportContext? {
    get { self[MarkdownExportContextKey.self] }
    set { self[MarkdownExportContextKey.self] = newValue }
  }
}

struct MarkdownExportCommands: Commands {
  let coordinator: MarkdownExportCoordinator

  @FocusedValue(\.markdownExportContext) private var context

  var body: some Commands {
    CommandGroup(replacing: .printItem) {
      Button("Print...") {
        printDocument()
      }
      .keyboardShortcut("p", modifiers: .command)
      .disabled(context == nil && coordinator.currentContext == nil)
    }

    CommandGroup(after: .saveItem) {
      Menu("Export") {
        ForEach(MarkdownExportFormat.allCases, id: \.self) { format in
          Button(format.menuTitle) {
            export(format)
          }
        }

        Divider()

        Button("Print / PDF...") {
          printDocument()
        }
      }
      .disabled(context == nil && coordinator.currentContext == nil)
    }
  }

  private func export(_ format: MarkdownExportFormat) {
    guard let context = context ?? coordinator.currentContext else { return }
    coordinator.export(context, as: format)
  }

  private func printDocument() {
    guard let context = context ?? coordinator.currentContext else { return }
    coordinator.printDocument(context)
  }
}

@MainActor
final class MarkdownExportCoordinator {
  private var printController: MarkdownPrintController?
  private(set) var currentContext: MarkdownExportContext?

  func updateCurrentContext(_ context: MarkdownExportContext?) {
    currentContext = context
  }

  func export(_ context: MarkdownExportContext, as format: MarkdownExportFormat) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [format.contentType]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = "\(context.suggestedBaseName).\(format.fileExtension)"

    let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
      guard response == .OK, let url = panel?.url else { return }

      do {
        let data = try MarkdownExportData.makeData(for: context, format: format)
        try data.write(to: url, options: .atomic)
      } catch {
        self?.showExportError(error)
      }
    }

    if let window = NSApp.keyWindow {
      panel.beginSheetModal(for: window, completionHandler: completion)
    } else {
      panel.begin(completionHandler: completion)
    }
  }

  func printDocument(_ context: MarkdownExportContext) {
    // One print at a time: a second Print while the first is still preparing would drop the first
    // controller without closing its hidden window.
    guard printController == nil else { return }
    let controller = MarkdownPrintController { [weak self] in
      self?.printController = nil
    }
    printController = controller
    controller.print(context)
  }

  private func showExportError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Export Failed"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning

    if let window = NSApp.keyWindow {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }
}

struct MarkdownExportCommandBridge: NSViewRepresentable {
  let context: MarkdownExportContext
  let coordinator: MarkdownExportCoordinator
  @Binding var windowFileURL: URL?

  func makeCoordinator() -> BridgeCoordinator {
    BridgeCoordinator()
  }

  func makeNSView(context bridgeContext: Context) -> NSView {
    let view = NSView(frame: .zero)
    view.isHidden = true
    updateBridge(bridgeContext.coordinator, from: view)
    return view
  }

  func updateNSView(_ view: NSView, context bridgeContext: Context) {
    updateBridge(bridgeContext.coordinator, from: view)
  }

  static func dismantleNSView(_ view: NSView, coordinator: BridgeCoordinator) {
    coordinator.uninstall()
  }

  private func updateBridge(_ bridgeCoordinator: BridgeCoordinator, from view: NSView) {
    bridgeCoordinator.update(context: context, coordinator: coordinator) { url in
      windowFileURL = url
    }
    coordinator.updateCurrentContext(context)

    DispatchQueue.main.async {
      bridgeCoordinator.install(from: view)
    }
  }

  @MainActor
  final class BridgeCoordinator {
    private let responder = MarkdownExportCommandResponder()
    private weak var installedWindow: NSWindow?

    func update(
      context: MarkdownExportContext,
      coordinator: MarkdownExportCoordinator,
      windowURLDidChange: @escaping (URL?) -> Void
    ) {
      responder.context = context
      responder.coordinator = coordinator
      responder.windowURLDidChange = windowURLDidChange
      coordinator.updateCurrentContext(context)
    }

    func install(from view: NSView) {
      guard let window = view.window else { return }

      if installedWindow !== window {
        uninstall()
        responder.nextResponder = window.nextResponder
        window.nextResponder = responder
        installedWindow = window
      }

      responder.syncWindowFileURL(from: window)
    }

    func uninstall() {
      guard let window = installedWindow else { return }

      if window.nextResponder === responder {
        window.nextResponder = responder.nextResponder
      }

      responder.nextResponder = nil
      responder.windowURLDidChange = nil
      installedWindow = nil
    }
  }
}

@MainActor
private final class MarkdownExportCommandResponder: NSResponder, NSUserInterfaceValidations {
  weak var coordinator: MarkdownExportCoordinator?
  var context: MarkdownExportContext?
  var windowURLDidChange: ((URL?) -> Void)?

  @objc(print:)
  func printAction(_ sender: Any?) {
    printActiveDocument()
  }

  @objc(printDocument:)
  func printDocumentAction(_ sender: Any?) {
    printActiveDocument()
  }

  func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    guard
      item.action == #selector(printAction(_:))
        || item.action == #selector(printDocumentAction(_:))
    else {
      return true
    }

    return activeContext != nil
  }

  func syncWindowFileURL(from window: NSWindow) {
    windowURLDidChange?(window.representedURL)
  }

  private var activeContext: MarkdownExportContext? {
    context ?? coordinator?.currentContext
  }

  private func printActiveDocument() {
    guard let context = activeContext else { return }
    coordinator?.printDocument(context)
  }
}

enum MarkdownExportData {
  static func makeData(for context: MarkdownExportContext, format: MarkdownExportFormat) throws -> Data {
    switch format {
    case .txt:
      return Data(MarkdownPlainTextRenderer.plainText(for: context.markdown).utf8)
    case .html:
      let html = MarkdownPreviewHTMLRenderer.htmlDocument(
        for: context.markdown,
        baseURL: context.baseURL,
        mode: .export
      )
      return Data(html.utf8)
    case .rtf:
      return try MarkdownRTFRenderer.rtfData(
        for: context.markdown,
        baseURL: context.baseURL
      )
    }
  }
}

enum MarkdownRTFRenderer {
  static func rtfData(for markdown: String, baseURL: URL?) throws -> Data {
    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: markdown,
      baseURL: baseURL,
      mode: .richText
    )
    let htmlData = Data(html.utf8)
    let attributed = try NSAttributedString(
      data: htmlData,
      options: [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue
      ],
      documentAttributes: nil
    )

    return try attributed.data(
      from: NSRange(location: 0, length: attributed.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
  }
}

enum MarkdownPlainTextRenderer {
  static func plainText(for markdown: String) -> String {
    let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")

    var output: [String] = []
    var paragraph: [String] = []
    var codeFence: [String]?
    var fenceMarker: (character: Character, length: Int) = ("`", 3)
    var index = 0

    func appendBlankIfNeeded() {
      guard output.last?.isEmpty == false else { return }
      output.append("")
    }

    func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      output.append(renderInline(paragraph.joined(separator: " ")))
      paragraph.removeAll()
      appendBlankIfNeeded()
    }

    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if var fence = codeFence {
        if let closing = fenceMarkerRun(in: trimmed),
           closing.character == fenceMarker.character,
           closing.length >= fenceMarker.length,
           trimmed.count == closing.length {
          output.append(contentsOf: fence)
          appendBlankIfNeeded()
          codeFence = nil
        } else {
          fence.append(line)
          codeFence = fence
        }
        index += 1
        continue
      }

      if trimmed.isEmpty {
        flushParagraph()
        index += 1
        continue
      }

      if let opening = fenceMarkerRun(in: trimmed) {
        flushParagraph()
        fenceMarker = opening
        codeFence = []
        index += 1
        continue
      }

      if let table = markdownTable(from: lines, startingAt: index) {
        flushParagraph()
        output.append(contentsOf: table.lines)
        appendBlankIfNeeded()
        index = table.nextIndex
        continue
      }

      if let heading = capture(in: trimmed, pattern: #"^#{1,6}\s+(.+)$"#, index: 1) {
        flushParagraph()
        output.append(renderInline(heading))
        appendBlankIfNeeded()
        index += 1
        continue
      }

      // List items keep their leading indentation so nested lists stay nested.
      if let item = firstMatch(in: line, pattern: #"^([ \t]*)[-*+][ \t]+(.+)$"#),
         let indent = item.capture(1, in: line),
         let content = item.capture(2, in: line) {
        flushParagraph()
        output.append("\(indent)- \(renderInline(content))")
        index += 1
        continue
      }

      if let ordered = firstMatch(in: line, pattern: #"^([ \t]*)(\d+[.)])[ \t]+(.+)$"#),
         let indent = ordered.capture(1, in: line),
         let marker = ordered.capture(2, in: line),
         let item = ordered.capture(3, in: line) {
        flushParagraph()
        output.append("\(indent)\(marker) \(renderInline(item))")
        index += 1
        continue
      }

      if trimmed.hasPrefix(">") {
        flushParagraph()
        let quote = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        output.append("> \(renderInline(String(quote)))")
        index += 1
        continue
      }

      paragraph.append(trimmed)
      index += 1
    }

    if let fence = codeFence {
      output.append(contentsOf: fence)
    }
    flushParagraph()

    return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
  }

  private static func markdownTable(from lines: [String], startingAt index: Int) -> (lines: [String], nextIndex: Int)? {
    guard
      index + 1 < lines.count,
      let headers = tableCells(from: lines[index]),
      tableAlignments(from: lines[index + 1]) != nil
    else {
      return nil
    }

    var rendered = [headers.map(renderInline).joined(separator: " | ")]
    var nextIndex = index + 2

    while nextIndex < lines.count, let cells = tableCells(from: lines[nextIndex]), !cells.isEmpty {
      rendered.append(cells.map(renderInline).joined(separator: " | "))
      nextIndex += 1
    }

    return (rendered, nextIndex)
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

  private static func tableAlignments(from line: String) -> [String]? {
    guard let cells = tableCells(from: line) else { return nil }
    let alignments = cells.filter { firstMatch(in: $0, pattern: #"^:?-{3,}:?$"#) != nil }
    return alignments.count == cells.count ? alignments : nil
  }

  /// Private-use characters that bracket placeholders for text that must not be touched by the
  /// emphasis rules (code spans and backslash escapes).
  private static let placeholderStart = "\u{E000}"
  private static let placeholderEnd = "\u{E001}"

  private static let protectedRegex = makeRegex(
    #"\\([`*_{}\[\]()#+\-.!~|<>])|(?<!`)(`+)(?!`)(.+?)(?<!`)\2(?!`)"#
  )
  private static let imageRegex = makeRegex(#"!\[([^\]]*)\]\(([^)]+)\)"#)
  private static let linkRegex = makeRegex(#"\[([^\]]+)\]\(([^)]+)\)"#)
  private static let emphasisRegexes: [NSRegularExpression] = [
    // Strong and emphasis markers only count as pairs: the opener must be followed by non-space,
    // the closer preceded by non-space, and neither may touch a word character on the outside.
    // That keeps snake_case_names, `2 * 3 * 4` and `a*b*c` untouched.
    makeRegex(#"(?<![\w*])\*\*(?=\S)(.+?)(?<=\S)\*\*(?![\w*])"#),
    makeRegex(#"(?<![\w_])__(?=\S)(.+?)(?<=\S)__(?![\w_])"#),
    makeRegex(#"(?<![\w~])~~(?=\S)(.+?)(?<=\S)~~(?![\w~])"#),
    makeRegex(#"(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])"#),
    makeRegex(#"(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])"#)
  ]
  private static let placeholderRegex = makeRegex("\u{E000}(\\d+)\u{E001}")

  /// Strips Markdown inline syntax conservatively. Text that is not clearly Markdown is left exactly
  /// as typed: code span contents stay verbatim, backslash escapes lose only the backslash, and HTML
  /// entities are never decoded.
  private static func renderInline(_ markdown: String) -> String {
    // Placeholders use private-use characters; if the text already contains them, leave it alone.
    guard !markdown.contains(placeholderStart), !markdown.contains(placeholderEnd) else {
      return markdown
    }

    var protected: [String] = []
    func stash(_ value: String) -> String {
      protected.append(value)
      return "\(placeholderStart)\(protected.count - 1)\(placeholderEnd)"
    }

    var text = replacingMatches(in: markdown, regex: protectedRegex) { match, source in
      if let escaped = match.capture(1, in: source) {
        return stash(escaped)
      }
      var code = match.capture(3, in: source) ?? ""
      if code.count > 2, code.hasPrefix(" "), code.hasSuffix(" "), code.contains(where: { $0 != " " }) {
        code = String(code.dropFirst().dropLast())
      }
      return stash(code)
    }

    text = replacingMatches(in: text, regex: imageRegex) { match, source in
      let alt = match.capture(1, in: source) ?? ""
      let path = match.capture(2, in: source) ?? ""
      return alt.isEmpty ? path : alt
    }
    text = replacingMatches(in: text, regex: linkRegex) { match, source in
      match.capture(1, in: source) ?? ""
    }

    for regex in emphasisRegexes {
      text = replacingMatches(in: text, regex: regex) { match, source in
        match.capture(1, in: source) ?? ""
      }
    }

    return replacingMatches(in: text, regex: placeholderRegex) { match, source in
      guard let value = match.capture(1, in: source), let index = Int(value), protected.indices.contains(index) else {
        return ""
      }
      return protected[index]
    }
  }

  /// Returns the fence character and run length when the line is a fence opener or closer.
  private static func fenceMarkerRun(in trimmed: String) -> (character: Character, length: Int)? {
    guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
    let length = trimmed.prefix(while: { $0 == first }).count
    guard length >= 3 else { return nil }
    // A backtick fence's info string may not contain backticks (that would be an inline code span).
    if first == "`", trimmed.dropFirst(length).contains("`") { return nil }
    return (first, length)
  }

  private static func capture(in text: String, pattern: String, index: Int) -> String? {
    firstMatch(in: text, pattern: pattern)?.capture(index, in: text)
  }

  private static func firstMatch(in text: String, pattern: String) -> NSTextCheckingResult? {
    regularExpression(for: pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
  }

  private static func replacingMatches(
    in text: String,
    regex: NSRegularExpression,
    transform: (NSTextCheckingResult, String) -> String
  ) -> String {
    var result = ""
    var currentIndex = text.startIndex

    for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
      guard let matchRange = Range(match.range, in: text) else { continue }
      result += text[currentIndex..<matchRange.lowerBound]
      result += transform(match, text)
      currentIndex = matchRange.upperBound
    }

    result += text[currentIndex...]
    return result
  }

  private static func regularExpression(for pattern: String) -> NSRegularExpression {
    makeRegex(pattern)
  }

  private static func makeRegex(_ pattern: String) -> NSRegularExpression {
    do {
      return try NSRegularExpression(pattern: pattern, options: [])
    } catch {
      preconditionFailure("Invalid regular expression: \(pattern)")
    }
  }
}

@MainActor
private final class MarkdownPrintController: NSObject, WKNavigationDelegate {
  /// Margins in points (0.75 inch) on every side.
  private static let pageMargin: CGFloat = 54
  /// Fallback paper (US Letter) when the system print settings report no paper size.
  private static let fallbackPaperSize = NSSize(width: 612, height: 792)
  private static let readinessPollInterval: TimeInterval = 0.05
  private static let readinessPollLimit = 160

  private let completion: () -> Void
  private var webView: WKWebView?
  private var hostWindow: NSWindow?
  private var printInfo: NSPrintInfo?
  private var jobTitle = "Untitled"
  private weak var window: NSWindow?

  init(completion: @escaping () -> Void) {
    self.completion = completion
  }

  func print(_ context: MarkdownExportContext) {
    window = NSApp.keyWindow
    jobTitle = context.suggestedBaseName

    // Paper and margins come from the user's default print settings (US Letter or A4 by region);
    // the page is laid out at the printable width so it paginates the way it will be printed.
    let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
    if info.paperSize.width < 100 || info.paperSize.height < 100 {
      info.paperSize = Self.fallbackPaperSize
    }
    info.topMargin = Self.pageMargin
    info.bottomMargin = Self.pageMargin
    info.leftMargin = Self.pageMargin
    info.rightMargin = Self.pageMargin
    info.isHorizontallyCentered = false
    info.isVerticallyCentered = false
    info.horizontalPagination = .fit
    info.verticalPagination = .automatic
    printInfo = info

    let contentSize = printableSize(for: info)

    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true

    let webView = WKWebView(frame: NSRect(origin: .zero, size: contentSize), configuration: configuration)
    webView.navigationDelegate = self
    self.webView = webView
    attachToOffscreenWindow(webView, size: contentSize)

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: context.markdown,
      baseURL: context.baseURL,
      mode: .print
    )
    webView.loadHTMLString(html, baseURL: context.baseURL)
  }

  /// A WKWebView that is not in a window never lays out, so Mermaid (which measures text) and the
  /// print pagination can come out blank or as a single page. Hosting it in a borderless, invisible
  /// window far off screen gives it a real layout without anything flashing on screen.
  private func attachToOffscreenWindow(_ webView: WKWebView, size: NSSize) {
    let host = NSWindow(
      contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    host.isReleasedWhenClosed = false
    host.isRestorable = false
    host.isExcludedFromWindowsMenu = true
    host.hasShadow = false
    host.alphaValue = 0
    host.ignoresMouseEvents = true
    host.collectionBehavior = [.transient, .ignoresCycle, .stationary]
    host.contentView = webView
    host.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
    host.orderBack(nil)
    hostWindow = host
  }

  private func printableSize(for info: NSPrintInfo) -> NSSize {
    NSSize(
      width: max(info.paperSize.width - info.leftMargin - info.rightMargin, 200),
      height: max(info.paperSize.height - info.topMargin - info.bottomMargin, 200)
    )
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    waitUntilReady(webView, attemptsRemaining: Self.readinessPollLimit)
  }

  /// Waits for the page to finish loading, fonts to settle and Mermaid to report 'ready', 'failed'
  /// or 'unavailable' (KaTeX renders synchronously while the page loads). Gives up after a few
  /// seconds so a broken diagram can never block printing.
  private func waitUntilReady(_ webView: WKWebView, attemptsRemaining: Int) {
    let script = """
      (document.readyState === 'complete')
        && (!document.fonts || document.fonts.status !== 'loading')
        && (!document.body || document.body.dataset.mermaidReady !== 'pending')
      """

    webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
      guard let self, let webView else { return }

      if (result as? Bool) == true || attemptsRemaining <= 0 {
        // One more beat so layout settles after the last diagram is inserted.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak webView] in
          guard let self, let webView else { return }
          self.runPrintOperation(for: webView)
        }
        return
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + Self.readinessPollInterval) { [weak self, weak webView] in
        guard let self, let webView else { return }
        self.waitUntilReady(webView, attemptsRemaining: attemptsRemaining - 1)
      }
    }
  }

  private func runPrintOperation(for webView: WKWebView) {
    let info = printInfo ?? NSPrintInfo.shared
    let contentSize = printableSize(for: info)

    webView.frame = NSRect(origin: .zero, size: contentSize)

    let operation = webView.printOperation(with: info)
    operation.view?.frame = NSRect(origin: .zero, size: contentSize)
    operation.jobTitle = jobTitle
    // The standard print sheet stays: it carries Save as PDF, paper size and page range.
    operation.showsPrintPanel = true
    operation.showsProgressPanel = true

    if let window {
      operation.runModal(
        for: window,
        delegate: self,
        didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
        contextInfo: nil
      )
    } else {
      operation.run()
      finish()
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    finish()
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    finish()
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    finish()
  }

  @objc private func printOperationDidRun(
    _ operation: NSPrintOperation,
    success: Bool,
    contextInfo: UnsafeMutableRawPointer?
  ) {
    finish()
  }

  private func finish() {
    webView?.navigationDelegate = nil
    webView = nil
    hostWindow?.orderOut(nil)
    hostWindow?.contentView = nil
    hostWindow?.close()
    hostWindow = nil
    printInfo = nil
    window = nil
    completion()
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
