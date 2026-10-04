# Changelog

Notable user-facing and release changes are recorded here. Dates use `YYYY-MM-DD`.

## 0.8.0 - 2026-10-04

### Added

- A Search toolbar button and native macOS find bar with incremental document search, a current/total result count, match navigation, and standard Find shortcuts; its background matches the title bar, with no Replace controls.

- A floating, icon-only circular Back button returns to the last clicked in-document link, including after font-size or window-width changes, then hides.

### Fixed

- Prevent Escape from crashing the reader when the search bar is already closed.
- Apply Light/Dark/System theme changes to the title bar, search strip, sidebar, and settings popover together with the document.
- Keep the search bar background within its strip so opening Search does not cover the document.
- Sidebar entries after an untitled heading (such as a logo-only H1) now scroll to and highlight the correct section.
- No sidebar entry is highlighted while content above the first heading fills the view.
- Closing the search bar removes the match highlight, and code-block "Copy" and language labels no longer count as search results.
- The image preview now dims the whole window, closes with Escape, and disables Search while open.
- Files changed on disk reload automatically and keep the scroll position.
- Image and file links whose names contain `%` now resolve correctly.

- Restore the native full-height sidebar and transparent toolbar; window dragging works across the whole title area again.
- Switching the theme from Dark to System now follows the current macOS appearance across the whole window.
- The Search toolbar button now toggles the find bar and shows a pressed state while it is open.
- Sidebar outline titles have a little horizontal padding inside the selection highlight.

- Trim the menus for a read-only reader: File no longer offers New, Save, Duplicate, Rename, Move To, or Revert To; Edit hides Undo, Redo, Cut, Paste, and Delete; and View no longer shows tab-bar items, since each document opens in its own window.

### Security

- Clicking a link to a file beside the document no longer launches apps or scripts; non-document types are revealed in Finder.

## 0.7.2 - 2026-10-03

### Fixed

- In-document contents links now jump to title-based heading anchors, with support for repeated titles and percent-encoded fragments.

## 0.7.1 - 2026-10-02

### Fixed

- Keep the complete highlighted table-of-contents row visible, including its rounded padding, when document scrolling moves to a section outside the sidebar viewport.

## 0.7.0 - 2026-10-02

### Changed

- Bold H1/H2 table-of-contents entries and keep the sidebar highlight synchronized with the current section while scrolling.

## 0.6.2 - 2026-08-31

### Added

- Added a dry-run-first developer script for removing duplicate MarkdownReader Launch Services and Quick Look registrations without deleting app bundles.

### Changed

- Widened Finder Quick Look's reading column and reduced its horizontal gutters so compact previews display more Markdown content.

## 0.6.1 - 2026-08-30

### Fixed

- Enabled copying from Finder Quick Look Markdown previews with continuous WebKit selection and ⌘A/⌘C routing.
- Removed the custom Quick Look hint and Copy All bar so the preview contains only the document.
- Replaced Quick Look's lossy AppKit HTML-to-rich-text import with script-disabled WebKit typesetting so it preserves the app's document hierarchy, spacing, lists, code surfaces, and complete frontmatter panel.
- Rendered leading YAML frontmatter as a compact, syntax-highlighted metadata panel without a disclosure or copy toolbar.

## 0.6.0 - 2026-08-06

### Added

- Finder Quick Look previews through a bundled, sandboxed extension using the shared safe Markdown renderer and system light/dark appearance.
- Reader Settings entry for opening macOS-managed Quick Look extension settings.
- Repeatable production-build script that tests, clean-builds, verifies, and packages a versioned macOS archive.
- Project-scoped agent guidance for preserving the reader, security, rendering, validation, and release boundaries.

### Changed

- Renamed the display popover to Reader Settings and replaced its typography icon with a gear.
- Moved the safe cmark renderer into a shared target used by both the app and Quick Look extension.

### Fixed

- Corrected Markdown filename-extension registration so Launch Services recognizes MarkdownReader as eligible for `.md` and `.markdown` files.

## 0.5.0 - 2026-08-06

### Added

- Persistent controls for font size, line spacing, percentage-based reading width, System/Light/Dark appearance, and syntax highlighting.

### Fixed

- Kept the settings popover open while controls update the live document.
- Restored the current system appearance after switching from an explicit Light or Dark theme.
- Kept every reading-width slider step effective in maximized and full-screen windows.
- Prevented cross-block WebKit selections from painting through the outer centering space.

## 0.4.0 - 2026-08-05

### Added

- One continuous `WKWebView` document renderer with GitHub-inspired typography, tables, blockquotes, inline code, and fenced code blocks.
- Safe GitHub-flavored Markdown conversion with cmark-gfm and a heading outline for the native sidebar.
- Offline Highlight.js syntax highlighting, code-language labels, copy controls, local-image handling, and image lightbox support.

### Security

- Disabled raw Markdown HTML, blocked remote page resources with a restrictive CSP, validated custom-scheme paths, and opened external navigation outside the reader.

## 0.3.0 - 2026-07-26

### Added

- Language labels and copy controls for fenced code blocks.
- Rounded code surfaces and padded inline-code styling in the previous native TextKit renderer.

### Fixed

- Improved list indentation, cursor behavior, and selection geometry around paragraphs and code blocks.

## 0.2.1 - 2026-07-25

### Changed

- Replaced the original notebook icon with open-book artwork optimized across macOS icon sizes.

## 0.2.0 - 2026-06-15

### Added

- Whole-document native text selection, GitHub-flavored tables, document-relative images, heading navigation, and an image lightbox.
- Reader-oriented window sizing and typography.

### Changed

- Disabled the main app sandbox so images beside an opened Markdown document remain accessible.

## 0.1.0 - 2026-03-12

### Added

- Initial macOS reader release using `DocumentGroup(viewing:)`, UTF-8 Markdown loading, and a toggleable heading sidebar.
- Reader-only behavior, disabled scene restoration, and Swift 6 language mode.
