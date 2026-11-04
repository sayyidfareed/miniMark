// Compiled only when SNAPSHOT_MODE is set (the screenshot build). Not part of the App Store build.
#if SNAPSHOT_MODE
enum SnapshotSampleDocument {
  struct Sample {
    let title: String
    let markdown: String
  }

  /// Every feature at a glance; used for the landing page pictures and the first two App Store frames.
  static let releaseNotes = Sample(title: "Release notes.md", markdown: """
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
  """)

  /// Math, a table and a diagram, for the "built in" frame.
  static let orbits = Sample(title: "Orbits.md", markdown: """
  # Orbits, briefly

  Kepler's third law links a planet's year $T$ to the size of its orbit $a$:

  $$
  T^2 = \\frac{4\\pi^2}{G M}\\, a^3
  $$

  | Planet | Distance (AU) | Year (days) |
  | :-- | --: | --: |
  | Mercury | 0.39 | 88 |
  | Earth | 1.00 | 365 |
  | Mars | 1.52 | 687 |

  ```mermaid
  flowchart LR
    Observe --> Model --> Predict --> Observe
  ```

  - [x] Check the units
  - [ ] Add Jupiter
  """)

  /// Fenced code in three languages, for the code frame.
  static let code = Sample(title: "Sync API.md", markdown: """
  # Sync API

  Fetch a page of notes and print each title:

  ```swift
  struct Note: Decodable {
    let id: Int
    let title: String
  }

  let url = URL(string: "https://example.com/notes?page=1")!
  let (data, _) = try await URLSession.shared.data(from: url)
  let notes = try JSONDecoder().decode([Note].self, from: data)
  notes.forEach { print($0.title) }
  ```

  The same call from the command line:

  ```bash
  curl -s "https://example.com/notes?page=1" | jq '.[].title'
  ```

  And in Python:

  ```python
  import requests

  for note in requests.get("https://example.com/notes", params={"page": 1}).json():
      print(note["title"])
  ```
  """)
}

extension SnapshotSampleDocument.Sample {
  static var releaseNotes: Self { SnapshotSampleDocument.releaseNotes }
  static var orbits: Self { SnapshotSampleDocument.orbits }
  static var code: Self { SnapshotSampleDocument.code }
}
#endif
