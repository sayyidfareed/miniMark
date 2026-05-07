import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "miniMark/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
  ("icon_16x16.png", 16),
  ("icon_16x16@2x.png", 32),
  ("icon_32x32.png", 32),
  ("icon_32x32@2x.png", 64),
  ("icon_128x128.png", 128),
  ("icon_128x128@2x.png", 256),
  ("icon_256x256.png", 256),
  ("icon_256x256@2x.png", 512),
  ("icon_512x512.png", 512),
  ("icon_512x512@2x.png", 1024)
]

// Render a single "Mm" wordmark — uppercase M followed by lowercase m, tightly kerned —
// as a single bezier path so it can be filled with a gradient and stroked uniformly.
func wordmarkPath(in rect: NSRect, size s: CGFloat) -> NSBezierPath {
  // Use SF Pro / system font, heavy, sized to fill the rect height.
  let targetHeight = rect.height
  // Iterate font size to match cap-height ~ rect.height.
  var fontSize = targetHeight * 1.05
  var font = NSFont.systemFont(ofSize: fontSize, weight: .black)
  let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .kern: -fontSize * 0.04
  ]
  var attr = NSAttributedString(string: "mM", attributes: attrs)
  var measured = attr.size()

  // Refine size so the wordmark fits the rect width and height.
  let widthScale = rect.width / measured.width
  let heightScale = rect.height / measured.height
  let scale = min(widthScale, heightScale)
  fontSize *= scale
  font = NSFont.systemFont(ofSize: fontSize, weight: .black)
  let finalAttrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .kern: -fontSize * 0.04
  ]
  attr = NSAttributedString(string: "mM", attributes: finalAttrs)
  measured = attr.size()

  // Convert glyphs to a CGPath via CoreText, then to NSBezierPath.
  let line = CTLineCreateWithAttributedString(attr)
  let runs = CTLineGetGlyphRuns(line) as! [CTRun]
  let combined = CGMutablePath()
  for run in runs {
    let runAttrs = CTRunGetAttributes(run) as! [NSAttributedString.Key: Any]
    guard let runFont = runAttrs[.font] else { continue }
    let ctFont = runFont as! CTFont
    let glyphCount = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
    var positions = [CGPoint](repeating: .zero, count: glyphCount)
    CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)
    for i in 0..<glyphCount {
      if let glyphPath = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) {
        var t = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
        combined.addPath(glyphPath, transform: t)
      }
    }
  }

  // Center the path inside `rect`.
  let bbox = combined.boundingBox
  let tx = rect.midX - bbox.midX
  let ty = rect.midY - bbox.midY
  let translated = CGMutablePath()
  var transform = CGAffineTransform(translationX: tx, y: ty)
  translated.addPath(combined, transform: transform)

  let bezier = NSBezierPath()
  bezier.append(translated.toNSBezierPath())
  return bezier
}

extension CGPath {
  func toNSBezierPath() -> NSBezierPath {
    let path = NSBezierPath()
    self.applyWithBlock { elementPtr in
      let element = elementPtr.pointee
      let pts = element.points
      switch element.type {
      case .moveToPoint:
        path.move(to: pts[0])
      case .addLineToPoint:
        path.line(to: pts[0])
      case .addQuadCurveToPoint:
        // Approximate quadratic with cubic.
        let current = path.currentPoint
        let cp = pts[0]
        let end = pts[1]
        let cp1 = NSPoint(x: current.x + 2.0/3.0 * (cp.x - current.x),
                          y: current.y + 2.0/3.0 * (cp.y - current.y))
        let cp2 = NSPoint(x: end.x + 2.0/3.0 * (cp.x - end.x),
                          y: end.y + 2.0/3.0 * (cp.y - end.y))
        path.curve(to: end, controlPoint1: cp1, controlPoint2: cp2)
      case .addCurveToPoint:
        path.curve(to: pts[2], controlPoint1: pts[0], controlPoint2: pts[1])
      case .closeSubpath:
        path.close()
      @unknown default: break
      }
    }
    return path
  }
}

