// Compiled only when SNAPSHOT_MODE is set (the screenshot build). Not part of the App Store build.
#if SNAPSHOT_MODE
import AppKit
import SwiftUI
import WebKit

/// Renders the app's own window to PNG files for the App Store listing.
///
/// Launch with `--snapshot <name>`. Writes 2880x1800 opaque PNGs (a 1440x900
/// window at 2x) for source and preview, light and dark, then quits. It draws its
/// own views instead of capturing the screen, so nothing else on the desktop is read.
@MainActor
final class SnapshotRunner {
  private let outputDirectory: URL
  private let coordinator = MarkdownExportCoordinator()
  private let windowSize = NSSize(width: 1440, height: 900)

  /// `--snapshot <name>` writes into a folder called `<name>` inside the app's own
  /// temporary directory, because the sandbox does not allow writing elsewhere.
  static func outputDirectory(from arguments: [String]) -> URL? {
    guard
      let flag = arguments.firstIndex(of: "--snapshot"),
      arguments.indices.contains(flag + 1)
    else { return nil }
    let name = arguments[flag + 1].replacingOccurrences(of: "/", with: "-")
    return FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
  }

  init(outputDirectory: URL) {
    self.outputDirectory = outputDirectory
  }

  func run() async {
    try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    NSApp.setActivationPolicy(.regular)
    logSession()

    let variants: [(name: String, mode: DocumentView.Mode, appearance: NSAppearance.Name)] = [
      ("source-light", .source, .aqua),
      ("preview-light", .preview, .aqua),
      ("source-dark", .source, .darkAqua),
      ("preview-dark", .preview, .darkAqua)
    ]

    for variant in variants {
      await capture(name: variant.name, mode: variant.mode, appearance: variant.appearance)
    }

    print("snapshot-output: \(outputDirectory.path)")
    fflush(stdout)
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
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)

    // Let SwiftUI lay out and the preview load, including Mermaid and KaTeX.
    try? await Task.sleep(for: .seconds(mode == .preview ? 4 : 1.5))
    hosting.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    log("\(name): visible=\(window.isVisible) occlusion-visible=\(window.occlusionState.contains(.visible)) active=\(NSApp.isActive) webviews=\(webViews(in: hosting).count) bounds=\(hosting.bounds.size)")

    guard let image = await renderImage(of: hosting, label: name) else {
      log("\(name): no image produced")
      window.orderOut(nil)
      return
    }

    if let data = pngData(from: image) {
      try? data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
    window.orderOut(nil)
  }

  /// Prints a line the run script keeps in snapshot.log, so a failed capture explains itself.
  private func log(_ message: String) {
    print("snapshot: \(message)")
    fflush(stdout)
  }

  /// What the login session looks like: a locked or sleeping screen is the usual reason nothing draws.
  private func logSession() {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    let locked = session["CGSSessionScreenIsLocked"] ?? "no"
    let console = session["kCGSSessionOnConsoleKey"] ?? "unknown"
    log("session: screens=\(NSScreen.screens.count) locked=\(locked) onConsole=\(console) policy=\(NSApp.activationPolicy().rawValue)")
  }

  private func newBitmap(for bounds: NSRect) -> NSBitmapImageRep? {
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
    return rep
  }

  /// True when every sampled pixel is the same colour, which means nothing was drawn.
  private func isBlank(_ rep: NSBitmapImageRep) -> Bool {
    guard let first = rep.colorAt(x: 0, y: 0) else { return true }
    for column in stride(from: 0, to: rep.pixelsWide, by: max(1, rep.pixelsWide / 48)) {
      for row in stride(from: 0, to: rep.pixelsHigh, by: max(1, rep.pixelsHigh / 30)) {
        guard let color = rep.colorAt(x: column, y: row) else { continue }
        if abs(color.redComponent - first.redComponent) > 0.01
          || abs(color.greenComponent - first.greenComponent) > 0.01
          || abs(color.blueComponent - first.blueComponent) > 0.01 {
          return false
        }
      }
    }
    return true
  }

  /// Tries several ways to draw the native views and keeps the first that draws something.
  private func renderNative(of view: NSView, label: String) -> NSBitmapImageRep? {
    let bounds = view.bounds
    var attempts: [(String, () -> NSBitmapImageRep?)] = []

    attempts.append(("cacheDisplay") {
      guard let rep = self.newBitmap(for: bounds) else { return nil }
      view.cacheDisplay(in: bounds, to: rep)
      return rep
    })
    attempts.append(("cachingRep") {
      guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
      view.cacheDisplay(in: bounds, to: rep)
      return rep
    })
    attempts.append(("layer.render") {
      guard let rep = self.newBitmap(for: bounds), let layer = view.layer,
        let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext
      else { return nil }
      context.scaleBy(x: 2, y: 2)
      layer.render(in: context)
      return rep
    })

    for (name, attempt) in attempts {
      guard let rep = attempt() else { log("\(label): \(name) gave no bitmap"); continue }
      let blank = isBlank(rep)
      log("\(label): \(name) blank=\(blank)")
      if !blank { return rep }
    }
    return nil
  }

  private func renderImage(of view: NSView, label: String) async -> NSBitmapImageRep? {
    let bounds = view.bounds
    guard let rep = renderNative(of: view, label: label) ?? newBitmap(for: bounds) else { return nil }

    // Web views are not captured by cacheDisplay, so snapshot and draw them on top.
    for webView in webViews(in: view) {
      guard let snapshot = await webSnapshot(of: webView, label: label) else { continue }
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

    log("\(label): final blank=\(isBlank(rep))")
    return rep
  }

  /// Takes a web view snapshot, giving up after ten seconds so one stuck page cannot stall the run.
  private func webSnapshot(of webView: WKWebView, label: String) async -> NSImage? {
    await withCheckedContinuation { continuation in
      var finished = false
      let finish: (NSImage?) -> Void = { image in
        guard !finished else { return }
        finished = true
        continuation.resume(returning: image)
      }
      webView.takeSnapshot(with: nil) { image, error in
        if let error { self.log("\(label): web snapshot failed: \(error.localizedDescription)") }
        finish(image)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        if !finished { self.log("\(label): web snapshot timed out") }
        finish(nil)
      }
    }
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
#endif
