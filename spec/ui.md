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
- `MarkdownUI` for Markdown rendering
- Asset catalog present, but no meaningful custom visual tokens are currently defined

## Current Design Direction

Observed:
- The UI is intentionally minimal and almost entirely system-default.
- The main content is a vertically scrollable document view with constrained reading width.
- Markdown content is padded with `36` horizontal points and `32` vertical points.
- Window sizing is constrained with a minimum frame of `720x520` and a default size of `980x780`.
- The sidebar defaults to hidden for smaller outlines and auto-opens for documents with a more meaningful heading count.

Inferred:
- The app currently prioritizes simplicity over product polish.
- The visual direction is a quiet native macOS reader rather than a branded custom interface.

## Styling System

Observed:
- No custom font family is introduced beyond system and monospaced system fonts.
- No custom colors are defined in the accent color asset.
- No reusable style tokens, theme layer, or shared view modifiers are present.
- Layout is expressed directly in SwiftUI views rather than through an abstraction layer.
- `MarkdownUI`'s GitHub theme is used as a base, with local overrides to tighten paragraph and heading spacing and lightly style blockquotes and code blocks.

Current visible spacing:
- Reader inset: `36` horizontal, `32` vertical
- Sidebar width hint: min `320`, ideal `360`, max `440`

## Layout Conventions

- A single document window hosts the reading view.
- The main reader uses `NavigationSplitView` with a sidebar and detail pane.
- Content is wrapped in a `ScrollView`.
- Markdown rendering is embedded in a lightweight wrapper view (`MarkdownView`) and then placed inside `ContentView`.
- The sidebar shows a heading-based table of contents derived from Markdown ATX headings.

## Component Conventions

- Keep view composition simple and local unless complexity justifies extraction.
- Prefer native SwiftUI structure and platform defaults.
- Use `MarkdownUI` as the rendering engine for rich text instead of building custom markdown presentation manually.

## Interaction Conventions

Observed:
- The current app interaction model is passive reading only.
- No explicit in-app controls are implemented in the main content view.
- The document scene is configured in viewer mode rather than editor mode.
- The standard macOS sidebar toggle is exposed through the `View` menu via `SidebarCommands`.
- Scene restoration is disabled so the app does not restore the last document window automatically on launch.

Open questions:
- Whether the app should remain fully document-driven or add explicit open/recent-file affordances.
- Whether reader preferences such as text size, theme, or focus mode should become first-class features.
- Whether the UI should remain system-default or adopt a more intentional reading-oriented visual identity.

## Constraints

- Preserve the current minimal app shape unless a feature requires broader UI changes.
- Favor readability and platform-native behavior over decorative customization.
- Treat this app as a reader, not an editor, unless the product direction changes explicitly.
