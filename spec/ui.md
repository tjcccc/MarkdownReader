# UI Spec

## Scope

This document records the current UI conventions of the existing app. It describes the app as implemented today and avoids introducing a redesign by default.

## Product Surface

- App type: document-based Markdown reader
- Primary platform inference: macOS-first
- Current user task: open a Markdown file and read its rendered content

## UI Stack

- SwiftUI for app structure and layout
- `DocumentGroup` for document window management
- One AppKit `WKWebView` for whole-document Markdown rendering
- `cmark-gfm` for safe GitHub-flavored HTML and a bundled Highlight.js build for code syntax
- Asset catalog present, but no meaningful custom visual tokens are currently defined

## Current Design Direction

Observed:
- The UI is intentionally minimal and almost entirely system-default.
- The main content is one vertically scrollable HTML document with a constrained `900px` reading width.
- Markdown content uses `48px` horizontal, `36px` top, and `72px` bottom padding; the horizontal inset contracts to `24px` in narrow windows.
- Window sizing is constrained with a minimum frame of `720x520` and a default size of `1200x820`.
- The sidebar defaults to hidden for smaller outlines and auto-opens for documents with a more meaningful heading count.
- A restrained native toolbar button opens display options without permanently occupying reading space.

Inferred:
- The app currently prioritizes simplicity over product polish.
- The visual direction is a quiet native macOS reader rather than a branded custom interface.

## Styling System

Observed:
- No custom font family is introduced beyond system and system-monospaced fonts.
- No custom colors are defined in the accent color asset.
- The HTML renderer defines a compact CSS token layer for canvas, text, muted text, borders, code surfaces, selection, and syntax colors in light and dark appearances.
- The document uses a GitHub-inspired hierarchy: system body text, bordered H1/H2 headings, padded grid tables, border-accented blockquotes, rounded code surfaces, and restrained link color.
- Font size, line height, System/Light/Dark appearance, and syntax highlighting are user-adjustable and persisted.

Current visible spacing:
- Reader inset: `48px` horizontal, `36px` top, `72px` bottom
- Sidebar width hint: min `180`, ideal `240`, max `420`

## Layout Conventions

- A single document window hosts the reading view.
- The main reader uses `NavigationSplitView` with a sidebar and detail pane.
- The entire rendered document lives in one persistent `WKWebView`; there are no per-block web views or parallel native text layout.
- The sidebar shows a heading-based table of contents derived from the cmark document tree and scrolls the web document to stable generated anchors.
- Image previews remain a native full-window overlay.

## Component Conventions

- Keep view composition simple and local unless complexity justifies extraction.
- Prefer native SwiftUI structure and platform defaults.
- Treat WebKit as the document typesetting engine, not the app shell: windows, sidebar, toolbar, preferences, pasteboard actions, navigation policy, and image preview remain native.
- Keep a single web view per document window so selection and scrolling remain continuous.

## Interaction Conventions

Observed:
- The current app interaction model is passive reading only.
- A toolbar popover provides font-size, line-spacing, theme, syntax-highlighting, and reset controls.
- The document scene is configured in viewer mode rather than editor mode.
- The standard macOS sidebar toggle is exposed through the `View` menu via `SidebarCommands`.
- Scene restoration is disabled so the app does not restore the last document window automatically on launch.
- External links open in the default browser; code-copy and image-click actions bridge back to native macOS behavior.

Open questions:
- Whether the app should remain fully document-driven or add explicit open/recent-file affordances.
- Whether the UI should remain system-default or adopt a more intentional reading-oriented visual identity.

## Constraints

- Preserve the current minimal app shape unless a feature requires broader UI changes.
- Favor readability and platform-native behavior over decorative customization.
- Preserve the GitHub-inspired document vocabulary while allowing measured typography and spacing refinements.
- Treat this app as a reader, not an editor, unless the product direction changes explicitly.
