import AppKit

enum MarkdownSourceStyler {
  static let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

  static func apply(to textStorage: NSTextStorage) {
    let fullRange = NSRange(location: 0, length: textStorage.length)
    guard fullRange.length > 0 else { return }

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 2.5
    paragraphStyle.paragraphSpacing = 3

    textStorage.beginEditing()
    textStorage.setAttributes([
      .font: baseFont,
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraphStyle
    ], range: fullRange)

    let text = textStorage.string as NSString
    applyLinePattern("(?m)^(#{1,6})\\s+.*$", in: text, storage: textStorage) { match in
      let level = min(max(match.range(at: 1).length, 1), 6)
      let size = max(15, 23 - (level * 2))
      let font = NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .semibold)
      textStorage.addAttributes([
        .font: font,
        .foregroundColor: NSColor.controlAccentColor
      ], range: match.range)
    }

    applyLinePattern("(?m)^\\s*>.*$", in: text, storage: textStorage) { match in
      textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
    }

    applyLinePattern("(?m)^\\s*([-*+] |\\d+\\. ).*$", in: text, storage: textStorage) { match in
      textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: match.range)
      textStorage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: match.range(at: 1))
    }

    applyPattern("`[^`\\n]+`", in: text, storage: textStorage) { match in
      textStorage.addAttributes([
        .foregroundColor: NSColor.systemPink,
        .backgroundColor: NSColor.textBackgroundColor.blended(withFraction: 0.08, of: .systemPink) ?? NSColor.textBackgroundColor
      ], range: match.range)
    }

    applyPattern("\\[[^\\]]+\\]\\([^)]+\\)", in: text, storage: textStorage) { match in
      textStorage.addAttributes([
        .foregroundColor: NSColor.linkColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue
      ], range: match.range)
    }

    applyPattern("\\*\\*[^*\\n]+\\*\\*", in: text, storage: textStorage) { match in
      textStorage.addAttributes([
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
      ], range: match.range)
    }

    applyPattern("(?<!\\*)\\*[^*\\n]+\\*(?!\\*)", in: text, storage: textStorage) { match in
      let italic = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
      textStorage.addAttribute(.font, value: italic, range: match.range)
    }

    applyLinePattern("(?m)^```.*$", in: text, storage: textStorage) { match in
      textStorage.addAttributes([
        .foregroundColor: NSColor.systemPurple,
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
      ], range: match.range)
    }

    textStorage.endEditing()
  }

  private static func applyPattern(
    _ pattern: String,
    in text: NSString,
    storage: NSTextStorage,
    body: (NSTextCheckingResult) -> Void
  ) {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
    regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
      guard let match else { return }
      body(match)
    }
  }

  private static func applyLinePattern(
    _ pattern: String,
    in text: NSString,
    storage: NSTextStorage,
    body: (NSTextCheckingResult) -> Void
  ) {
    applyPattern(pattern, in: text, storage: storage, body: body)
  }
}

