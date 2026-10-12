import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
  private static let defaultMarkdownPromptShownKey = "defaultMarkdownPromptShown"
  private var launchOpenPanel: NSOpenPanel?

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !isRunningTests else { return }

    let savedAppearance = UserDefaults.standard.string(forKey: AppAppearance.storageKey)
      ?? AppAppearance.system.rawValue
    AppAppearanceController.apply(savedAppearance)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      self.promptToBecomeDefaultMarkdownApplicationIfNeeded()
      guard NSDocumentController.shared.documents.isEmpty else { return }
      self.openInitialDocument()
    }
  }

  private func promptToBecomeDefaultMarkdownApplicationIfNeeded() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: Self.defaultMarkdownPromptShownKey) else { return }

    defaults.set(true, forKey: Self.defaultMarkdownPromptShownKey)

    let alert = NSAlert()
    alert.messageText = "Make miniMark your default Markdown app?"
    alert.informativeText = "Markdown files (.md and .markdown) will open in miniMark when you double-click them. You can change this later in Finder."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Make Default")
    alert.addButton(withTitle: "Not Now")

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    makeDefaultMarkdownApplication()
  }

  private func makeDefaultMarkdownApplication() {
    let applicationURL = Bundle.main.bundleURL
    let contentTypes = [
      UTType("app.minimark.markdown"),
      UTType("net.daringfireball.markdown"),
      UTType("public.markdown"),
      UTType.minimarkMarkdown,
      UTType.minimarkMarkdownLong
    ]
    .compactMap { $0 }

    let uniqueContentTypes = Dictionary(
      contentTypes.map { ($0.identifier, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    .values

    Task { @MainActor in
      do {
        for contentType in uniqueContentTypes {
          try await NSWorkspace.shared.setDefaultApplication(
            at: applicationURL,
            toOpen: contentType
          )
        }
      } catch {
        showDefaultApplicationError(error)
      }
    }
  }

  private func showDefaultApplicationError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Couldn’t Make miniMark the Default"
    alert.informativeText = error.localizedDescription
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func openInitialDocument() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = MarkdownDocument.readableContentTypes
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.resolvesAliases = true

    launchOpenPanel = panel
    panel.begin { [weak self, weak panel] response in
      guard let self else { return }
      defer {
        panel?.orderOut(nil)
        self.launchOpenPanel = nil
      }

      guard response == .OK, let url = panel?.url else { return }
      panel?.close()
      NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
  }

  private var isRunningTests: Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCTestConfigurationFilePath"] != nil
      || environment["XCTestBundlePath"] != nil
      || NSClassFromString("XCTestCase") != nil
  }
}
