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
- A view-based Quick Look extension presenting self-contained, script-disabled HTML in one `WKWebView`
- `cmark-gfm` for safe GitHub-flavored HTML and a bundled Highlight.js build for code syntax
- Asset catalog present, but no meaningful custom visual tokens are currently defined

## Current Design Direction

Observed:
- The UI is intentionally minimal and almost entirely system-default.
- The main content is one vertically scrollable HTML document with an adjustable `50–100%` reading width (`75%` default), measured within the available reader area without an absolute width cap.
- The HTML canvas supplies `48px` horizontal gutters while the centered reading frame supplies `36px` top and `72px` bottom padding. The horizontal gutter contracts to `24px` in narrow windows, where the reading frame uses the full available width. All centering space stays outside the frame so cross-block WebKit selection does not paint into it.
- Window sizing is constrained with a minimum frame of `720x520` and a default size of `1200x820`.
- The sidebar defaults to hidden for smaller outlines and auto-opens for documents with a more meaningful heading count.
- A restrained native gear button opens reader settings without permanently occupying reading space.

Inferred:
- The app currently prioritizes simplicity over product polish.
- The visual direction is a quiet native macOS reader rather than a branded custom interface.

## Styling System

Observed:
- No custom font family is introduced beyond system and system-monospaced fonts.
- No custom colors are defined in the accent color asset.
- The HTML renderer defines a compact CSS token layer for canvas, text, muted text, borders, code surfaces, selection, and syntax colors in light and dark appearances.
- The document uses a GitHub-inspired hierarchy: system body text, bordered H1/H2 headings, padded grid tables, border-accented blockquotes, rounded code surfaces, and restrained link color.
- Leading YAML frontmatter uses an always-visible, compact bordered code panel with YAML syntax coloring in the app. It has no disclosure row, language label, or copy button, keeping metadata visually subordinate to the document title.
- Font size, line height, reading width, System/Light/Dark appearance, and syntax highlighting are user-adjustable and persisted.

Current visible spacing:
- Reader gutter: `48px` horizontal; reading-frame inset: `36px` top, `72px` bottom
- Sidebar width hint: min `180`, ideal `240`, max `420`

## Layout Conventions

- A single document window hosts the reading view.
- The main reader uses `NavigationSplitView` with a sidebar and detail pane.
- The entire rendered document lives in one persistent `WKWebView`; there are no per-block web views or parallel native text layout.
- The HTML canvas owns the fixed horizontal gutter; the centered body owns the percentage width and vertical padding. The body's line box and the Markdown root share the same horizontal edges so browser selection remains within the reading column.
- The sidebar shows a heading-based table of contents derived from the cmark document tree and scrolls the web document to stable generated anchors.
- Image previews remain a native full-window overlay.
- Finder Quick Look uses a separate system-owned preview window with no app sidebar, reader settings, or custom control bar. macOS supplies its own title bar, sharing controls, and Open With action; the extension fills the remaining surface with the WebKit document. Its reading column uses `85%` of the available width with `24px` horizontal gutters so the compact preview surface shows more content than the main app's default layout; narrow previews reduce those gutters to `16px`.

## Component Conventions

- Keep view composition simple and local unless complexity justifies extraction.
- Prefer native SwiftUI structure and platform defaults.
- Treat WebKit as the document typesetting engine, not the app shell: windows, sidebar, toolbar, preferences, pasteboard actions, navigation policy, and image preview remain native.
- Keep a single web view per document window so selection and scrolling remain continuous.

## Interaction Conventions

Observed:
- The current app interaction model is passive reading only.
- A gear-shaped Reader Settings toolbar button presents a transient native `NSPopover` containing SwiftUI controls for font size, line spacing, reading width, theme, syntax highlighting, and reset. The broader settings identity leaves room for future reader integrations without changing the control again. The popover remains open while settings update the document live and dismisses when the reader is clicked.
- The Reader Settings popover includes a Quick Look Preview section explaining the Space-bar workflow and a Manage action that opens macOS extension settings. Activation remains system-controlled; the app does not present a duplicate enable toggle.
- The Quick Look document surface follows the current system appearance and uses WebKit with a preview-specific `85%` reading measure, `17px` typography, GitHub-inspired hierarchy, and unified rounded code/frontmatter panels. It intentionally omits custom controls, the sidebar, reader settings, JavaScript syntax highlighting, and image loading. Browser-native selection handles ⌘A/⌘C.
- Font-size and line-spacing controls use one visible header/value row and a separate full-width slider row; slider accessibility labels must not appear as duplicate visible labels.
- Theme uses a compact segmented control aligned to the trailing edge of its row. Reading width changes the centered column as a percentage of the available reader area; every step remains distinct in maximized and full-screen windows, while narrow windows use the full available width.
- Theme applies to the complete document window. System explicitly clears the window's appearance override so it immediately follows the current macOS appearance after Light or Dark was selected.
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
