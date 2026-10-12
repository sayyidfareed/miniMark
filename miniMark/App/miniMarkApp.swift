import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
  static let storageKey = "appAppearance"

  case system = "System"
  case light = "Light"
  case dark = "Dark"

  var id: String { rawValue }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }

  var appKitAppearance: NSAppearance? {
    switch self {
    case .system: return nil
    case .light: return NSAppearance(named: .aqua)
    case .dark: return NSAppearance(named: .darkAqua)
    }
  }

  var systemImage: String {
    switch self {
    case .system: return "circle.lefthalf.filled"
    case .light: return "sun.max"
    case .dark: return "moon"
    }
  }
}

@MainActor
enum AppAppearanceController {
  static func apply(_ rawValue: String) {
    let appearance = AppAppearance(rawValue: rawValue) ?? .system
    NSApp.appearance = appearance.appKitAppearance

    for window in NSApp.windows {
      window.appearance = appearance.appKitAppearance
    }
  }
}

struct AppearanceCommands: Commands {
  @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

  var body: some Commands {
    CommandGroup(after: .toolbar) {
      Menu("Appearance") {
        ForEach(AppAppearance.allCases) { appearance in
          Button {
            appearanceRaw = appearance.rawValue
            AppAppearanceController.apply(appearance.rawValue)
          } label: {
            if appearanceRaw == appearance.rawValue {
              Label(appearance.rawValue, systemImage: "checkmark")
            } else {
              Text(appearance.rawValue)
            }
          }
        }
      }
    }
  }
}

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
      AppearanceCommands()
    }
  }
}
