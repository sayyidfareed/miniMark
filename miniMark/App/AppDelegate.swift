import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var launchOpenPanel: NSOpenPanel?
  private var mainWindowObserver: NSObjectProtocol?

  /// Set when AppKit asks whether to open an untitled document at launch. AppKit only asks after it
  /// has processed the launch's open-documents Apple event and window restoration, so this means the
  /// app was launched without anything to open.
  private var launchHadNothingToOpen = false

  /// How long to wait for a Finder double-click or state restoration to produce a document before
  /// showing the open panel, depending on whether AppKit has reported "nothing to open" yet.
  private static let settleDelayWhenLaunchedEmpty: TimeInterval = 0.3
  private static let settleDelayOtherwise: TimeInterval = 1.5
  private static let pollInterval: TimeInterval = 0.15

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    launchHadNothingToOpen = true
    return false
  }

  /// Clicking the Dock icon with no window open shows the open panel again, so the app is never left
  /// without a way in after the first panel was cancelled.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag, !isRunningTests, NSDocumentController.shared.documents.isEmpty {
      if let panel = launchOpenPanel {
        NSApp.activate(ignoringOtherApps: true)
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

    // A document opening from Finder or being restored must never get an open panel on top of it.
    // Instead of a fixed delay, watch until the launch has settled: any document or document window
    // cancels the panel; if nothing has appeared once the launch events are processed, show it.
    scheduleLaunchPanelCheck(elapsed: 0)
  }

  private func scheduleLaunchPanelCheck(elapsed: TimeInterval) {
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in
      guard let self else { return }

      if self.hasDocumentOrDocumentWindow {
        return
      }

      let required = self.launchHadNothingToOpen
        ? Self.settleDelayWhenLaunchedEmpty
        : Self.settleDelayOtherwise
      let elapsed = elapsed + Self.pollInterval

      if elapsed >= required {
        self.openInitialDocument()
      } else {
        self.scheduleLaunchPanelCheck(elapsed: elapsed)
      }
    }
  }

  private var hasDocumentOrDocumentWindow: Bool {
    if !NSDocumentController.shared.documents.isEmpty {
      return true
    }

    return NSApp.windows.contains { window in
      window.isVisible && !(window is NSPanel) && window.canBecomeMain
    }
  }

  private func openInitialDocument() {
    guard launchOpenPanel == nil else {
      launchOpenPanel?.makeKeyAndOrderFront(nil)
      return
    }

    let panel = NSOpenPanel()
    panel.allowedContentTypes = MarkdownDocument.readableContentTypes
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.resolvesAliases = true

    launchOpenPanel = panel
    observeDocumentWindows()

    panel.begin { [weak self, weak panel] response in
      guard let self else { return }
      defer {
        panel?.orderOut(nil)
        self.launchOpenPanel = nil
        self.stopObservingDocumentWindows()
      }

      guard response == .OK, let url = panel?.url else { return }
      panel?.close()
      NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
  }

  /// If a document opens while the panel is up (a late Finder open), the panel steps aside.
  private func observeDocumentWindows() {
    stopObservingDocumentWindows()
    mainWindowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeMainNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self, let panel = self.launchOpenPanel else { return }
      guard !NSDocumentController.shared.documents.isEmpty else { return }
      panel.cancel(nil)
    }
  }

  private func stopObservingDocumentWindows() {
    if let observer = mainWindowObserver {
      NotificationCenter.default.removeObserver(observer)
      mainWindowObserver = nil
    }
  }

  private var isRunningTests: Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCTestConfigurationFilePath"] != nil
      || environment["XCTestBundlePath"] != nil
      || NSClassFromString("XCTestCase") != nil
  }
}
