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
        if trimmed.hasPrefix("```") {
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

      if trimmed.hasPrefix("```") {
        flushParagraph()
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

      if let item = capture(in: trimmed, pattern: #"^[-*+]\s+(.+)$"#, index: 1) {
        flushParagraph()
        output.append("- \(renderInline(item))")
        index += 1
        continue
      }

      if let ordered = firstMatch(in: trimmed, pattern: #"^(\d+[.)])\s+(.+)$"#),
         let marker = ordered.capture(1, in: trimmed),
         let item = ordered.capture(2, in: trimmed) {
        flushParagraph()
        output.append("\(marker) \(renderInline(item))")
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

  private static func renderInline(_ markdown: String) -> String {
    var text = markdown

    text = replacingMatches(in: text, pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) { match, source in
      let alt = match.capture(1, in: source) ?? ""
      let path = match.capture(2, in: source) ?? ""
      return alt.isEmpty ? path : alt
    }
    text = replacingMatches(in: text, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) { match, source in
      match.capture(1, in: source) ?? ""
    }
    text = replacingMatches(in: text, pattern: #"`([^`]+)`"#) { match, source in
      match.capture(1, in: source) ?? ""
    }
    text = replacingMatches(in: text, pattern: #"\*\*([^*]+)\*\*"#) { match, source in
      match.capture(1, in: source) ?? ""
    }
    text = replacingMatches(in: text, pattern: #"__([^_]+)__"#) { match, source in
      match.capture(1, in: source) ?? ""
    }
    text = replacingMatches(in: text, pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#) { match, source in
      match.capture(1, in: source) ?? ""
    }
    text = replacingMatches(in: text, pattern: #"(?<!_)_([^_]+)_(?!_)"#) { match, source in
      match.capture(1, in: source) ?? ""
    }

    return text
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
  }

  private static func capture(in text: String, pattern: String, index: Int) -> String? {
    firstMatch(in: text, pattern: pattern)?.capture(index, in: text)
  }

  private static func firstMatch(in text: String, pattern: String) -> NSTextCheckingResult? {
    regularExpression(for: pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
  }

  private static func replacingMatches(
    in text: String,
    pattern: String,
    transform: (NSTextCheckingResult, String) -> String
  ) -> String {
    let regex = regularExpression(for: pattern)
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
    do {
      return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    } catch {
      preconditionFailure("Invalid regular expression: \(pattern)")
    }
  }
}

@MainActor
private final class MarkdownPrintController: NSObject, WKNavigationDelegate {
  private let completion: () -> Void
  private var webView: WKWebView?
  private weak var window: NSWindow?

  init(completion: @escaping () -> Void) {
    self.completion = completion
  }

  func print(_ context: MarkdownExportContext) {
    window = NSApp.keyWindow

    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true

    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 760, height: 980), configuration: configuration)
    webView.navigationDelegate = self
    self.webView = webView

    let html = MarkdownPreviewHTMLRenderer.htmlDocument(
      for: context.markdown,
      baseURL: context.baseURL,
      mode: .print
    )
    webView.loadHTMLString(html, baseURL: context.baseURL)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    waitForMermaid(in: webView, attemptsRemaining: 100)
  }

  private func waitForMermaid(in webView: WKWebView, attemptsRemaining: Int) {
    webView.evaluateJavaScript(
      "document.body.dataset.mermaidReady !== 'pending'"
    ) { [weak self, weak webView] result, _ in
      guard let self, let webView else { return }

      if (result as? Bool) == true || attemptsRemaining <= 0 {
        self.runPrintOperation(for: webView)
        return
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak webView] in
        guard let self, let webView else { return }
        self.waitForMermaid(in: webView, attemptsRemaining: attemptsRemaining - 1)
      }
    }
  }

  private func runPrintOperation(for webView: WKWebView) {
    let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
    printInfo.topMargin = 52
    printInfo.bottomMargin = 52
    printInfo.leftMargin = 52
    printInfo.rightMargin = 52
    printInfo.horizontalPagination = .fit
    printInfo.verticalPagination = .automatic

    let operation = webView.printOperation(with: printInfo)
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

  @objc private func printOperationDidRun(
    _ operation: NSPrintOperation,
    success: Bool,
    contextInfo: UnsafeMutableRawPointer?
  ) {
    finish()
  }

  private func finish() {
    self.webView = nil
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
