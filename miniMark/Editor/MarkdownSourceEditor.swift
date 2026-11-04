import AppKit
import SwiftUI

/// Lets the toolbar edit through the live text view, so formatting is a normal undoable text change
/// instead of a wholesale replacement of the document from outside.
final class MarkdownSourceEditorController {
  fileprivate(set) weak var textView: NSTextView?

  /// Applies a formatting command to the text view's current selection. Returns false when there is
  /// no text view to edit, so the caller can fall back to editing the document text directly.
  @discardableResult
  func apply(_ command: MarkdownFormatCommand) -> Bool {
    guard let textView, textView.isEditable, let storage = textView.textStorage else { return false }
    if textView.hasMarkedText() { textView.unmarkText() }

    let original = textView.string
    let result = MarkdownFormatter.apply(command, to: original, selection: TextSelection(textView.selectedRange()))

    if let edit = MarkdownTextEdit.between(original, result.text) {
      guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return true }
      textView.breakUndoCoalescing()
      storage.replaceCharacters(in: edit.range, with: edit.replacement)
      textView.didChangeText()
      textView.undoManager?.setActionName(command.undoActionName)
      textView.breakUndoCoalescing()
    }

    let selection = result.selection.clamped(to: storage.length).nsRange
    textView.setSelectedRange(selection)
    textView.scrollRangeToVisible(selection)
    if textView.window?.firstResponder !== textView {
      textView.window?.makeFirstResponder(textView)
    }
    return true
  }
}

struct MarkdownSourceEditor: NSViewRepresentable {
  @Binding var text: String
  @Binding var selection: TextSelection
  /// False while another mode is showing. The text view stays alive (keeping its undo history and
  /// scroll position) but is hidden and gives up keyboard focus.
  var isActive: Bool = true
  var controller: MarkdownSourceEditorController?

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

    let coordinator = context.coordinator
    let textStorage = NSTextStorage(string: text)
    textStorage.delegate = coordinator.styler
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
    textView.delegate = coordinator
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
    textView.typingAttributes = MarkdownSourceStyler.typingAttributes
    textView.setAccessibilityLabel("Markdown source")

