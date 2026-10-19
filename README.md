# TeakTextView

[English](README.md) | [中文](README.zh-CN.md)

**The native code editor and previewer built into the Teak browser.**

TeakTextView brings Teak's native text editing and source preview capabilities to a standalone Swift Package. Built with UIKit, TextKit 2, and a C++20 text buffer, it supports editable and read-only modes, native text selection and copying, and basic syntax highlighting for 19 languages. Previews display source text without executing it.

## Features

- Native text input, Chinese IME composition, selection handles, copy/cut/paste, undo, and redo.
- Logical line numbers, line wrapping, and bounded layout with tiled rendering for long lines in minified code.
- A persistent C++ Rope and immutable document snapshots that share unchanged nodes across edits.
- Background file reading, decoding, and saving with support for UTF-8 and BOM-marked UTF-16 LE/BE, preserving encoding, BOM, and line endings.
- Background viewport-based highlighting, stale result checks, and importable JSON language rules.
- A standalone demo with a language list, normal and large sample files, file import and export, read-only mode, and performance metrics.

## Requirements

| Component | Requirements |
| --- | --- |
| Editor and demo | iOS 17+, Xcode 16+, Swift 6, C++20 |
| Document and highlighting core | macOS 14+ or iOS 17+ |

There are no third-party runtime dependencies. The editor UI currently uses UIKit; macOS supports the core modules and tests.

## Installation

In Xcode, choose **File → Add Package Dependencies** and enter:

```
https://github.com/yangliu-1995/TeakTextView.git
```

Select the `main` branch. Alternatively, add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/yangliu-1995/TeakTextView.git", branch: "main")
```

Add the `TeakTextView` product to your app target. Also add `TeakTextCore` if you use language rules or document snapshots directly.

## Usage

Create and operate the editor on `MainActor`, then add it to your interface as a regular `UIView`:

```swift
import UIKit
import TeakTextView
import TeakTextCore

@MainActor
func makeEditor(fileURL: URL) async throws -> TeakTextView {
    let editor = TeakTextView()
    editor.showsLineNumbers = true

    let registry = TeakLanguageRegistry()
    let language = try await registry.bundledLanguage(id: "javascript")
    let highlighter = try await registry.makeHighlighter(language: language)
    editor.installPlugin(highlighter)

    try await editor.open(fileURL: fileURL)
    return editor
}
```

Common operations:

```swift
try await editor.load(text: "const answer = 42;\n")
editor.isEditable = false // Read-only source preview with selection and copying
editor.isEditable = true

try await editor.save(to: destinationURL)
editor.undoManager?.undo()
editor.undoManager?.redo()

let snapshot = editor.snapshot
let excerpt = try snapshot.text(
    in: NSRange(location: 0, length: min(200, snapshot.utf16Count))
)
```

All ranges use UTF-16 coordinates. For large documents, prefer range reads and `save(to:)` over requesting the entire document as a string. A `snapshot` shares the immutable tree and can safely be passed to background tasks.

Load custom language rules from a local JSON file:

```swift
let definition = try await registry.load(url: ruleURL)
let plugin = try await registry.makeHighlighter(language: definition)
editor.installPlugin(plugin)
editor.removePlugin(id: plugin.id)
```

`TeakLanguageRegistry.bundledLanguages()` returns the built-in languages. `detect(fileName:firstLine:among:)` detects languages using filenames, the longest matching suffix, and known interpreter shebangs. Unrecognized files can be displayed as plain text.

## Supported Languages

JavaScript / TypeScript, Python, HTML / CSS / Markdown, Java / C#, C / C++, Go, Rust, Swift, Kotlin, SQL, Bash, JSON, YAML, and TOML.

Rules in [`Sources/TeakTextCore/Languages`](Sources/TeakTextCore/Languages) provide highlighting for keywords, comments, strings, numbers, and selected contextual patterns. These are finite lexical rules: full semantic analysis, embedded languages in HTML and Markdown fences, JavaScript template interpolation and regex literals, Bash heredocs, and SQL dollar quoting are not yet supported. See [`Examples/python.json`](Examples/python.json) for a custom rule example.

## Demo

Open [`Demo/TeakTextViewDemo.xcodeproj`](Demo/TeakTextViewDemo.xcodeproj), select **TeakTextViewDemo**, and run on an iPhone or arm64 simulator. To run on a physical device, select your own Team in Signing settings.

The launch screen lists 19 languages. Opening a language loads its normal sample; use **Demo files** in the top-right menu to switch to the large sample. The demo includes 38 real files from open-source projects, preserving their original contents, filenames, and extensions. The largest is TypeScript's `checker.ts` at approximately 3.1 MB. Editing uses temporary copies and leaves bundled resources intact. The menu also supports manual language selection, file and rule import, saving, export, and third-party notices.

See [`Demo/Samples/SOURCES.md`](Demo/Samples/SOURCES.md) and [`catalog.json`](Demo/Samples/catalog.json) for upstream sources, pinned commits, sizes, SHA-256 hashes, and licenses. These files are display resources and are never compiled or executed.

Build the demo for an arm64 simulator from the command line:

```sh
xcodebuild -project Demo/TeakTextViewDemo.xcodeproj \
  -scheme TeakTextViewDemo -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
```

On macOS, validate the text buffer, encoding round trips, and highlighting core:

```sh
swift test
```

## Architecture and Limitations

| Module | Responsibility |
| --- | --- |
| `TeakTextBuffer` | C++20 Rope, snapshots, and newline indexes |
| `TeakTextCore` | File I/O, language rules, background highlighting plugins, and caches |
| `TeakTextStorage` | Foundation / TextKit 2 storage and bounded layout elements |
| `TeakTextView` | UIKit input, line numbers, viewport rendering, and selection geometry |

Very long lines are split into internal layout elements at composed character boundaries. This can slightly change wrapping positions; source text, logical line numbers, copied text, and saved contents remain unchanged. Opening a file still decodes the entire document into resident UTF-16 storage. This is not a disk-backed editor with on-demand loading. On-device performance benchmarks for files of hundreds of megabytes or millions of lines have not yet been established.

Large selections use viewport-local geometry to reduce full-document layout. `TeakTextTouchSupport` centralizes signature-checked probes for an optional private UIKit capability; touch selection behavior needs validation as system versions change. Unit tests cover core data correctness. Scrolling, IME input, selection, and editing menu performance require validation on target devices.

See the [architecture notes (Chinese)](docs/Architecture.md) for implementation details.

## License

TeakTextView is released under the [MIT License](LICENSE). Third-party demo and test samples belong to their respective authors and retain their bundled licenses. See [third-party notices (Chinese)](THIRD_PARTY_NOTICES.md).
