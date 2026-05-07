import SwiftUI

@main
struct miniMarkApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let exportCoordinator = MarkdownExportCoordinator()

  var body: some Scene {
    DocumentGroup(newDocument: MarkdownDocument()) { configuration in
      DocumentView(
        document: configuration.$document,
        fileURL: configuration.fileURL,
        exportCoordinator: exportCoordinator
      )
    }
    .commands {
      MarkdownExportCommands(coordinator: exportCoordinator)
    }
  }
}