    scrollView.documentView = textView
    scrollView.sourceTextView = textView
    scrollView.isHidden = !isActive
    coordinator.textView = textView
    coordinator.syncedText = text
    coordinator.styler.styleAll(textStorage)
    controller?.textView = textView
    scrollView.updateTextGeometry()
    return scrollView
  }

  func updateNSView(_ scrollView: SourceEditorScrollView, context: Context) {
    let coordinator = context.coordinator
    coordinator.text = $text
    coordinator.selection = $selection
    guard let textView = coordinator.textView else { return }
    controller?.textView = textView
    updateActiveState(scrollView, textView: textView)

    // Never touch the storage or selection in the middle of an input-method composition.
    guard !textView.hasMarkedText() else { return }

    // The binding only differs from what the text view last reported when the document changed
    // from outside the editor (for example File > Revert). User edits arrive through textDidChange,
    // which updates `syncedText` first, so they never come back through here.
    if text != coordinator.syncedText {
      coordinator.syncedText = text
      if text != textView.string {
        coordinator.replaceAllText(with: text, in: textView)
      }
    }

    let desiredSelection = selection.clamped(to: textView.textStorage?.length ?? 0).nsRange
    if textView.selectedRange() != desiredSelection {
      textView.setSelectedRange(desiredSelection)
    }

    scrollView.updateTextGeometry()
  }

  private func updateActiveState(_ scrollView: SourceEditorScrollView, textView: NSTextView) {
    let shouldHide = !isActive
    guard scrollView.isHidden != shouldHide else { return }
    scrollView.isHidden = shouldHide
    if shouldHide {
      if textView.window?.firstResponder === textView {
        textView.window?.makeFirstResponder(nil)
      }
    } else {
      DispatchQueue.main.async { [weak textView] in
        guard let textView, let window = textView.window, !textView.isHiddenOrHasHiddenAncestor else { return }
        window.makeFirstResponder(textView)
      }
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    var selection: Binding<TextSelection>
    let styler = MarkdownSourceStyler()
    weak var textView: NSTextView?
    /// The text most recently exchanged with the binding, in either direction.
    var syncedText = ""
    var isApplyingUpdate = false
    private var restyleScheduled = false

    init(text: Binding<String>, selection: Binding<TextSelection>) {
      self.text = text
      self.selection = selection
    }

    func textDidChange(_ notification: Notification) {
      guard !isApplyingUpdate, let textView = notification.object as? NSTextView else { return }
      var newText = textView.string
      newText.makeContiguousUTF8()
      syncedText = newText
      text.wrappedValue = newText
      selection.wrappedValue = TextSelection(textView.selectedRange())
      // Restyling resets attributes, which would break an input-method composition in progress.
      // The edits stay pending and are styled once the composition ends.
      guard !textView.hasMarkedText() else { return }
      restyle(textView)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard !isApplyingUpdate, let textView = notification.object as? NSTextView else { return }
      selection.wrappedValue = TextSelection(textView.selectedRange())
      // A composition can end without a text change (clicking elsewhere commits it), so catch up on
      // any styling deferred while it was active.
      if styler.hasPendingEdits, !textView.hasMarkedText(), !restyleScheduled {
        restyleScheduled = true
        DispatchQueue.main.async { [weak self, weak textView] in
          guard let self else { return }
          self.restyleScheduled = false
          guard let textView, !textView.hasMarkedText(), self.styler.hasPendingEdits else { return }
          self.restyle(textView)
        }
      }
    }

    private func restyle(_ textView: NSTextView) {
      guard let storage = textView.textStorage else { return }
      styler.stylePendingEdits(in: storage)
      textView.typingAttributes = MarkdownSourceStyler.typingAttributes
    }

    /// Replaces the whole text after an outside change. This is not an undoable edit, so earlier
    /// undo steps (which refer to ranges in the old text) are dropped rather than left to misfire.
    func replaceAllText(with newText: String, in textView: NSTextView) {
      guard let storage = textView.textStorage else { return }
      isApplyingUpdate = true
      defer { isApplyingUpdate = false }
      storage.setAttributedString(NSAttributedString(string: newText, attributes: MarkdownSourceStyler.baseAttributes))
      styler.styleAll(storage)
      textView.typingAttributes = MarkdownSourceStyler.typingAttributes
      if let undoManager = textView.undoManager, !undoManager.isUndoing, !undoManager.isRedoing {
        undoManager.removeAllActions()
      }
    }
  }
}

final class SourceEditorScrollView: NSScrollView {
  weak var sourceTextView: NSTextView?

  override func layout() {
    super.layout()
    updateTextGeometry()
  }

  /// Keeps the text view as wide as the visible area. Height is left to NSTextView, which grows as
  /// layout proceeds; forcing layout of the whole document here made every keystroke cost a full
  /// relayout on long files.
  func updateTextGeometry() {
    guard
      let textView = sourceTextView,
      let textContainer = textView.textContainer
    else { return }

    let availableSize = self.contentSize
    let inset = textView.textContainerInset
    let documentWidth = max(0, availableSize.width)
    let containerWidth = max(0, documentWidth - inset.width * 2)

    if textView.minSize.height != availableSize.height {
      textView.minSize = NSSize(width: 0, height: availableSize.height)
    }

    if textContainer.containerSize.width != containerWidth {
      textContainer.containerSize = NSSize(
        width: containerWidth,
        height: CGFloat.greatestFiniteMagnitude
      )
    }

    let height = max(textView.frame.height, availableSize.height)
    if textView.frame.width != documentWidth || textView.frame.height != height {
      textView.setFrameSize(NSSize(width: documentWidth, height: height))
    }
  }
}

private extension MarkdownFormatCommand {
  var undoActionName: String {
    switch self {
    case .bold: return "Bold"
    case .italic: return "Italic"
    case .link: return "Link"
    case .heading: return "Heading"
    case .unorderedList: return "Bulleted List"
    case .orderedList: return "Numbered List"
    case .quote: return "Quote"
    case .inlineCode: return "Inline Code"
    case .codeBlock: return "Code Block"
    }
  }
}
