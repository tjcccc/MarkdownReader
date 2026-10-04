# CLAUDE.md — MarkdownReader

macOS SwiftUI Markdown **reader** (viewer only, never an editor). `DocumentGroup(viewing:)` opens `.md`/`.markdown` (UTI `net.daringfireball.markdown`, extension tags `md`/`markdown` without dots). One persistent `WKWebView` renders the whole document from `swift-cmark` GFM HTML; the sidebar TOC, toolbar, find bar, Back button, and image lightbox are native. Swift 6, macOS 15.1+. Version is `MARKETING_VERSION`, aligned across app and Quick Look targets.

## Boundaries

- Markdown and linked files are untrusted. Keep raw HTML disabled, the restrictive CSP, the external-navigation policy, and canonical path validation for `markdown-reader-resource://`. Never launch linked apps or scripts. No remote/CDN dependencies.
- Responsibilities: parsing in `MarkdownReaderShared/MarkdownHTMLRenderer`, page CSS/JS in `MarkdownHTMLDocument`, native/WebKit boundary in `MarkdownWebView`. Never split the document across views.
- The app sandbox is intentionally **off** so sibling images load. Don't re-enable it without a folder-grant/security-scoped-bookmark design.
- The Quick Look extension stays sandboxed, read-only, script-free, and view-based (never set `QLIsDataBasedPreview`). Its outgoing-network entitlement exists only so WebKit can start: keep CSP `default-src 'none'`/`img-src 'none'`, JavaScript off, images sanitized, and navigation cancelled.
- Keep disabled scene restoration and macOS-managed Quick Look activation.

## Invariants that tests don't fully guard

- TOC anchors are `heading-N` over **every** rendered heading (the page script numbers the DOM that way); TOC `id`s stay contiguous because `TableOfContentsScrollBridge` uses them as table rows.
- Theme: on macOS 27 changing only `NSWindow.appearance` doesn't repaint SwiftUI content, and `.preferredColorScheme(nil)` doesn't undo a forced scheme. So System resolves to an explicit scheme via `SystemAppearance` and is applied with both `.preferredColorScheme` and `ReaderWindowAppearanceBridge`. Never paint a custom toolbar background: it breaks the full-height sidebar and title-bar dragging. Settings use an AppKit `NSPopover` because a SwiftUI toolbar popover closes when a live `AppStorage` binding changes.
- Find uses public `WKWebView.find` (`NSTextFinder` doesn't scroll WebKit). Only a failed search clears WebKit's match highlight. Code-toolbar labels are CSS generated content so they're not searchable.
- `NSResponder` has no `cancelOperation(_:)`: never call `super`; forward unhandled Escape with `nextResponder?.tryToPerform(...)`.
- Menus: `ReaderMenuCleaner` removes file-modifying commands by action and hides editing items with `allowsKeyEquivalentWhenHidden` (the find field still needs ⌘V/⌘Z). Revert To is matched by position because AppKit inserts it lazily after launch. Don't replace SwiftUI's `.saveItem` group: that also drops Close, Close All, and Share.
- Favorites (`FavoritesStore`) are file bookmarks in `UserDefaults` (`reader.favorites`), not bare paths. Menu titles that depend on window state come from focused values; SwiftUI doesn't refresh a command's title from an observed store. Focused-value commands are disabled in a background app with no key window, so test them in the foreground.
- `NSView` doesn't clip by default on macOS 14+; custom drawing intersects `dirtyRect` with `bounds`.

## Build and test

```bash
xcodebuild -scheme MarkdownReader -project MarkdownReader.xcodeproj -destination 'platform=macOS,arch=arm64' -quiet build
xcodebuild -scheme MarkdownReader -project MarkdownReader.xcodeproj -destination 'platform=macOS' -only-testing:MarkdownReaderTests test
scripts/build-production.sh          # tests, clean Release build, signature + package checks → dist/ (ad-hoc = local only)
scripts/run-debug.sh --build-only    # rebuild the Debug app the user runs
```

- Unit tests use Swift Testing in `MarkdownReaderTests`. WebKit tests must be window-backed and serialized (offscreen web views get no animation frames) and must register the resource scheme handler (otherwise links trigger a URL-open dialog). Use a page snapshot or bitmap for visual assertions; DOM geometry passing isn't proof.
- UI tests are a placeholder and fail for runner reasons (Grammarly polling, missing LLDB). Those aren't product defects.
- `IDESimulatorFoundation`/`DVTDownloads` errors mean an incomplete Xcode install; the fix `xcodebuild -runFirstLaunch` downloads components, so ask first.
- Several app copies share one bundle id, so computer-use and Quick Look can bind to the wrong one. Confirm which binary runs before claiming a visual check, and capture with the window frontmost: AppKit content in windows behind other apps isn't repainted, so those captures are stale. `qlmanage -p -o` can't probe the view-based preview.
- Report fresh results only; say when a pass count is reused.

## Docs

`DEVLOG.md` is newest-date-first; add notable findings under today's date. Keep README status, `CHANGELOG.md` (Unreleased), and `spec/ui.md` in sync with behavior. Checkpoints, version bumps, and commits go through the `savegame` skill; don't bump versions or add legal/distribution metadata unless asked.
