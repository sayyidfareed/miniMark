import AppKit
import SwiftUI

struct MarkdownSourceEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var selection: TextSelection

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, selection: $selection)
  }

  func makeNSView(context: Context) -> SourceEditorScrollView {
    let scrollView = SourceEditorScrollView()
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.drawsBackground = false
    scrollView.autohidesScrollers = true

    let textStorage = NSTextStorage(string: text)
    let layoutManager = NSLayoutManager()
    let contentSize = scrollView.contentSize
    let textContainer = NSTextContainer(
      containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    )
    textContainer.widthTracksTextView = true
    textContainer.lineFragmentPadding = 0
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)

    let textView = NSTextView(
      frame: NSRect(origin: .zero, size: NSSize(width: contentSize.width, height: contentSize.height)),
      textContainer: textContainer
    )
    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.allowsUndo = true
    textView.usesFindPanel = true
    textView.isIncrementalSearchingEnabled = true
    textView.isContinuousSpellCheckingEnabled = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.minSize = NSSize(width: 0, height: contentSize.height)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.autoresizingMask = [.width]
    textView.textContainerInset = NSSize(width: 28, height: 24)
    textView.backgroundColor = .textBackgroundColor
    textView.insertionPointColor = .controlAccentColor
    textView.font = MarkdownSourceStyler.baseFont
    textView.typingAttributes = [.font: MarkdownSourceStyler.baseFont, .foregroundColor: NSColor.labelColor]
    textView.string = text

    scrollView.documentView = textView
    scrollView.sourceTextView = textView
    context.coordinator.textView = textView
    MarkdownSourceStyler.apply(to: textView.textStorage!)
    scrollView.updateTextGeometry()
    return scrollView
  }

  func updateNSView(_ scrollView: SourceEditorScrollView, context: Context) {
    guard let textView = context.coordinator.textView else { return }
    let desiredSelection = selection.clamped(to: (text as NSString).length).nsRange

    if textView.string != text {
      context.coordinator.isApplyingUpdate = true
      textView.textStorage?.setAttributedString(NSAttributedString(string: text))
      MarkdownSourceStyler.apply(to: textView.textStorage!)
      textView.setSelectedRange(desiredSelection)
      textView.typingAttributes = [.font: MarkdownSourceStyler.baseFont, .foregroundColor: NSColor.labelColor]
      context.coordinator.isApplyingUpdate = false
    } else if textView.selectedRange() != desiredSelection {
      textView.setSelectedRange(desiredSelection)
    }

    scrollView.updateTextGeometry()
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding var text: String
    @Binding var selection: TextSelection
    weak var textView: NSTextView?
    var isApplyingUpdate = false

    init(text: Binding<String>, selection: Binding<TextSelection>) {
      _text = text
      _selection = selection
    }

    func textDidChange(_ notification: Notification) {
      guard !isApplyingUpdate, let textView = notification.object as? NSTextView else { return }
      text = textView.string
      selection = TextSelection(textView.selectedRange())
      MarkdownSourceStyler.apply(to: textView.textStorage!)
      textView.typingAttributes = [.font: MarkdownSourceStyler.baseFont, .foregroundColor: NSColor.labelColor]
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard !isApplyingUpdate, let textView = notification.object as? NSTextView else { return }
      selection = TextSelection(textView.selectedRange())
    }
  }
}

final class SourceEditorScrollView: NSScrollView {
  weak var sourceTextView: NSTextView?

  override func layout() {
    super.layout()
    updateTextGeometry()
  }

  func updateTextGeometry() {
    guard
      let textView = sourceTextView,
      let textContainer = textView.textContainer,
      let layoutManager = textView.layoutManager
    else { return }

    let availableSize = self.contentSize
    let inset = textView.textContainerInset
    let documentWidth = max(0, availableSize.width)
    let containerWidth = max(0, documentWidth - inset.width * 2)

    textView.minSize = NSSize(width: 0, height: availableSize.height)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )

    if textContainer.containerSize.width != containerWidth {
      textContainer.containerSize = NSSize(
        width: containerWidth,
        height: CGFloat.greatestFiniteMagnitude
      )
    }

    layoutManager.ensureLayout(for: textContainer)
    let usedHeight = layoutManager.usedRect(for: textContainer).height
    let documentHeight = max(availableSize.height, ceil(usedHeight + inset.height * 2))
    let newFrame = NSRect(x: 0, y: 0, width: documentWidth, height: documentHeight)

    if textView.frame != newFrame {
      textView.frame = newFrame
    }
  }
}
