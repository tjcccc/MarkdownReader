# MarkdownReader

MarkdownReader is a small SwiftUI document app for opening and reading Markdown files on macOS. It is currently closer to a minimal viewer than a polished product.

Current release snapshot: `0.7.1`

## Current Status

- Opens `.md` and `.markdown` files through a document-based app flow.
- Renders the complete document in one `WKWebView`, so prose, tables, code blocks, and selection share one continuous layout surface.
- Opens files in viewer mode rather than editor mode.
- Uses a split-view reader with a toggleable table-of-contents sidebar for Markdown headings; H1/H2 entries are bold, selecting a heading scrolls to it, and the sidebar keeps the current section's complete highlight visible with a small safety margin while reading.
- Applies a GitHub-inspired reading style tuned for macOS, including properly padded tables, blockquotes, inline code, and fenced code blocks.
- Presents leading YAML frontmatter as a compact syntax-highlighted metadata panel instead of misreading it as a heading.
- Provides persistent reader settings for font size, line spacing, reading width, System/Light/Dark theme, and syntax highlighting.
- Includes a macOS Quick Look preview extension for rendering Markdown from Finder with the Space bar and continuous WebKit text selection with ⌘A/⌘C; users enable or disable it in macOS Extensions settings.
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
- Quick Look UI with a view-based, script-disabled WebKit preview extension
- Xcode project-based workflow

## Build the macOS App

Building requires a full Xcode installation. The app runs on macOS 15.1 or newer, and the first build needs internet access to download its Swift package dependencies.

From the repository root, create and verify a Release build with:

```bash
scripts/build-production.sh
```

The script runs the unit tests, performs a clean Release build for the current Mac architecture, verifies the app and embedded Quick Look extension signatures, and creates `dist/MarkdownReader-<version>-macOS-<architecture>.zip` with a SHA-256 checksum. Use `scripts/build-production.sh --skip-tests` only when the same revision has already passed its tests.

To run the underlying build command directly instead:

```bash
xcodebuild \
  -project MarkdownReader.xcodeproj \
  -scheme MarkdownReader \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build \
  clean build
```

The built app is written to `.build/Build/Products/Release/MarkdownReader.app` and contains the Quick Look extension at `Contents/PlugIns/MarkdownReaderQuickLook.appex`. Launch it with:

```bash
open .build/Build/Products/Release/MarkdownReader.app
```

To build in Xcode instead, open `MarkdownReader.xcodeproj`, select the **MarkdownReader** scheme and **My Mac** destination, then choose **Product → Build**. The production script packages the signing identity already selected by Xcode; without a Developer ID identity it produces an ad-hoc-signed local build. Public distribution still requires Developer ID signing and Apple notarization.

## Project Structure

- [MarkdownReader](MarkdownReader): app source
- [MarkdownReaderShared](MarkdownReaderShared): safe Markdown/frontmatter renderer plus the script-free Quick Look HTML page shared across targets
- [MarkdownReaderQuickLook](MarkdownReaderQuickLook): sandboxed Quick Look preview extension
- [MarkdownReaderTests](MarkdownReaderTests): unit test target
- [MarkdownReaderUITests](MarkdownReaderUITests): UI test target
- [spec/ui.md](spec/ui.md): project UI spec
- [AGENTS.md](AGENTS.md): project-scoped implementation and validation boundaries
- [CHANGELOG.md](CHANGELOG.md): release-facing history
- [DEVLOG.md](DEVLOG.md): session context and recent findings

## How It Works Today

The app registers the Markdown UTI (`net.daringfireball.markdown`) and opens matching files in a viewer-only `DocumentGroup`. The document loader reads file contents as UTF-8 text. `MarkdownHTMLRenderer` converts the source to safe GFM HTML and extracts the heading outline. `MarkdownWebView` displays the entire document in one persistent `WKWebView`; the native sidebar scrolls it to generated heading anchors.

The HTML page and styling are generated locally. A leading `---` YAML frontmatter block is escaped and shown as a compact, always-visible YAML code panel without an extra disclosure toolbar. Raw Markdown HTML is disabled, a restrictive Content Security Policy blocks network content, and relative images are served from the document folder through a validated custom WebKit URL scheme. Parent-directory traversal and arbitrary app resources are rejected. External links open in the default browser.

Reader preferences are stored with `AppStorage` and applied to the existing page without reloading it. Reading width controls a centered column from 50–100% of the available reader area (75% by default); every step remains effective in maximized and full-screen windows, while narrow windows use the full available width automatically. Syntax highlighting also runs locally; an unsupported fenced language falls back to readable plain code.

The bundled Quick Look extension registers the exact Markdown UTI and presents the shared safe cmark output in one extension-owned `WKWebView` with no custom toolbar. Using the same browser typesetting model and default document hierarchy as the app keeps headings, lists, code, tables, and the complete frontmatter block visually consistent. The page contains no scripts, and content JavaScript is also disabled in WebKit preferences. Images become inert alt-text placeholders and link navigation is restricted. The sandbox target carries the outgoing-network entitlement required to start WebKit's helper processes, but document content remains offline under the `default-src 'none'`/`img-src 'none'` CSP and navigation policy. The Reader Settings popover links to macOS extension management rather than maintaining a conflicting app-owned enabled state.

Because images live beside the document and the App Sandbox only grants access to the opened file, the **main app's App Sandbox is disabled** so sibling resources can be read. This means the app is not sandboxed and is not Mac App Store eligible. The Quick Look extension remains sandboxed and previews only the Markdown file supplied by macOS; image references are shown as inert alt-text placeholders rather than loaded.

## Development Notes

- `MarkdownHTMLRenderer`, both WebKit preview representations, Quick Look page isolation/layout, display-option bounds, and local-resource path validation are covered by unit tests (`MarkdownReaderTests`, Swift Testing); the UI targets are still template placeholders.
- The app is a reader-only document viewer. The App Sandbox is disabled (see above) so images stored next to a Markdown file can be loaded.
- `scripts/run-debug.sh` builds Debug and runs the app from the terminal (`scripts/run-debug.sh file.md` to open a document).
- `scripts/build-production.sh` tests, clean-builds, verifies, and packages a Release app (`--skip-tests` is available for an already-tested revision).
- `scripts/cleanup-markdownreader-registrations.sh` reports duplicate Launch Services and Quick Look registrations created by local build products. It is a read-only dry run by default; pass `--apply` to unregister duplicates while preserving `/Applications/MarkdownReader.app`. The script does not delete app bundles.

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
- Add focused UI coverage for the settings popover, sidebar scrolling, code copying, and image lightbox.
- Improve file decoding and error handling beyond UTF-8-only assumptions.
- Refine document-window polish such as the unresolved `Locked` subtitle.
