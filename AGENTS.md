# AGENTS

Project-scoped guidance for changes to MarkdownReader. For the detailed architecture map and known Xcode runner noise, see `CLAUDE.md`.

## Product boundaries

- Keep MarkdownReader a macOS-first, reader-only document app. Do not introduce editing behavior without an explicit product decision.
- Render each document in one persistent `WKWebView`; do not split Markdown blocks across native views or multiple web views.
- Keep safe Markdown conversion in `MarkdownReaderShared`, interactive app HTML in `MarkdownHTMLDocument`, and native/WebKit boundary behavior in `MarkdownWebView`.
- Treat Markdown and linked resources as untrusted. Preserve raw-HTML filtering, the restrictive CSP, external-navigation handling, and canonical path validation. Do not add remote rendering dependencies.

## Platform boundaries

- The main app sandbox is intentionally disabled so document-relative sibling images remain readable. Do not re-enable it without a folder-grant or security-scoped-bookmark design.
- The Quick Look extension must remain sandboxed, read-only, self-contained, and script-free. It may only assume access to the Markdown file supplied by macOS.
- Keep the app and Quick Look extension on the exact `net.daringfireball.markdown` UTI. Filename-extension tags are `md` and `markdown` without leading dots.
- Preserve `DocumentGroup(viewing:)`, disabled scene restoration, the native table-of-contents sidebar, and macOS-managed Quick Look activation.

## Change and validation rules

- Prefer focused changes and preserve the current SwiftUI/AppKit/WebKit boundaries.
- Add unit coverage with Swift Testing in `MarkdownReaderTests`; use UI tests only for behavior that cannot be validated below the UI layer.
- Use `scripts/build-production.sh` for a complete test, clean Release build, signature check, and package validation. An ad-hoc result is local-only; public distribution additionally requires Developer ID signing and notarization.
- For UI behavior or visual conventions, update `spec/ui.md` when the implemented contract changes.

## Documentation and versions

- Keep `README.md` accurate for user-facing behavior and setup, append notable implementation findings to `DEVLOG.md`, and record release-facing changes in `CHANGELOG.md`.
- Keep the app and Quick Look `MARKETING_VERSION` values aligned. Update the README release snapshot and changelog in the same release change.
- Do not bump versions, create release commits, or add legal/distribution metadata unless requested.
