# MarkdownReader

MarkdownReader is a small SwiftUI document app for opening and reading Markdown files on macOS. It is currently closer to a minimal viewer than a polished product.

Current release snapshot: `0.4.0`

## Current Status

- Opens `.md` and `.markdown` files through a document-based app flow.
- Renders the complete document in one `WKWebView`, so prose, tables, code blocks, and selection share one continuous layout surface.
- Opens files in viewer mode rather than editor mode.
- Uses a split-view reader with a toggleable table-of-contents sidebar for Markdown headings; selecting a heading scrolls the document to it.
- Applies a GitHub-inspired reading style tuned for macOS, including properly padded tables, blockquotes, inline code, and fenced code blocks.
- Provides persistent display options for font size, line spacing, System/Light/Dark theme, and syntax highlighting.
- Highlights common programming languages offline with Highlight.js, using fenced language tags when present and automatic detection otherwise. Each fenced block includes its language and a copy button.
- Disables document restoration so the app does not automatically reopen the last restored file on launch.
- Still has product and release gaps around automated UI coverage, some document-window polish, and more robust file handling.

## Stack

- Swift
- SwiftUI
- `FileDocument` with `DocumentGroup`
- WebKit `WKWebView` (via `NSViewRepresentable`) for whole-document HTML rendering
- [`swift-cmark`](https://github.com/swiftlang/swift-cmark) for safe CommonMark and GitHub-flavored Markdown HTML
- A bundled offline Highlight.js build for language-aware syntax highlighting
- Xcode project-based workflow

## Build the macOS App

Building requires a full Xcode installation. The app runs on macOS 15.1 or newer, and the first build needs internet access to download its Swift package dependencies.

From the repository root, create a Release build with:

```bash
xcodebuild \
  -project MarkdownReader.xcodeproj \
  -scheme MarkdownReader \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build \
  clean build
```

The built app is written to `.build/Build/Products/Release/MarkdownReader.app`. Launch it with:

```bash
open .build/Build/Products/Release/MarkdownReader.app
```

To build in Xcode instead, open `MarkdownReader.xcodeproj`, select the **MarkdownReader** scheme and **My Mac** destination, then choose **Product → Build**. These steps produce a local development build; distributing the app to other Macs also requires the appropriate Apple signing and notarization workflow.

## Project Structure

- [MarkdownReader](/Users/taojiachun/stacks/tjcccc/MarkdownReader/MarkdownReader): app source
- [MarkdownReaderTests](/Users/taojiachun/stacks/tjcccc/MarkdownReader/MarkdownReaderTests): unit test target
- [MarkdownReaderUITests](/Users/taojiachun/stacks/tjcccc/MarkdownReader/MarkdownReaderUITests): UI test target
- [spec/ui.md](/Users/taojiachun/stacks/tjcccc/MarkdownReader/spec/ui.md): project UI spec
- [DEVLOG.md](/Users/taojiachun/stacks/tjcccc/MarkdownReader/DEVLOG.md): session context and recent findings

## How It Works Today

The app registers the Markdown UTI (`net.daringfireball.markdown`) and opens matching files in a viewer-only `DocumentGroup`. The document loader reads file contents as UTF-8 text. `MarkdownHTMLRenderer` converts the source to safe GFM HTML and extracts the heading outline. `MarkdownWebView` displays the entire document in one persistent `WKWebView`; the native sidebar scrolls it to generated heading anchors.

The HTML page and styling are generated locally. Raw Markdown HTML is disabled, a restrictive Content Security Policy blocks network content, and relative images are served from the document folder through a validated custom WebKit URL scheme. Parent-directory traversal and arbitrary app resources are rejected. External links open in the default browser.

Reader preferences are stored with `AppStorage` and applied to the existing page without reloading it. Syntax highlighting also runs locally; an unsupported fenced language falls back to readable plain code.

Because images live beside the document and the App Sandbox only grants access to the opened file, the **App Sandbox is disabled** so sibling resources can be read. This means the app is not sandboxed and is not Mac App Store eligible.

## Development Notes

- `MarkdownHTMLRenderer`, the page wrapper, display-option bounds, and local-resource path validation are covered by unit tests (`MarkdownReaderTests`, Swift Testing); the UI targets are still template placeholders.
- The app is a reader-only document viewer. The App Sandbox is disabled (see above) so images stored next to a Markdown file can be loaded.
- `scripts/run-debug.sh` builds Debug and runs the app from the terminal (`scripts/run-debug.sh file.md` to open a document).

## Runtime Noise Checklist

Some Xcode/macOS console messages are environment noise rather than app defects. In this project, the following messages were observed during build/run and are not treated as product bugs by themselves:

- `Unable to obtain a task name port right for pid ...`
- `open(/private/var/db/DetachedSignatures) - No such file or directory`

Treat them as harmless unless they come with real symptoms such as:

- the app does not launch
- the debugger cannot attach
- code signing fails
- the app crashes on startup
- sandboxed file access does not work

When these messages appear, use this check order:

1. Confirm the app still builds and launches.
2. Confirm the markdown file open flow still works.
3. Clean the build folder in Xcode.
4. Delete the project's Derived Data if the behavior looks inconsistent.
5. Re-run and only escalate if there is a user-visible failure.

## Next Likely Improvements

- Refine the GitHub-inspired typography and spacing against a wider set of real documents.
- Add focused UI coverage for the display popover, sidebar scrolling, code copying, and image lightbox.
- Improve file decoding and error handling beyond UTF-8-only assumptions.
- Refine document-window polish such as the unresolved `Locked` subtitle.
