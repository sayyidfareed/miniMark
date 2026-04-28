import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
  static var readableContentTypes: [UTType] {
    [.minimarkMarkdown, .minimarkMarkdownLong]
  }

  var text: String

  init(text: String = "") {
    self.text = text
  }

  init(data: Data) throws {
    guard let decoded = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    text = decoded
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }

    try self.init(data: data)
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: dataRepresentation())
  }

  func dataRepresentation() -> Data {
    Data(text.utf8)
  }
}
