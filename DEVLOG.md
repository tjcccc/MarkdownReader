# DEVLOG

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
