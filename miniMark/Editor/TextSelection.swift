import Foundation

struct TextSelection: Equatable {
  var location: Int
  var length: Int

  static let zero = TextSelection(location: 0, length: 0)

  var nsRange: NSRange {
    NSRange(location: location, length: length)
  }

  init(location: Int, length: Int) {
    self.location = max(0, location)
    self.length = max(0, length)
  }

  init(_ range: NSRange) {
    self.init(location: range.location, length: range.length)
  }

  func clamped(to utf16Length: Int) -> TextSelection {
    let boundedLocation = min(max(0, location), max(0, utf16Length))
    let boundedLength = min(max(0, length), max(0, utf16Length - boundedLocation))
    return TextSelection(location: boundedLocation, length: boundedLength)
  }
}

