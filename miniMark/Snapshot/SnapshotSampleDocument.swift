enum SnapshotSampleDocument {
  static let markdown = """
  # Release notes

  A **small**, native Markdown editor. Write in plain text, preview as you go.

  ## This week

  - [x] Add strikethrough, task lists and footnotes
  - [x] Render math with KaTeX
  - [ ] Ship to the Mac App Store

  Old plan: ~~sell it direct~~. New plan: one low price.[^price]

  ## Math

  Euler's identity, $e^{i\\pi} + 1 = 0$, sits next to a display equation:

  $$
  \\int_0^1 x^2\\,dx = \\frac{1}{3}
  $$

  ## Results

  | Build | Tests | Notes |
  | :-- | --: | :-- |
  | 1.0 | 42 | Math and footnotes |
  | 1.1 | 48 | Quick Look |

  ```swift
  let words = text.split(separator: " ").count
  print("\\(words) words")
  ```

  ```mermaid
  flowchart LR
    Write --> Preview --> Export
  ```

  [^price]: Launch price, then a fixed 90-day review.
  """
}
