# CLAUDE.md — MarkdownReader

Agent guidance for this repo. Keep it short and current; update when architecture or tooling changes.

## What this is

A SwiftUI document-based **reader** (viewer, not editor) for Markdown files, macOS-first. Opens `.md`/`.markdown` via `DocumentGroup(viewing:)` and renders the whole document into one styled `NSAttributedString` shown in a read-only `NSTextView`, for native document-wide text selection. (`swift-markdown-ui` is still a dependency but no longer used for rendering.)

## Stack

- Swift 6 language mode (`SWIFT_VERSION = 6.0`), SwiftUI, `FileDocument` + `DocumentGroup`.
- Deployment target: macOS 15.1 (`SDKROOT = auto`; project also lists iOS/visionOS as supported platforms, but the app is built and exercised on macOS).
- Dependency: [`swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui) 2.4.1 (pulls in NetworkImage, swift-cmark). Pins live in `MarkdownReader.xcodeproj/.../swiftpm/Package.resolved`.
- Xcode project workflow (no SwiftPM manifest, no Makefile). Bundle id `com.taojiachun.MarkdownReader`, version in `MARKETING_VERSION` (currently 0.1.0).

## Layout

- `MarkdownReader/MarkdownReaderApp.swift` — `@main` scene: `DocumentGroup(viewing:)`, restoration disabled, `SidebarCommands()`; passes `file.fileURL` into `ContentView` so images resolve relative to the document folder.
- `MarkdownReader/MarkdownReaderDocument.swift` — `FileDocument`; registers UTI `net.daringfireball.markdown`; reads/writes UTF-8 only.
- `MarkdownReader/MarkdownAttributedRenderer.swift` — pure Markdown→`NSAttributedString` converter (+ heading TOC with `NSRange`s). Uses Foundation `AttributedString(markdown:)`; strips HTML comments; renders tables via `NSTextTable` and images via `NSTextAttachment` (resolved against the doc folder `baseURL`).
- `MarkdownReader/SelectableMarkdownView.swift` — `NSViewRepresentable` over a read-only, selectable `NSTextView` (centered ~820pt column; links open in browser; scrolls to a heading on sidebar selection).
- `MarkdownReader/ContentView.swift` — `NavigationSplitView` with the TOC sidebar + the text view; renders once into `@State` in `init`.
- `MarkdownReaderTests/` — unit target, **Swift Testing** (`import Testing`, `@Test`). `MarkdownAttributedRendererTests` covers the renderer.
- `MarkdownReaderUITests/` — UI target, **XCTest**. Placeholder only.
- `spec/ui.md` — UI spec. `DEVLOG.md` — session history (append, don't rewrite).

## Build / test

Scheme `MarkdownReader`, macOS destination:

```bash
xcodebuild -scheme MarkdownReader -project MarkdownReader.xcodeproj -destination 'platform=macOS,arch=arm64' -quiet build
xcodebuild -scheme MarkdownReader -project MarkdownReader.xcodeproj -destination 'platform=macOS' test
```

Build verified green on 2026-06-15 (exit 0, no errors) after an Xcode 26.4.1 component install was completed. If `xcodebuild` ever again fails with `IDESimulatorFoundation` / `Symbol not found … DVTDownloads`, it's an incomplete Xcode install (not a code defect) — fix with `xcodebuild -runFirstLaunch` (downloads components — **ask the user first**) or by finishing the Xcode update.

UI tests: `MarkdownReaderUITestsLaunchTests.testLaunch` can fail environmentally (`Unable to update application state … com.grammarly.ProjectLlama.UpdateService`) — Grammarly's background helper interferes with XCUITest polling. Quit Grammarly before UI-test runs; it's not a product defect. Don't claim a build/test passed if the CLI didn't actually run it.

Harmless console noise (see README): `Unable to obtain a task name port right…`, `open(/private/var/db/DetachedSignatures)…`. Only escalate if there's a real symptom (no launch, no debugger, signing failure, crash, broken sandbox file access).

## Conventions & boundaries

- Reader-only: do **not** reintroduce editing UI. `fileWrapper` exists only to satisfy `FileDocument`.
- **App Sandbox is intentionally disabled** (`MarkdownReader.entitlements`, `com.apple.security.app-sandbox = false`) so images stored beside a document (e.g. `assets/foo.png`) can be read — the sandbox only grants the opened file, not siblings. Don't re-enable it without a folder-grant/security-scoped-bookmark plan; doing so silently breaks local images. (Re-enabling would also be required for any future Mac App Store distribution.)
- Rendering is pure `NSAttributedString` (AppKit): style runs in `MarkdownAttributedRenderer`. Keep the converter pure and testable; add styling there, not in the view. Tables = `NSTextTable`, images = `NSTextAttachment` — both keep selection flowing, so prefer them over view-based attachments.
- New unit tests go in `MarkdownReaderTests` using Swift Testing (`#expect`), not XCTest. Renderer internals are `internal` + `@testable import` — extend `MarkdownAttributedRendererTests` rather than duplicating logic.
- Prefer the smallest correct change. Don't broaden platform support, add dependencies, or refactor unrelated code without being asked.

## Docs / version policy

- Append a dated entry to `DEVLOG.md` for notable changes; keep README "Current Status" accurate.
- Version lives in `MARKETING_VERSION` (Xcode project) and the README snapshot; bump both together. The `savegame` skill handles checkpoint/version/commit flow.
- Don't add license/legal/distribution metadata without approval.
```
