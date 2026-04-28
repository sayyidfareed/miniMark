import AppKit
import Highlightr
import MarkdownUI
import SwiftUI

struct HighlightrCodeSyntaxHighlighter: CodeSyntaxHighlighter {
  private let highlightr: Highlightr?

  init(themeName: String) {
    let highlightr = Highlightr()
    highlightr?.setTheme(to: themeName)
    self.highlightr = highlightr
  }

  func highlightCode(_ code: String, language: String?) -> Text {
    let languageName = normalizedLanguage(language)
    guard let highlighted = highlightr?.highlight(code, as: languageName) else {
      return Text(code)
    }

    if let attributed = try? AttributedString(highlighted, including: \.appKit) {
      return Text(attributed)
    }

    return Text(highlighted.string)
  }

  private func normalizedLanguage(_ language: String?) -> String? {
    guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !language.isEmpty
    else {
      return nil
    }

    switch language {
    case "js":
      return "javascript"
    case "ts":
      return "typescript"
    case "sh", "zsh", "shell":
      return "bash"
    case "objc", "objective-c":
      return "objectivec"
    case "c++":
      return "cpp"
    default:
      return language
    }
  }
}

extension CodeSyntaxHighlighter where Self == HighlightrCodeSyntaxHighlighter {
  static func highlightr(themeName: String) -> Self {
    HighlightrCodeSyntaxHighlighter(themeName: themeName)
  }
}

