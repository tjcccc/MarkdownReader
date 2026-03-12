# MarkdownReader

MarkdownReader is a small SwiftUI document app for opening and reading Markdown files on Apple platforms. It is currently closer to a minimal viewer than a polished product.

Current release snapshot: `0.1.0`

## Current Status

- Opens `.md` and `.markdown` files through a document-based app flow.
- Renders Markdown content with `MarkdownUI`.
- Opens files in viewer mode rather than editor mode.
- Uses a split-view reader with a toggleable table-of-contents sidebar for Markdown headings.
- Applies a restrained native reading style tuned for macOS.
- Disables document restoration so the app does not automatically reopen the last restored file on launch.
- Still has product and release gaps around tests, some document-window polish, and more robust file handling.

## Stack

- Swift
- SwiftUI
- `FileDocument` with `DocumentGroup`
- [`swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui)
- Xcode project-based workflow

## Project Structure

- [MarkdownReader](/Users/taojiachun/stacks/tjcccc/MarkdownReader/MarkdownReader): app source
- [MarkdownReaderTests](/Users/taojiachun/stacks/tjcccc/MarkdownReader/MarkdownReaderTests): unit test target
- [MarkdownReaderUITests](/Users/taojiachun/stacks/tjcccc/MarkdownReader/MarkdownReaderUITests): UI test target
- [spec/ui.md](/Users/taojiachun/stacks/tjcccc/MarkdownReader/spec/ui.md): project UI spec
- [DEVLOG.md](/Users/taojiachun/stacks/tjcccc/MarkdownReader/DEVLOG.md): session context and recent findings

## How It Works Today

The app registers the Markdown UTI (`net.daringfireball.markdown`) and opens matching files in a viewer-only `DocumentGroup`. The document loader reads file contents as UTF-8 text and the main content view passes that string into `MarkdownUI` for rendering. The reader UI now uses a split view with a heading-based table of contents in the sidebar.

## Development Notes

- The repository currently has placeholder tests only.
- The app is now wired as a reader-only document viewer and uses read-only user-selected file access in its sandbox entitlements.

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

- Add focused tests around document loading and heading parsing.
- Improve file decoding and error handling beyond UTF-8-only assumptions.
- Refine document-window polish such as the unresolved `Locked` subtitle.
- Revisit selection/copy ergonomics if `MarkdownUI`'s cross-block selection limit becomes a product issue.
