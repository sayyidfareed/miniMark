import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
  static var readableContentTypes: [UTType] {
    [.minimarkMarkdown, .minimarkMarkdownLong]
  }

  /// How the file was encoded when it was opened.
  ///
  /// Encodings that round-trip losslessly (UTF-8, UTF-8 with BOM, UTF-16 with BOM) are written back
  /// as they were found. Legacy 8-bit encodings (Windows-1252 / ISO Latin-1) are a best-effort guess
  /// that cannot be verified, so those documents are saved as UTF-8, which every Markdown tool reads.
  enum SourceEncoding: Equatable {
    case utf8
    case utf8WithBOM
    case utf16LittleEndian
    case utf16BigEndian
    /// Decoded as Windows-1252 or ISO Latin-1 because the bytes were not valid UTF-8; saved as UTF-8.
    case legacyFallback
  }

  var text: String
  private(set) var sourceEncoding: SourceEncoding

  init(text: String = "") {
    self.text = text
    self.sourceEncoding = .utf8
  }

  init(data: Data) throws {
    let decoded = Self.decode(data)
    text = decoded.text
    sourceEncoding = decoded.encoding
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
    switch sourceEncoding {
    case .utf8, .legacyFallback:
      return Data(text.utf8)
    case .utf8WithBOM:
      return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    case .utf16LittleEndian:
      guard let body = text.data(using: .utf16LittleEndian) else { return Data(text.utf8) }
      return Data([0xFF, 0xFE]) + body
    case .utf16BigEndian:
      guard let body = text.data(using: .utf16BigEndian) else { return Data(text.utf8) }
      return Data([0xFE, 0xFF]) + body
    }
  }

  /// Decodes file contents without ever failing, so a file is never refused because of its encoding.
  /// Order: UTF-8 (with or without BOM), UTF-16 with BOM, UTF-8 without BOM, Windows-1252, ISO Latin-1.
  static func decode(_ data: Data) -> (text: String, encoding: SourceEncoding) {
    let bytes = [UInt8](data.prefix(3))

    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
      let body = data.dropFirst(3)
      if let text = String(data: body, encoding: .utf8) {
        return (text, .utf8WithBOM)
      }
    } else if bytes.starts(with: [0xFF, 0xFE]) {
      if let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
        return (text, .utf16LittleEndian)
      }
    } else if bytes.starts(with: [0xFE, 0xFF]) {
      if let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
        return (text, .utf16BigEndian)
      }
    }

    if let text = String(data: data, encoding: .utf8) {
      return (text, .utf8)
    }

    if let text = String(data: data, encoding: .windowsCP1252) {
      return (text, .legacyFallback)
    }

    // ISO Latin-1 maps every byte to a character, so this cannot fail.
    return (String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self), .legacyFallback)
  }
}
