# Changelog

Notable user-facing and release changes are recorded here. Dates use `YYYY-MM-DD`.

## Unreleased

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
