import SwiftUI

struct DocumentView: View {
  enum Mode: String, CaseIterable, Identifiable {
    case source = "Source"
    case preview = "Preview"

    var id: String { rawValue }

    var systemImage: String {
      switch self {
      case .source: return "square.text.square"
      case .preview: return "eye"
      }
    }
  }

  private static let defaultModeKey = "defaultMode"

  @Binding var document: MarkdownDocument
  let fileURL: URL?
  let exportCoordinator: MarkdownExportCoordinator

  @AppStorage(Self.defaultModeKey) private var defaultModeRaw = Mode.source.rawValue
  @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
  @State private var mode: Mode
  @State private var selection = TextSelection.zero
  @State private var previewMarkdown = ""
  @State private var previewTask: Task<Void, Never>?
  @State private var windowFileURL: URL?

  init(
    document: Binding<MarkdownDocument>,
    fileURL: URL?,
    exportCoordinator: MarkdownExportCoordinator
  ) {
    self._document = document
    self.fileURL = fileURL
    self.exportCoordinator = exportCoordinator

    let savedMode = UserDefaults.standard.string(forKey: Self.defaultModeKey)
      .flatMap(Mode.init(rawValue:)) ?? .source
    self._mode = State(initialValue: savedMode)
  }

  private var stats: DocumentStats {
    DocumentStats.calculate(text: document.text, selection: selection)
  }

  private var defaultMode: Mode {
    Mode(rawValue: defaultModeRaw) ?? .source
  }

  private var effectiveFileURL: URL? {
    fileURL ?? windowFileURL
  }

  private var exportContext: MarkdownExportContext {
    MarkdownExportContext(markdown: document.text, fileURL: effectiveFileURL)
  }

  var body: some View {
    VStack(spacing: 0) {
      topBar
      Divider().opacity(0.6)

      Group {
        switch mode {
        case .source:
          MarkdownSourceEditor(text: $document.text, selection: $selection)
            .transition(.opacity)
        case .preview:
          MarkdownPreview(markdown: previewMarkdown, fileURL: effectiveFileURL)
            .transition(.opacity)
        }
      }
      .frame(minWidth: 720, minHeight: 480)

      Divider().opacity(0.6)
      statusBar
    }
    .background {
      Button("Toggle Mode") {
        mode = mode == .source ? .preview : .source
      }
      .keyboardShortcut("p", modifiers: [.command, .shift])
      .opacity(0)
      .frame(width: 0, height: 0)
      .accessibilityHidden(true)

      MarkdownExportCommandBridge(
        context: exportContext,
        coordinator: exportCoordinator,
        windowFileURL: $windowFileURL
      )
      .frame(width: 0, height: 0)
      .accessibilityHidden(true)
    }
    .animation(.easeInOut(duration: 0.18), value: mode)
    .onAppear {
      AppAppearanceController.apply(appearanceRaw)
      previewMarkdown = document.text
      exportCoordinator.updateCurrentContext(exportContext)
    }
    .onChange(of: appearanceRaw) { _, newValue in
      AppAppearanceController.apply(newValue)
    }
    .onChange(of: document.text) { _, newValue in
      schedulePreviewUpdate(for: newValue)
      exportCoordinator.updateCurrentContext(
        MarkdownExportContext(markdown: newValue, fileURL: effectiveFileURL)
      )
    }
    .onChange(of: windowFileURL) {
      exportCoordinator.updateCurrentContext(exportContext)
    }
    .onDisappear {
      previewTask?.cancel()
      exportCoordinator.updateCurrentContext(nil)
    }
    .focusedValue(
      \.markdownExportContext,
      exportContext
    )
  }

  private var topBar: some View {
    HStack(spacing: 14) {
      modePicker
      defaultModeMenu

      Rectangle()
        .fill(Color.primary.opacity(0.1))
        .frame(width: 1, height: 20)

      FormatToolbar(isEnabled: mode == .source) { command in
        apply(command)
      }

      Spacer()

      appearancePicker
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(.bar)
  }

  private var modePicker: some View {
    Picker("", selection: $mode) {
      ForEach(Mode.allCases) { mode in
        Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
      }
    }
    .pickerStyle(.segmented)
    .frame(width: 196)
    .labelsHidden()
    .help("Toggle source / preview  ⌘⇧P")
  }

  private var defaultModeMenu: some View {
    Button {
      defaultModeRaw = (defaultMode == .source ? Mode.preview : .source).rawValue
    } label: {
      HStack(spacing: 4) {
        Text("Default")
          .foregroundStyle(.tertiary)
        Text(defaultMode.rawValue)
          .foregroundStyle(.secondary)
      }
      .font(.system(size: 11, weight: .regular))
    }
    .buttonStyle(.plain)
    .help("Click to switch which mode documents open in")
  }

  private var appearancePicker: some View {
    Picker("Appearance", selection: $appearanceRaw) {
      ForEach(AppAppearance.allCases) { appearance in
        Label(appearance.rawValue, systemImage: appearance.systemImage)
          .tag(appearance.rawValue)
      }
    }
    .pickerStyle(.segmented)
    .frame(width: 236)
    .labelsHidden()
    .help("Use the system, light, or dark appearance")
  }

  private var statusBar: some View {
    HStack(spacing: 0) {
      statItem(icon: "text.alignleft", text: "\(stats.wordCount) \(stats.wordCount == 1 ? "word" : "words")")
      statSeparator
      statItem(icon: "character", text: "\(stats.characterCount) \(stats.characterCount == 1 ? "char" : "chars")")
      statSeparator
      statItem(icon: "clock", text: stats.readingTimeLabel)

      Spacer(minLength: 16)

      Text("Ln \(stats.line)")
        .monospacedDigit()
      Text("·")
        .opacity(0.4)
        .padding(.horizontal, 6)
      Text("Col \(stats.column)")
        .monospacedDigit()
    }
    .font(.system(size: 11, weight: .medium))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 14)
    .padding(.vertical, 6)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func statItem(icon: String, text: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .imageScale(.small)
        .opacity(0.75)
      Text(text)
        .monospacedDigit()
    }
  }

  private var statSeparator: some View {
    Text("·")
      .opacity(0.4)
      .padding(.horizontal, 8)
  }

  private func apply(_ command: MarkdownFormatCommand) {
    let result = MarkdownFormatter.apply(command, to: document.text, selection: selection)
    document.text = result.text
    selection = result.selection
  }

  private func schedulePreviewUpdate(for text: String) {
    previewTask?.cancel()
    previewTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(220))
      guard !Task.isCancelled else { return }
      previewMarkdown = text
    }
  }
}
