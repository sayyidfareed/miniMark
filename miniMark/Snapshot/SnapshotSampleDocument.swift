// Compiled only when SNAPSHOT_MODE is set (the screenshot build). Not part of the App Store build.
#if SNAPSHOT_MODE
enum SnapshotSampleDocument {
  static let markdown = """
  # Release notes

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

  ```swift
  let words = text.split(separator: " ").count
  ```

  ```mermaid
  flowchart LR
    Write --> Preview --> Export
  ```

  [^price]: Launch price, then a fixed 90-day review.
  """
}
#endif
