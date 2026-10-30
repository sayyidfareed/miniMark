import AppKit
import SwiftUI
import WebKit

/// Renders the app's own window to PNG files for the App Store listing.
///
/// Launch with `--snapshot <directory>`. Writes 2880x1800 opaque PNGs (a 1440x900
/// window at 2x) for source and preview, light and dark, then quits. It draws its
/// own views instead of capturing the screen, so nothing else on the desktop is read.
@MainActor
final class SnapshotRunner {
  private let outputDirectory: URL
  private let coordinator = MarkdownExportCoordinator()
  private let windowSize = NSSize(width: 1440, height: 900)

  static func outputDirectory(from arguments: [String]) -> URL? {
    guard
      let flag = arguments.firstIndex(of: "--snapshot"),
      arguments.indices.contains(flag + 1)
    else { return nil }
    return URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
  }

  init(outputDirectory: URL) {
    self.outputDirectory = outputDirectory
  }

  func run() async {
    try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let variants: [(name: String, mode: DocumentView.Mode, appearance: NSAppearance.Name)] = [
      ("source-light", .source, .aqua),
      ("preview-light", .preview, .aqua),
      ("source-dark", .source, .darkAqua),
      ("preview-dark", .preview, .darkAqua)
    ]

    for variant in variants {
      await capture(name: variant.name, mode: variant.mode, appearance: variant.appearance)
    }

    NSApp.terminate(nil)
  }

  private func capture(name: String, mode: DocumentView.Mode, appearance: NSAppearance.Name) async {
    let document = SnapshotDocumentBox(text: SnapshotSampleDocument.markdown)
    let root = SnapshotHost(box: document, coordinator: coordinator, mode: mode)
    let hosting = NSHostingView(rootView: root)

    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: windowSize),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Release notes.md"
    window.appearance = NSAppearance(named: appearance)
    window.contentView = hosting
    window.setContentSize(windowSize)
    window.center()
    window.orderFrontRegardless()

    // Let SwiftUI lay out and the preview load, including Mermaid and KaTeX.
    try? await Task.sleep(for: .seconds(mode == .preview ? 4 : 1.5))
    hosting.layoutSubtreeIfNeeded()

    guard let image = await renderImage(of: hosting) else {
      window.orderOut(nil)
      return
    }

    if let data = pngData(from: image) {
      try? data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
    window.orderOut(nil)
  }

  private func renderImage(of view: NSView) async -> NSBitmapImageRep? {
    let bounds = view.bounds
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bounds.width * 2),
        pixelsHigh: Int(bounds.height * 2),
        bitsPerSample: 8,
        samplesPerPixel: 3,
        hasAlpha: false,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else { return nil }
    rep.size = bounds.size

    // Native views (the source editor, toolbar, status bar).
    view.cacheDisplay(in: bounds, to: rep)

    // Web views are not captured by cacheDisplay, so snapshot and draw them on top.
    for webView in webViews(in: view) {
      guard let snapshot = try? await webView.takeSnapshot(configuration: nil) else { continue }
      let frame = webView.convert(webView.bounds, to: view)
      NSGraphicsContext.saveGraphicsState()
      if let context = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.current = context
        let flipped = NSRect(
          x: frame.minX,
          y: view.isFlipped ? frame.minY : bounds.height - frame.maxY,
          width: frame.width,
          height: frame.height
        )
        snapshot.draw(in: flipped)
      }
      NSGraphicsContext.restoreGraphicsState()
    }

    return rep
  }

  private func webViews(in view: NSView) -> [WKWebView] {
    var found: [WKWebView] = []
    if let webView = view as? WKWebView { found.append(webView) }
    for subview in view.subviews { found += webViews(in: subview) }
    return found
  }

  private func pngData(from rep: NSBitmapImageRep) -> Data? {
    rep.representation(using: .png, properties: [:])
  }
}

private final class SnapshotDocumentBox: ObservableObject {
  @Published var document: MarkdownDocument

  init(text: String) {
    document = MarkdownDocument(text: text)
  }
}

private struct SnapshotHost: View {
  @ObservedObject var box: SnapshotDocumentBox
  let coordinator: MarkdownExportCoordinator
  let mode: DocumentView.Mode

  var body: some View {
    DocumentView(
      document: $box.document,
      fileURL: nil,
      exportCoordinator: coordinator,
      initialMode: mode
    )
    .frame(width: 1440, height: 900)
  }
}
