# DEVLOG

## 2026-06-15

- Release: cut `0.2.0`. Highlights since 0.1.0 — whole-document native text selection (render to `NSAttributedString` in a read-only `NSTextView`), GFM tables (`NSTextTable`), local images (`NSTextAttachment`, App Sandbox disabled to read sibling files), padded code-block boxes, HTML-comment stripping, image lightbox + hover cursor, larger/centered reading column, an emoji app icon, repo `CLAUDE.md`, and dev scripts. Renderer covered by Swift Testing unit tests.

- Onboarding pass; added repo `CLAUDE.md` with stack, layout, build/test commands, reader-only boundaries, and docs/version policy.
- Build/test blocker (now resolved): `xcodebuild` had been failing before compiling — could not load `IDESimulatorFoundation` (`Symbol not found … DVTDownloads`) under Xcode 26.4.1, aborting even macOS builds. Root cause was an incomplete Xcode component install, not a code regression. User completed the Xcode component install; re-verified: `xcodebuild … -destination 'platform=macOS,arch=arm64' build` now exits 0 with no errors.
  - `test` action also runs again. Unit suite + UI tests pass, except `MarkdownReaderUITestsLaunchTests.testLaunch`, which failed environmentally (120s timeout, `Unable to update application state … com.grammarly.ProjectLlama.UpdateService`) then passed on retry. Grammarly's background helper interferes with XCUITest app-state polling; quit it before UI-test runs. Not a product defect.
- Selectable rendering (Step 1 of the native-selection rework):
  - Problem: MarkdownUI draws each block as a separate SwiftUI view and SwiftUI `.textSelection` only selects within a single `Text`, so users could only select one block at a time. The old `ContentView` split the doc into per-heading sections, compounding it.
  - Change: render the whole document into one styled `NSAttributedString` shown in a read-only, selectable `NSTextView`, giving native document-wide selection, ⌘A, Copy, and Find.
  - New files: `MarkdownReader/MarkdownAttributedRenderer.swift` (Markdown→`NSAttributedString` + heading TOC with character ranges, via Foundation `AttributedString(markdown:)`, no new dependency) and `MarkdownReader/SelectableMarkdownView.swift` (`NSViewRepresentable` over `NSTextView`, link clicks open in browser, scrolls to a heading on sidebar selection, centered ~820pt reading column).
  - `ContentView.swift` rewired to the new view; `MarkdownOutlineParser`/`MarkdownView`/per-section rendering removed. `swift-markdown-ui` dependency retained (unused for now) for the planned Step 2.
  - Tests: `MarkdownReaderTests/MarkdownAttributedRendererTests.swift` (Swift Testing) — 7 tests for heading extraction/ranges, bold/italic/inline-code, code blocks, links, empty docs. All pass via `-only-testing:MarkdownReaderTests`. Build green; smoke-launched with a sample file, no crash.
  - Known Step-1 caveats (intentional): code blocks use a flat background (no rounded card), blockquotes use indent+tint (no accent bar), tables/images fall back to plain text. Plan: `~/.claude/plans/sleepy-sniffing-abelson.md`. Step 2 = embed SwiftUI tables/images as view-based attachments.
  - Not reviewed by the advisor tool (overloaded during this session).
- Real-document fixes (tested against `~/stacks/biorad/urt-training-docs/Unity Real Time.md`):
  - HTML comments (`<!-- ... -->`) are now stripped before parsing instead of showing as literal text.
  - GFM tables now render as a real grid via `NSTextTable`/`NSTextTableBlock` (previously each cell showed on its own line). Selection still flows through.
  - Local images now render: the document's folder URL is threaded from `MarkdownReaderApp` (`file.fileURL`) → `ContentView` → renderer, which resolves relative paths (e.g. `assets/foo.png`) and embeds them as `NSTextAttachment`. Unreadable images fall back to a `🖼 alt` placeholder.
  - Sidebar widened (`navigationSplitViewColumnWidth` moved onto the sidebar content; min 240 / ideal 300).
  - **App Sandbox disabled** (`MarkdownReader.entitlements`): proved via the running app that sibling image reads failed with `EPERM "Operation not permitted"` — the sandbox grants access only to the file opened via the panel, not its `assets/` siblings. Verified after disabling: all 29 images in the test doc load. Trade-off (user-approved): the app is no longer sandboxed and is not Mac App Store eligible.
  - Tests extended (now 10 renderer tests): HTML-comment stripping, table → `NSTextTable`, image-syntax detection. All pass via `-only-testing:MarkdownReaderTests`.
- Reading-experience refinements:
  - Larger text (body 15→17pt, headings scaled up, slightly looser line/paragraph spacing) for comfortable reading.
  - Reading column set to a common ~800pt measure, centered in a wider container; default window widened to 1200×820.
  - Images are now interactive: pointing-hand cursor on hover and clicking one opens a full-window `ImageLightbox` (semi-black backdrop, click or Esc to dismiss). Image hit-testing uses the layout manager's attachment glyph rects; the click handler is threaded `SelectableMarkdownView.onImageTap` → `ContentView` state.
  - Cursor fix: `resetCursorRects`/`addCursorRect` does not work inside `NSTextView` (it manages its own I-beam via tracking areas). Switched to per-image `NSTrackingArea` with `.cursorUpdate` + a `cursorUpdate(with:)` override that sets `.pointingHand` over images.
