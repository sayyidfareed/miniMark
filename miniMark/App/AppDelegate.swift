import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var launchOpenPanel: NSOpenPanel?

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    false
  }

  /// Clicking the Dock icon with no window open shows the open panel again, so the app is never left
  /// without a way in after the first panel was cancelled.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag, !isRunningTests, NSDocumentController.shared.documents.isEmpty {
      if let panel = launchOpenPanel {
        panel.makeKeyAndOrderFront(nil)
      } else {
        openInitialDocument()
      }
      return false
    }
    return true
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !isRunningTests else { return }

#if SNAPSHOT_MODE
    if let directory = SnapshotRunner.outputDirectory(from: ProcessInfo.processInfo.arguments) {
      Task { @MainActor in
        await SnapshotRunner(outputDirectory: directory).run()
      }
      return
    }
#endif

    let savedAppearance = UserDefaults.standard.string(forKey: AppAppearance.storageKey)
      ?? AppAppearance.system.rawValue
    AppAppearanceController.apply(savedAppearance)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      guard NSDocumentController.shared.documents.isEmpty else { return }
      self.openInitialDocument()
    }
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