func draw(size: Int) -> NSBitmapImageRep {
  let s = CGFloat(size)
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else { fatalError("bitmap") }

  bitmap.size = NSSize(width: size, height: size)
  NSGraphicsContext.saveGraphicsState()
  let ctxWrapper = NSGraphicsContext(bitmapImageRep: bitmap)
  NSGraphicsContext.current = ctxWrapper
  ctxWrapper?.imageInterpolation = .high
  let cg = ctxWrapper!.cgContext

  let inset = s * 0.045
  let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
  let cornerRadius = rect.width * 0.225
  let squircle = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

  // Outer drop shadow.
  if size >= 64 {
    cg.saveGState()
    cg.setShadow(
      offset: CGSize(width: 0, height: -s * 0.012),
      blur: s * 0.04,
      color: NSColor(calibratedWhite: 0, alpha: 0.35).cgColor
    )
    NSColor.black.setFill()
    squircle.fill()
    cg.restoreGState()
  }

  // Background gradient: indigo → violet → deep purple.
  cg.saveGState()
  squircle.addClip()
  let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.31, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.55, green: 0.27, blue: 0.92, alpha: 1),
    NSColor(calibratedRed: 0.31, green: 0.18, blue: 0.78, alpha: 1)
  ], atLocations: [0.0, 0.55, 1.0], colorSpace: .deviceRGB)!
  bgGradient.draw(in: rect, angle: -55)

  // Top inner highlight for glassy depth.
  let highlight = NSGradient(colors: [
    NSColor(calibratedWhite: 1, alpha: 0.20),
    NSColor(calibratedWhite: 1, alpha: 0.0)
  ])!
  highlight.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: 90)

  // Soft radial glow behind the wordmark.
  let glowCenter = NSPoint(x: rect.midX, y: rect.midY)
  let glow = NSGradient(colors: [
    NSColor(calibratedWhite: 1, alpha: 0.18),
    NSColor(calibratedWhite: 1, alpha: 0.0)
  ])!
  glow.draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: rect.width * 0.55, options: [])
  cg.restoreGState()

  // "Mm" wordmark area — fills most of the squircle, slightly inset.
  let markRect = NSRect(
    x: rect.minX + rect.width * 0.12,
    y: rect.minY + rect.height * 0.18,
    width: rect.width * 0.76,
    height: rect.height * 0.64
  )
  let mark = wordmarkPath(in: markRect, size: s)

  // Soft drop shadow under the wordmark.
  if size >= 48 {
    cg.saveGState()
    cg.setShadow(
      offset: CGSize(width: 0, height: -s * 0.010),
      blur: s * 0.025,
      color: NSColor(calibratedRed: 0.05, green: 0.02, blue: 0.18, alpha: 0.55).cgColor
    )
    NSColor.white.setFill()
    mark.fill()
    cg.restoreGState()
  } else {
    NSColor.white.setFill()
    mark.fill()
  }

  // Subtle gradient overlay on the wordmark for premium depth (white → faint cool tint).
  if size >= 64 {
    cg.saveGState()
    mark.addClip()
    let markGradient = NSGradient(colors: [
      NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
      NSColor(calibratedRed: 0.92, green: 0.93, blue: 1.00, alpha: 1)
    ])!
    markGradient.draw(in: markRect, angle: -90)
    cg.restoreGState()
  }

  // Tiny accent dot for miniMark, placed after the lowercase m to subtly
  // echo the brand name. Acts like a punctuation period at the baseline.
  if size >= 48 {
    let bbox = mark.bounds
    let dotDiameter = bbox.height * 0.18
    let dotRect = NSRect(
      x: bbox.maxX + dotDiameter * 0.45,
      y: bbox.minY,
      width: dotDiameter,
      height: dotDiameter
    )
    if dotRect.maxX < rect.maxX - rect.width * 0.06 {
      NSColor(calibratedRed: 0.75, green: 0.92, blue: 1.0, alpha: 1).setFill()
      NSBezierPath(ovalIn: dotRect).fill()
    }
  }

  NSGraphicsContext.restoreGraphicsState()
  return bitmap
}

for (filename, size) in sizes {
  let bitmap = draw(size: size)
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render \(filename)")
  }
  try png.write(to: outputURL.appendingPathComponent(filename), options: .atomic)
}
