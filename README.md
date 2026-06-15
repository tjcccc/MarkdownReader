# MarkdownReader

MarkdownReader is a small SwiftUI document app for opening and reading Markdown files on Apple platforms. It is currently closer to a minimal viewer than a polished product.

Current release snapshot: `0.2.0`

## Current Status

- Opens `.md` and `.markdown` files through a document-based app flow.
- Renders Markdown into one styled `NSAttributedString` shown in a read-only, fully selectable `NSTextView`, so text selects, copies, and searches across the whole document like a normal reader.
- Opens files in viewer mode rather than editor mode.
- Uses a split-view reader with a toggleable table-of-contents sidebar for Markdown headings; selecting a heading scrolls the document to it.
- Applies a restrained native reading style tuned for macOS.
- Disables document restoration so the app does not automatically reopen the last restored file on launch.
- Still has product and release gaps around tests, some document-window polish, and more robust file handling.

## Stack

- Swift
- SwiftUI
- `FileDocument` with `DocumentGroup`
- AppKit `NSTextView` (via `NSViewRepresentable`) for native, document-wide text selection
- Foundation `AttributedString(markdown:)` for parsing/rendering Markdown into `NSAttributedString`
- [`swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui) — retained as a dependency for planned native table/image embedding; not currently used for rendering
- Xcode project-based workflow

## Project Structure

- [MarkdownReader](/Users/taojiachun/stacks/tjcccc/MarkdownReader/MarkdownReader): app source
- [MarkdownReaderTests](/Users/taojiachun/stacks/tjcccc/MarkdownReader/MarkdownReaderTests): unit test target
- [MarkdownReaderUITests](/Users/taojiachun/stacks/tjcccc/MarkdownReader/MarkdownReaderUITests): UI test target
- [spec/ui.md](/Users/taojiachun/stacks/tjcccc/MarkdownReader/spec/ui.md): project UI spec
- [DEVLOG.md](/Users/taojiachun/stacks/tjcccc/MarkdownReader/DEVLOG.md): session context and recent findings

## How It Works Today

The app registers the Markdown UTI (`net.daringfireball.markdown`) and opens matching files in a viewer-only `DocumentGroup`. The document loader reads file contents as UTF-8 text. `MarkdownAttributedRenderer` converts that string into a single styled `NSAttributedString` (plus a heading table of contents with character ranges), which `SelectableMarkdownView` displays in a read-only `NSTextView`. The reader UI uses a split view with the heading-based table of contents in the sidebar; selecting a heading scrolls the text view to it.

Headings, paragraphs, lists, inline styles, code blocks, and blockquotes render as styled text; HTML comments are stripped; GFM tables render as native `NSTextTable` grids; and images are embedded as `NSTextAttachment`, resolved relative to the document's folder (the folder URL is passed in from the document scene). Unreadable images fall back to a `🖼 alt` placeholder.

Because images live beside the document and the App Sandbox only grants access to the opened file, the **App Sandbox is disabled** so sibling resources can be read. This means the app is not sandboxed and is not Mac App Store eligible.

## Development Notes

- `MarkdownAttributedRenderer` is covered by unit tests (`MarkdownReaderTests`, Swift Testing); the UI targets are still template placeholders.
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

- Polish rendering fidelity: rounded code-block cards and a blockquote accent bar (the attributed-string versions are currently flat).
- Improve file decoding and error handling beyond UTF-8-only assumptions.
- Refine document-window polish such as the unresolved `Locked` subtitle.
