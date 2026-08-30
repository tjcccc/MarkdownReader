//
//  PreviewViewController.swift
//  MarkdownReaderQuickLook
//

import AppKit
import Foundation
import OSLog
import QuickLookUI
import WebKit

@MainActor
final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController,
    WKNavigationDelegate
{
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.taojiachun.MarkdownReader.QuickLookPreview",
        category: "PreviewViewController"
    )

    private var webView: WKWebView!

    override func loadView() {
        let initialFrame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let root = NSView(frame: initialFrame)
        root.autoresizesSubviews = true

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(
            frame: initialFrame,
            configuration: configuration
        )
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.setAccessibilityLabel("Markdown preview")
        root.addSubview(webView)
        self.webView = webView

        preferredContentSize = initialFrame.size
        view = root
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping ((any Error)?) -> Void
    ) {
        Self.logger.debug("Preparing script-free WebKit Markdown preview")

        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            guard let markdown = String(data: data, encoding: .utf8) else {
                throw PreviewError.unsupportedTextEncoding
            }

            let rendered = MarkdownHTMLRenderer.render(markdown)
            let page = MarkdownQuickLookHTMLDocument.make(bodyHTML: rendered.bodyHTML)
            title = url.lastPathComponent
            webView.loadHTMLString(page, baseURL: nil)
            Self.logger.debug("Prepared script-free WebKit Markdown preview")
            handler(nil)
        } catch {
            Self.logger.error("Could not prepare preview: \(error.localizedDescription, privacy: .private)")
            handler(error)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(
                  [.command, .shift, .option, .control]
              ) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased(),
              key == "a" || key == "c" else {
            return super.performKeyEquivalent(with: event)
        }

        if webView.performKeyEquivalent(with: event) {
            return true
        }

        let selector = key == "a"
            ? #selector(NSText.selectAll(_:))
            : #selector(NSText.copy(_:))
        return view.window?.firstResponder?.tryToPerform(selector, with: nil) == true
            || super.performKeyEquivalent(with: event)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor @Sendable (
            WKNavigationActionPolicy,
            WKWebpagePreferences
        ) -> Void
    ) {
        preferences.allowsContentJavaScript = false

        guard navigationAction.navigationType == .linkActivated else {
            decisionHandler(.allow, preferences)
            return
        }

        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto"].contains(scheme) {
            extensionContext?.open(url)
        }
        decisionHandler(.cancel, preferences)
    }

}

private enum PreviewError: LocalizedError {
    case unsupportedTextEncoding

    var errorDescription: String? {
        switch self {
        case .unsupportedTextEncoding:
            "MarkdownReader Quick Look supports UTF-8 Markdown files."
        }
    }
}
