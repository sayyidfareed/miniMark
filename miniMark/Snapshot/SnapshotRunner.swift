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
    // Remove pictures left by an earlier run so a failed capture cannot pass for a new one.
    let leftovers = (try? FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil)) ?? []
    for file in leftovers where file.pathExtension == "png" { try? FileManager.default.removeItem(at: file) }
    NSApp.setActivationPolicy(.regular)
    logSession()

    let variants: [(name: String, mode: DocumentView.Mode, appearance: NSAppearance.Name)] = [
      ("source-light", .source, .aqua),
      ("preview-light", .preview, .aqua),
      ("source-dark", .source, .darkAqua),
      ("preview-dark", .preview, .darkAqua)
    ]

    // The app's own appearance setting decides the colours, so set it for each picture and put it back after.
    let defaults = UserDefaults.standard
    let savedAppearance = defaults.string(forKey: AppAppearance.storageKey)
    for variant in variants {
      let setting: AppAppearance = variant.appearance == .darkAqua ? .dark : .light
      defaults.set(setting.rawValue, forKey: AppAppearance.storageKey)
      AppAppearanceController.apply(setting.rawValue)
      await capture(name: variant.name, mode: variant.mode, appearance: variant.appearance)
    }
    if let savedAppearance {
      defaults.set(savedAppearance, forKey: AppAppearance.storageKey)
    } else {
      defaults.removeObject(forKey: AppAppearance.storageKey)
    }

    print("snapshot-output: \(outputDirectory.path)")
    fflush(stdout)
    NSApp.terminate(nil)
  }

  private let pixelWidth = 2880
  private let pixelHeight = 1800

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
    try? await Task.sleep(for: .seconds(mode == .preview ? 5 : 2))
    hosting.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    log("\(name): visible=\(window.isVisible) occlusion-visible=\(window.occlusionState.contains(.visible)) active=\(NSApp.isActive) webviews=\(webViews(in: hosting).count) bounds=\(hosting.bounds.size)")

    guard let image = await renderImage(of: hosting, in: window, label: name) else {
      log("\(name): no image produced")
      window.orderOut(nil)
      return
    }

    let rep = NSBitmapImageRep(cgImage: image)
    if let data = rep.representation(using: .png, properties: [:]) {
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

  /// An opaque 2880x1800 drawing surface. Drawing goes through a CGContext because AppKit refuses
  /// to make a graphics context from a bitmap without an alpha channel.
  private func makeContext() -> CGContext? {
    CGContext(
      data: nil,
      width: pixelWidth,
      height: pixelHeight,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
  }

  /// True when every sampled pixel is the same colour, which means nothing was drawn.
  private func isBlank(_ image: CGImage) -> Bool {
    let rep = NSBitmapImageRep(cgImage: image)
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

  /// The app's own window as the window server composites it. CGWindowListCreateImage is looked up at
  /// run time because newer SDKs no longer declare it; asking for one of this app's own windows needs no
  /// screen-recording permission. The title bar is cropped so the picture matches the 1440x900 content.
  private func windowImage(of window: NSWindow) -> CGImage? {
    typealias Function = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
      log("CGWindowListCreateImage is not available")
      return nil
    }
    guard let windowID = UInt32(exactly: window.windowNumber), windowID > 0 else {
      log("the window has no window-server id")
      return nil
    }
    let function = unsafeBitCast(symbol, to: Function.self)
    // kCGWindowListOptionIncludingWindow, kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution
    guard let full = function(CGRect.null, 8, windowID, 1 | 8)?.takeRetainedValue() else { return nil }
    log("window image \(full.width)x\(full.height)")
    let crop = full.height - pixelHeight
    guard full.width == pixelWidth, crop >= 0,
      let content = full.cropping(to: CGRect(x: 0, y: crop, width: pixelWidth, height: pixelHeight))
    else { return nil }
    return content
  }

  /// The window image carries an alpha channel; App Store screenshots must not, so redraw it opaque.
  private func opaque(_ image: CGImage) -> CGImage {
    guard let context = makeContext() else { return image }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    return context.makeImage() ?? image
  }

  /// The native views drawn by AppKit itself (works for classic views, may not for SwiftUI).
  private func cacheDisplayImage(of view: NSView) -> CGImage? {
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: pixelHeight, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = view.bounds.size
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.cgImage
  }

  private func layerImage(of view: NSView) -> CGImage? {
    guard let layer = view.layer, let context = makeContext() else { return nil }
    context.scaleBy(x: 2, y: 2)
    layer.render(in: context)
    return context.makeImage()
  }

  private func pdfImage(of view: NSView) -> CGImage? {
    let data = view.dataWithPDF(inside: view.bounds)
    guard let provider = CGDataProvider(data: data as CFData),
      let document = CGPDFDocument(provider), let page = document.page(at: 1),
      let context = makeContext()
    else { return nil }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    context.scaleBy(x: 2, y: 2)
    context.drawPDFPage(page)
    return context.makeImage()
  }

  /// Tries several ways to draw the window and keeps the first that draws something.
  private func renderImage(of view: NSView, in window: NSWindow, label: String) async -> CGImage? {
    // 1. The window as composited by the window server (web content included).
    if let image = windowImage(of: window) {
      let blank = isBlank(image)
      log("\(label): windowList blank=\(blank)")
      if !blank { return opaque(image) }
    }

    // 2. AppKit drawing of the views, with the web views snapshotted and laid on top.
    let attempts: [(String, () -> CGImage?)] = [
      ("cacheDisplay", { self.cacheDisplayImage(of: view) }),
      ("layer.render", { self.layerImage(of: view) }),
      ("pdf", { self.pdfImage(of: view) })
    ]
    for (name, attempt) in attempts {
      guard let native = attempt() else { log("\(label): \(name) gave no image"); continue }
      let blank = isBlank(native)
      log("\(label): \(name) blank=\(blank)")
      if blank { continue }
      return await addWebViews(to: native, view: view, label: label)
    }
    return nil
  }

  /// Web views are not captured by AppKit drawing, so snapshot them and draw them on top.
  private func addWebViews(to native: CGImage, view: NSView, label: String) async -> CGImage? {
    guard let context = makeContext() else { return nil }
    context.draw(native, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    for webView in webViews(in: view) {
      guard let snapshot = await webSnapshot(of: webView, label: label) else { return nil }
      let frame = webView.convert(webView.bounds, to: view)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = graphics
      context.scaleBy(x: 2, y: 2)
      let y = view.isFlipped ? view.bounds.height - frame.maxY : frame.minY
      snapshot.draw(in: NSRect(x: frame.minX, y: y, width: frame.width, height: frame.height))
      context.scaleBy(x: 0.5, y: 0.5)
      NSGraphicsContext.restoreGraphicsState()
    }
    return context.makeImage()
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
