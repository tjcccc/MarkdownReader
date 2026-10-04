# TODO

## Mac App Store publication

Prerequisites for publishing. The new app name is still being decided; the rename (product `<New Name>.app` with the Swift module pinned to `MarkdownReader`) can happen alongside this work.

- [ ] **Re-enable the App Sandbox with folder access for sibling images.**
  The main app turns the sandbox off (`MarkdownReader/MarkdownReader.entitlements`) because a sandboxed app only gets the opened file, so images beside it (for example `./assets/foo.png`) can't load. The App Store requires the sandbox.
  - Turn on `com.apple.security.app-sandbox` with `com.apple.security.files.user-selected.read-only`.
  - When a document references local images, ask once for access to its folder (`NSOpenPanel` preselecting that folder), then store a security-scoped bookmark so later opens need no prompt.
  - Resolve the bookmark and wrap file reads in `startAccessingSecurityScopedResource()` / `stop…`, especially in `MarkdownResourceSchemeHandler` and image previews.
  - Without access, show images as inert placeholders (like Quick Look) instead of failing silently.
  - Re-check every out-of-sandbox assumption: document-relative links revealed in Finder, file monitoring (`DocumentFileMonitor`), and the duplicate-registration cleanup script.

- [ ] **Make Favorites sandbox-safe.**
  `FavoritesStore` saves ordinary file bookmarks, which a sandboxed app can't use to reopen files later.
  - Create bookmarks with `.withSecurityScope` (and `.securityScopeAllowOnlyReadAccess`), and resolve them with `.withSecurityScope`.
  - Start and stop security-scoped access around opening a favorite.
  - Migrate existing favorites: renew the bookmark the next time the user opens the document, or drop entries that can't be upgraded and say so once.
  - Keep the current behavior: follow renames and moves, and explain and remove missing files.

- [ ] **Set up App Store signing and distribution.**
  Builds are currently ad-hoc signed and local-only (`scripts/build-production.sh` warns about this).
  - Join the Apple Developer Program, set the team, and use App Store distribution signing for the app and the embedded Quick Look extension (both sandboxed, matching bundle ID prefixes).
  - Add an Archive → App Store Connect upload path (Xcode Organizer or `xcodebuild -exportArchive` with an App Store export options plist), and keep the ad-hoc local build as is.
  - Prepare App Store Connect metadata: final name, privacy details (no data collected), screenshots, and the review notes explaining the folder-access prompt.
