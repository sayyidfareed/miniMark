import AppKit
import Foundation

final class MarkdownFolderAccessStore {
  static let shared = MarkdownFolderAccessStore()

  private let bookmarksKey = "markdownImageFolderBookmarks"
  private var cachedBookmarks: [String: String]?

  private init() {}

  func data(for fileURL: URL) -> Data? {
    guard let folderURL = resolvedBookmarkedFolder(containing: fileURL) else {
      return nil
    }

    let didStartAccess = folderURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccess {
        folderURL.stopAccessingSecurityScopedResource()
      }
    }

    return try? Data(contentsOf: fileURL)
  }

  func imageURLsNeedingFolderAccess(_ imageURLs: [URL]) -> [URL] {
    imageURLs.filter { !canRead($0) }
  }

  @MainActor
  func requestAccess(
    toFolderContaining imageURLs: [URL],
    documentURL: URL,
    window: NSWindow?
  ) async -> Bool {
    let inaccessibleURLs = imageURLsNeedingFolderAccess(imageURLs)
    guard !inaccessibleURLs.isEmpty else { return false }

    let suggestedFolderURL = suggestedGrantFolder(for: documentURL)
    guard let selectedFolderURL = await chooseFolder(defaultingTo: suggestedFolderURL, window: window) else {
      return false
    }

    do {
      try saveBookmark(for: selectedFolderURL)
      return inaccessibleURLs.contains { fileURL in
        contains(fileURL, in: selectedFolderURL)
      }
    } catch {
      return false
    }
  }

  private func canRead(_ fileURL: URL) -> Bool {
    if canOpen(fileURL) {
      return true
    }

    guard let folderURL = resolvedBookmarkedFolder(containing: fileURL) else {
      return false
    }

    let didStartAccess = folderURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccess {
        folderURL.stopAccessingSecurityScopedResource()
      }
    }

    return canOpen(fileURL)
  }

  private func canOpen(_ fileURL: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
      return false
    }

    try? handle.close()
    return true
  }

  @MainActor
  private func chooseFolder(defaultingTo folderURL: URL, window: NSWindow?) async -> URL? {
    let panel = NSOpenPanel()
    panel.message = "Allow miniMark to read local images for previews. Choose Documents or a project folder."
    panel.prompt = "Allow"
    panel.directoryURL = folderURL
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = true

    let response: NSApplication.ModalResponse
    if let window {
      response = await withCheckedContinuation { continuation in
        panel.beginSheetModal(for: window) { result in
          continuation.resume(returning: result)
        }
      }
    } else {
      response = panel.runModal()
    }

    guard response == .OK else { return nil }
    return panel.url
  }

  private func saveBookmark(for folderURL: URL) throws {
    let normalizedURL = normalizedFolderURL(folderURL)
    let didStartAccess = normalizedURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccess {
        normalizedURL.stopAccessingSecurityScopedResource()
      }
    }

    let bookmark = try normalizedURL.bookmarkData(
      options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    var bookmarks = storedBookmarks()
    bookmarks[normalizedURL.path] = bookmark.base64EncodedString()
    setStoredBookmarks(bookmarks)
  }

  private func suggestedGrantFolder(for documentURL: URL) -> URL {
    let documentFolderURL = documentURL.deletingLastPathComponent()
    guard
      let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
      contains(documentFolderURL, in: documentsURL)
    else {
      return documentFolderURL
    }

    return documentsURL
  }

  private func resolvedBookmarkedFolder(containing fileURL: URL) -> URL? {
    let normalizedFileURL = normalizedFileURL(fileURL)
    let bookmarks = storedBookmarks()
    let candidatePaths = bookmarks.keys
      .filter { path(normalizedFileURL.path, isContainedIn: $0) }
      .sorted { $0.count > $1.count }

    for storedPath in candidatePaths {
      guard let encodedBookmark = bookmarks[storedPath] else { continue }
      guard let bookmark = Data(base64Encoded: encodedBookmark) else {
        pruneBookmark(at: storedPath)
        continue
      }

      var isStale = false
      guard
        let resolvedURL = try? URL(
          resolvingBookmarkData: bookmark,
          options: [.withSecurityScope, .withoutUI],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )
      else {
        continue
      }

      let normalizedFolderURL = normalizedFolderURL(resolvedURL)
      guard contains(normalizedFileURL, in: normalizedFolderURL) else {
        continue
      }

      if isStale {
        try? saveBookmark(for: normalizedFolderURL)
      }

      return normalizedFolderURL
    }

    return nil
  }

  private func storedBookmarks() -> [String: String] {
    if let cachedBookmarks {
      return cachedBookmarks
    }
    let value = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: String] ?? [:]
    cachedBookmarks = value
    return value
  }

  private func setStoredBookmarks(_ bookmarks: [String: String]) {
    cachedBookmarks = bookmarks
    UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
  }

  private func pruneBookmark(at storedPath: String) {
    var bookmarks = storedBookmarks()
    guard bookmarks.removeValue(forKey: storedPath) != nil else { return }
    setStoredBookmarks(bookmarks)
  }

  private func contains(_ fileURL: URL, in folderURL: URL) -> Bool {
    path(normalizedFileURL(fileURL).path, isContainedIn: normalizedFolderURL(folderURL).path)
  }

  private func path(_ filePath: String, isContainedIn folderPath: String) -> Bool {
    let folderPrefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
    return filePath == folderPath || filePath.hasPrefix(folderPrefix)
  }

  private func normalizedFileURL(_ url: URL) -> URL {
    url.standardizedFileURL.resolvingSymlinksInPath()
  }

  private func normalizedFolderURL(_ url: URL) -> URL {
    URL(fileURLWithPath: url.standardizedFileURL.resolvingSymlinksInPath().path, isDirectory: true)
  }
}