- Round 3 fixes:
  - Code block: discovered (via a render-to-image probe) that a plain `NSTextBlock` background does **not** draw — only `NSTextTableBlock` does. Switched code blocks to a single-cell `NSTextTable` with `backgroundColor` + padding: reliable gray box, uniform padding, and wrapped lines stay indented inside the box.
  - App icon: removed the squircle background (was a faint white box under the emoji); icon is now the emoji alone on transparent, sized to ~iBooks fill (`fontSize = body.width * 1.02`; `drawBackground` flag in the script to re-enable a filled square).
  - Decided (user): long inline-code spans that wrap show a continuous gray region because each wrapped line fragment's `.backgroundColor` abuts — inherent to attributed-string inline backgrounds. Accepted as-is; keep the gray background on all inline code.
- Round 2 fixes:
  - Code block background: the `NSTextBlock` background didn't render reliably, so reverted to the inline-code gray as a per-character `.backgroundColor` (newline fills each line to full width → one solid box) with empty top/bottom padding lines. Same color as inline code.
  - List indentation: marker now uses a tab + an explicit `NSTextTab`/`headIndent` at `indent + markerWidth`, so wrapped lines hang-align under the text instead of drifting left of it.
- Follow-up fixes:
  - Code blocks now render as one padded background box via a shared `NSTextBlock` (`appendCodeBlock`), replacing the ragged per-glyph `.backgroundColor` highlight. Trailing newlines trimmed so the box ends at the last code line.
  - Cursor blink fixed: the per-image `.cursorUpdate` tracking area wasn't enough because `NSTextView.mouseMoved` kept restoring the I-beam. Now a visible-rect `.mouseMoved` tracking area + a `mouseMoved` override sets `.pointingHand` over images without calling super (so the I-beam isn't restored); `acceptsMouseMovedEvents` enabled in `viewDidMoveToWindow`.
  - Icon-in-Dock was a cache artifact (source PNGs are all exact sizes; `actool` builds a complete `AppIcon.icns`). Refresh with `lsregister -f <app>` + `killall Dock` after a rebuild.
- App icon: added `scripts/make-emoji-icon.swift` (renders an Apple color emoji on a macOS-style rounded gradient via Core Text). Generated 📒 at all macOS sizes into `Assets.xcassets/AppIcon.appiconset` and rewrote `Contents.json` (mac-only). To change the icon, edit the emoji/colors in the script and re-run per size. Builds into `AppIcon.icns`.

## 2026-03-12

- Initial onboarding pass for an older SwiftUI markdown reader project.
- Repo currently has no `README.md`; this file records the observed baseline for future sessions.
- App shape:
  - SwiftUI document-based app using `DocumentGroup`.
  - Opens markdown files via `UTType` `net.daringfireball.markdown`.
  - Renders content with `MarkdownUI` (`swift-markdown-ui` 2.4.1).
  - Current UI is a single scroll view with padded markdown content.
- Current limitations:
  - No visible empty/error/loading states.
  - No app-level polish such as window title handling, toolbar actions, theming, or reading affordances.
  - `FileDocument` only reads UTF-8 and always exposes write support even though the app is intended to be a reader.
  - Unit and UI tests are template placeholders only.
  - Validation via `xcodebuild` is currently blocked because the active developer directory points to Command Line Tools instead of full Xcode.
- Likely next work:
  - Decide the target platform focus, likely macOS-first.
  - Define the intended reader-only behavior and trim editing semantics if needed.
  - Add focused tests around document loading and markdown rendering boundaries where practical.
  - Add basic project documentation and usage notes once behavior is clarified.
- Project setting update:
  - Switched all targets from `SWIFT_VERSION = 5.0` to `SWIFT_VERSION = 6.0` in the Xcode project to opt into Swift 6 language mode.
  - Updated `xcode-select` to `/Applications/Xcode.app/Contents/Developer`.
  - Verified with `xcodebuild -scheme MarkdownReader -project MarkdownReader.xcodeproj -destination 'platform=macOS' build`.
  - Result: macOS build succeeded under Swift 6.
  - Removed the remaining App Intents metadata warning for the app target by setting `APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING = NO`.
  - Verified again with `xcodebuild -scheme MarkdownReader -project MarkdownReader.xcodeproj -destination 'platform=macOS,arch=arm64' -quiet build`.
- Reader-only behavior update:
  - Switched the app scene from `DocumentGroup(newDocument:)` to `DocumentGroup(viewing:)`.
  - Removed the editable binding from `ContentView`.
  - Changed the sandbox entitlement from `com.apple.security.files.user-selected.read-write` to `com.apple.security.files.user-selected.read-only`.
- Navigation update:
  - Replaced the single-pane reader with a `NavigationSplitView`.
  - Added a heading-based table of contents sidebar for Markdown ATX headings.
  - Added `SidebarCommands()` so the sidebar can be toggled from the macOS `View` menu.
- Release snapshot:
  - Prepared `0.1.0` as the first tagged preview/stable-ish checkpoint for the current macOS reader state.
  - Current known limitations remain: unresolved `Locked` subtitle in the title bar, non-native cross-block text selection with `MarkdownUI`, placeholder tests, and narrow file decoding behavior.
