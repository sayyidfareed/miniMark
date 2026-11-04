import SwiftUI

struct FormatToolbar: View {
  var isEnabled: Bool
  var action: (MarkdownFormatCommand) -> Void

  var body: some View {
    HStack(spacing: 2) {
      group {
        toolbarButton("bold", help: "Bold", shortcut: "⌘B", command: .bold)
          .keyboardShortcut("b", modifiers: .command)
        toolbarButton("italic", help: "Italic", shortcut: "⌘I", command: .italic)
          .keyboardShortcut("i", modifiers: .command)
        toolbarButton("link", help: "Link", shortcut: "⌘K", command: .link)
          .keyboardShortcut("k", modifiers: .command)
      }

      separator

      group {
        toolbarButton("textformat.size", help: "Heading", shortcut: "⌘⌥1", command: .heading)
          .keyboardShortcut("1", modifiers: [.command, .option])
        toolbarButton("list.bullet", help: "Bulleted list", shortcut: "⌘⇧8", command: .unorderedList)
          .keyboardShortcut("8", modifiers: [.command, .shift])
        toolbarButton("list.number", help: "Numbered list", shortcut: "⌘⇧7", command: .orderedList)
          .keyboardShortcut("7", modifiers: [.command, .shift])
        toolbarButton("text.quote", help: "Quote", shortcut: "⌘⇧.", command: .quote)
          .keyboardShortcut(".", modifiers: [.command, .shift])
      }

      separator

      group {
        toolbarButton("chevron.left.forwardslash.chevron.right", help: "Inline code", shortcut: "⌘⇧C", command: .inlineCode)
          .keyboardShortcut("c", modifiers: [.command, .shift])
        toolbarButton("curlybraces", help: "Code block", shortcut: "⌘⌥C", command: .codeBlock)
          .keyboardShortcut("c", modifiers: [.command, .option])
      }
    }
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.5)
    .animation(.easeInOut(duration: 0.15), value: isEnabled)
  }

  @ViewBuilder
  private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: 2) { content() }
  }

  private var separator: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.12))
      .frame(width: 1, height: 16)
      .padding(.horizontal, 4)
  }

  private func toolbarButton(
    _ systemImage: String,
    help: String,
    shortcut: String,
    command: MarkdownFormatCommand
  ) -> some View {
    Button {
      action(command)
    } label: {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .medium))
    }
    .buttonStyle(ToolbarIconButtonStyle())
    .help("\(help)  \(shortcut)")
    .accessibilityLabel(help)
  }
}

private struct ToolbarIconButtonStyle: ButtonStyle {
  @State private var isHovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(width: 28, height: 24)
      .foregroundStyle(configuration.isPressed ? Color.accentColor : Color.primary.opacity(0.85))
      .background(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(background(for: configuration))
      )
      .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
      .onHover { isHovering = $0 }
      .animation(.easeOut(duration: 0.12), value: isHovering)
      .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
  }

  private func background(for configuration: Configuration) -> Color {
    if configuration.isPressed { return Color.primary.opacity(0.14) }
    if isHovering { return Color.primary.opacity(0.07) }
    return .clear
  }
}
