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

    // Window captures: (key, document, mode, dark). The four "raw" ones are the plain window pictures used
    // on the landing page; the others only feed the App Store frames below.
    let shots: [(key: String, doc: SnapshotSampleDocument.Sample, mode: DocumentView.Mode, dark: Bool, raw: Bool)] = [
      ("source-light", .releaseNotes, .source, false, true),
      ("preview-light", .releaseNotes, .preview, false, true),
      ("source-dark", .releaseNotes, .source, true, true),
      ("preview-dark", .releaseNotes, .preview, true, true),
      ("orbits-light", .orbits, .preview, false, false),
      ("orbits-dark", .orbits, .preview, true, false),
      ("code-light", .code, .preview, false, false)
    ]

    // The app's own appearance setting decides the colours, so set it for each picture and put it back after.
    let defaults = UserDefaults.standard
    let savedAppearance = defaults.string(forKey: AppAppearance.storageKey)
    var windows: [String: CGImage] = [:]
    // The first window of a launch can be captured before the app is frontmost (grey title bar buttons), so
    // take one throwaway picture first.
    defaults.set(AppAppearance.light.rawValue, forKey: AppAppearance.storageKey)
    AppAppearanceController.apply(AppAppearance.light.rawValue)
    _ = await capture(name: "warm-up", sample: .releaseNotes, mode: .preview, appearance: .aqua, writeRaw: false)
    for shot in shots {
      let setting: AppAppearance = shot.dark ? .dark : .light
      defaults.set(setting.rawValue, forKey: AppAppearance.storageKey)
      AppAppearanceController.apply(setting.rawValue)
      windows[shot.key] = await capture(
        name: shot.key, sample: shot.doc, mode: shot.mode,
        appearance: shot.dark ? .darkAqua : .aqua, writeRaw: shot.raw
      )
    }

    // App Store frames: a headline over the real window, in the landing page's colours.
    for frame in StoreFrame.all {
      guard let window = windows[frame.window] else { log("\(frame.file): no window capture"); continue }
      guard let image = compose(frame, window: window) else { log("\(frame.file): compose failed"); continue }
      if let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
        try? data.write(to: outputDirectory.appendingPathComponent("\(frame.file).png"))
        log("\(frame.file): written")
      }
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

  /// Captures one window. Writes the cropped window PNG when `writeRaw` is set and returns the full window
  /// image (title bar and rounded corners included) for the App Store frames.
  private func capture(
    name: String, sample: SnapshotSampleDocument.Sample, mode: DocumentView.Mode,
    appearance: NSAppearance.Name, writeRaw: Bool
  ) async -> CGImage? {
    lastFullWindow = nil
    let document = SnapshotDocumentBox(text: sample.markdown)
    let root = SnapshotHost(box: document, coordinator: coordinator, mode: mode)
    let hosting = NSHostingView(rootView: root)

    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: windowSize),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = sample.title
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
      return nil
    }

    if writeRaw, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
      try? data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
    window.orderOut(nil)
    return lastFullWindow
  }

  /// The most recent uncropped window image, kept by `windowImage(of:)`.
  private var lastFullWindow: CGImage?

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
    lastFullWindow = full
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

  // MARK: App Store frames

  private func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
  }

  /// Draws one 2880x1800 App Store picture: background, a one-line headline with one phrase marked in the
  /// highlighter yellow of the landing page, a smaller line under it, and the real window below with a shadow.
  private func compose(_ frame: StoreFrame, window: CGImage) -> CGImage? {
    guard let context = makeContext() else { return nil }
    let width = CGFloat(pixelWidth), height = CGFloat(pixelHeight)
    let background = frame.dark ? color(0x0E1012) : color(0xF4F5F2)
    let ink = frame.dark ? color(0xEDEFEA) : color(0x111418)
    let muted = frame.dark ? color(0x9CA5AC) : color(0x556069)
    let marker = color(0xFFE14D)

    context.setFillColor(background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics

    // Headline, shrunk if it would run wider than the margins.
    var size: CGFloat = 132
    func pieces(_ size: CGFloat) -> [NSAttributedString] {
      frame.headline.map { part in
        NSAttributedString(string: part.text, attributes: [
          .font: NSFont.systemFont(ofSize: size, weight: .bold),
          .foregroundColor: part.marked ? color(0x111418) : ink,
          .kern: -size * 0.02
        ])
      }
    }
    var parts = pieces(size)
    while parts.reduce(0, { $0 + $1.size().width }) > width - 280, size > 80 {
      size -= 4
      parts = pieces(size)
    }
    let total = parts.reduce(0) { $0 + $1.size().width }
    let baselineTop: CGFloat = 250
    var x = (width - total) / 2
    let lineY = height - baselineTop - size * 0.8
    for (part, piece) in zip(frame.headline, parts) {
      let pieceSize = piece.size()
      if part.marked {
        let rect = NSRect(x: x - size * 0.12, y: lineY - size * 0.12, width: pieceSize.width + size * 0.24, height: size * 0.95)
        marker.setFill()
        NSBezierPath(roundedRect: rect, xRadius: size * 0.12, yRadius: size * 0.12).fill()
      }
      piece.draw(at: NSPoint(x: x, y: lineY - size * 0.2))
      x += pieceSize.width
    }

    // The line under the headline.
    let sub = NSAttributedString(string: frame.subline, attributes: [
      .font: NSFont.systemFont(ofSize: 54, weight: .regular),
      .foregroundColor: muted
    ])
    let subSize = sub.size()
    sub.draw(at: NSPoint(x: (width - subSize.width) / 2, y: lineY - size * 0.2 - 110))
    NSGraphicsContext.restoreGraphicsState()

    // The window, centred, running off the bottom edge, with a soft shadow.
    let windowWidth: CGFloat = 2360
    let scale = windowWidth / CGFloat(window.width)
    let windowHeight = CGFloat(window.height) * scale
    let top: CGFloat = 560
    let rect = CGRect(x: (width - windowWidth) / 2, y: height - top - windowHeight, width: windowWidth, height: windowHeight)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 90, color: NSColor.black.withAlphaComponent(frame.dark ? 0.55 : 0.22).cgColor)
    context.interpolationQuality = .high
    context.draw(window, in: rect)
    context.restoreGState()

    return context.makeImage()
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
/// One App Store picture: which window capture it shows and the words over it. Claims must be things the
/// app does (guideline 2.3.14: no unverifiable claims, no prices).
private struct StoreFrame {
  let file: String
  let window: String
  let dark: Bool
  let headline: [(text: String, marked: Bool)]
  let subline: String

  static let all: [StoreFrame] = [
    StoreFrame(
      file: "store-1", window: "preview-light", dark: false,
      headline: [("The tiny ", false), ("Markdown", true), (" editor for your Mac", false)],
      subline: "Write in plain text. Press Shift-Command-P to see it beautifully rendered."
    ),
    StoreFrame(
      file: "store-2", window: "source-light", dark: false,
      headline: [("Plain text you ", false), ("own", true)],
      subline: "Ordinary .md files, styled as you type. No account, no library, no lock-in."
    ),
    StoreFrame(
      file: "store-3", window: "orbits-light", dark: false,
      headline: [("Math, diagrams and tables, ", false), ("built in", true)],
      subline: "LaTeX, Mermaid diagrams, task lists, footnotes and tables render right in the preview."
    ),
    StoreFrame(
      file: "store-4", window: "code-light", dark: false,
      headline: [("Code that ", false), ("reads", true), (" like code", false)],
      subline: "Syntax highlighting in fenced code blocks, with a copy button on each one."
    ),
    StoreFrame(
      file: "store-5", window: "orbits-dark", dark: true,
      headline: [("Easy on the eyes, ", false), ("day or night", true)],
      subline: "Light, dark or follow your Mac. Export TXT, RTF or HTML, or print to PDF."
    )
  ]
}
#endif
