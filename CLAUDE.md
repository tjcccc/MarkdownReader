# CLAUDE.md — MarkdownReader

Agent guidance for this repo. Keep it short and current; update when architecture or tooling changes.

## What this is

A SwiftUI document-based **reader** (viewer, not editor) for Markdown files, macOS-first. Opens `.md`/`.markdown` via `DocumentGroup(viewing:)` and renders the complete document as safe, GitHub-flavored HTML in one `WKWebView`. The window structure, table-of-contents sidebar, toolbar, file handling, and image lightbox remain native.

## Stack

- Swift 6 language mode (`SWIFT_VERSION = 6.0`), SwiftUI, `FileDocument` + `DocumentGroup`.
- Deployment target: macOS 15.1 (`SDKROOT = auto`; project also lists iOS/visionOS as supported platforms, but the app is built and exercised on macOS).
- Dependency: [`swift-cmark`](https://github.com/swiftlang/swift-cmark) 0.5.0 (`cmark-gfm` + extensions). Highlight.js 11.11.1 is bundled as an offline app resource.
- Xcode project workflow (no SwiftPM manifest, no Makefile). Bundle id `com.taojiachun.MarkdownReader`, version in `MARKETING_VERSION` (currently 0.6.1).

## Layout

- `MarkdownReader/MarkdownReaderApp.swift` — `@main` scene: `DocumentGroup(viewing:)`, restoration disabled, `SidebarCommands()`; passes `file.fileURL` into `ContentView` so images resolve relative to the document folder.
- `MarkdownReader/MarkdownReaderDocument.swift` — `FileDocument`; registers UTI `net.daringfireball.markdown`; reads/writes UTF-8 only.
- `MarkdownReaderShared/MarkdownHTMLRenderer.swift` — pure cmark-gfm Markdown→safe HTML conversion compiled into both the app and Quick Look extension, plus heading TOC extraction. Raw Markdown HTML stays disabled.
- `MarkdownReaderShared/MarkdownFrontMatter.swift` — conservative leading-YAML-frontmatter recognition shared by both presentation paths; requires a top-of-file delimiter pair and at least one YAML-style key before extracting metadata.
- `MarkdownReaderShared/MarkdownQuickLookHTMLDocument.swift` — self-contained, script-free, system-themed HTML used by Finder Quick Look; untrusted images become inert alt-text placeholders before WebKit receives the page.
- `MarkdownReaderQuickLook/` — sandboxed view-based Quick Look extension. `PreviewViewController` hosts only the script-disabled page in one `WKWebView`; its plist must keep the exact `net.daringfireball.markdown` supported content type and must not set `QLIsDataBasedPreview`.
- `MarkdownReader/MarkdownHTMLDocument.swift` — GitHub-inspired CSS and the small JavaScript bridge for live display settings, heading scrolling, code highlighting/copying, and image clicks.
- `MarkdownReader/MarkdownWebView.swift` — the single `WKWebView`, external-link policy, native pasteboard/image bridge, and validated custom URL scheme for document-relative images and bundled resources.
- `MarkdownReader/ReaderDisplayOptions.swift` — display preference model, a stable AppKit Reader Settings `NSPopover` host, SwiftUI controls, and the per-window appearance bridge. Keep both AppKit boundaries: a SwiftUI toolbar popover is dismissed when a live preference binding changes on macOS, and `.preferredColorScheme(nil)` can leave a previously forced window dark instead of restoring System appearance.
- `MarkdownReader/ContentView.swift` — `NavigationSplitView`, TOC selection, persisted `AppStorage` preferences, toolbar, and native image lightbox.
- `MarkdownReaderTests/` — unit target, **Swift Testing** (`import Testing`, `@Test`). `MarkdownHTMLRendererTests` covers rendering, page security/settings, and resource path validation.
- `MarkdownReaderUITests/` — UI target, **XCTest**. Placeholder only.
- `spec/ui.md` — UI spec. `DEVLOG.md` — session history (append, don't rewrite).

## Build / test

Scheme `MarkdownReader`, macOS destination:

```bash
xcodebuild -scheme MarkdownReader -project MarkdownReader.xcodeproj -destination 'platform=macOS,arch=arm64' -quiet build
xcodebuild -scheme MarkdownReader -project MarkdownReader.xcodeproj -destination 'platform=macOS' test
```

The app scheme builds and embeds `MarkdownReaderQuickLook.appex`. Build the extension alone with scheme `MarkdownReaderQuickLook` when diagnosing provider compilation or registration.

Build and focused unit tests were verified green on 2026-08-30. If `xcodebuild` fails with `IDESimulatorFoundation` / `Symbol not found … DVTDownloads`, it's an incomplete Xcode install (not a code defect) — fix with `xcodebuild -runFirstLaunch` (downloads components — **ask the user first**) or by finishing the Xcode update.

UI tests: `MarkdownReaderUITestsLaunchTests.testLaunch` can fail environmentally, either while polling app state (`com.grammarly.ProjectLlama.UpdateService`) or when Xcode cannot resolve LLDB (`DebuggerVersionStore: no debugger version`). Quit Grammarly before UI-test runs and verify Xcode's debugger components when needed; these are runner failures, not product defects. Don't claim a build/test passed if the CLI didn't actually run it.

Harmless console noise (see README): `Unable to obtain a task name port right…`, `open(/private/var/db/DetachedSignatures)…`. Only escalate if there's a real symptom (no launch, no debugger, signing failure, crash, broken sandbox file access).

## Conventions & boundaries

- Reader-only: do **not** reintroduce editing UI. `fileWrapper` exists only to satisfy `FileDocument`.
- **App Sandbox is intentionally disabled** (`MarkdownReader.entitlements`, `com.apple.security.app-sandbox = false`) so images stored beside a document (e.g. `assets/foo.png`) can be read — the sandbox only grants the opened file, not siblings. Don't re-enable it without a folder-grant/security-scoped-bookmark plan; doing so silently breaks local images. (Re-enabling would also be required for any future Mac App Store distribution.)
- The Quick Look extension is intentionally sandboxed and read-only. It receives the selected Markdown file from macOS but does not assume access to sibling image resources. Keep its preview self-contained and script-free; extension activation remains under macOS control.
- Sandboxed `WKWebView` startup requires the Quick Look target's outgoing-network entitlement so WebKit can launch its helper processes. This is not permission for document content: keep the preview CSP at `default-src 'none'`/`img-src 'none'`, keep content JavaScript disabled, sanitize images before loading, and cancel page navigation so Markdown cannot use that capability.
- Keep the renderer one whole-document `WKWebView`; do not split blocks into multiple web views. Keep Markdown parsing in `MarkdownHTMLRenderer`, page presentation/interaction in `MarkdownHTMLDocument`, and native/WebKit boundary behavior in `MarkdownWebView`.
- Web content is untrusted. Keep raw Markdown HTML disabled, retain the restrictive CSP and external-navigation policy, and validate every custom-scheme filesystem path before reading it. Do not add remote CDN dependencies.
- New unit tests go in `MarkdownReaderTests` using Swift Testing (`#expect`), not XCTest. Extend `MarkdownHTMLRendererTests` for renderer/page/resource contracts.
- Prefer the smallest correct change. Don't broaden platform support, add dependencies, or refactor unrelated code without being asked.

## Docs / version policy

- Append a dated entry to `DEVLOG.md` for notable changes; keep README "Current Status" accurate.
- Version lives in `MARKETING_VERSION` (Xcode project) and the README snapshot; bump both together. The `savegame` skill handles checkpoint/version/commit flow.
- Don't add license/legal/distribution metadata without approval.
