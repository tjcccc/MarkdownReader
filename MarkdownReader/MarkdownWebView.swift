//
//  MarkdownWebView.swift
//  MarkdownReader
//
//  One persistent WKWebView renders the complete document so text selection,
//  tables, code blocks, and block styling all share one HTML layout surface.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct MarkdownResourceResolver {
    static let scheme = "markdown-reader-resource"

    private let rootURL: URL?

    init(rootURL: URL?) {
        self.rootURL = rootURL?
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    func resolveDocumentURL(_ requestURL: URL) -> URL? {
        guard requestURL.scheme == Self.scheme,
              requestURL.host == "document",
              let rootURL,
              let decodedPath = requestURL.path.removingPercentEncoding
        else {
            return nil
        }

        let relativePath = decodedPath.drop(while: { $0 == "/" })
        guard !relativePath.isEmpty else { return nil }

        let candidate = rootURL
            .appendingPathComponent(String(relativePath))
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"

        guard candidate.path.hasPrefix(rootPath) else { return nil }
        return candidate
    }
}

final class MarkdownResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    let resolver: MarkdownResourceResolver

    init(documentRootURL: URL?) {
        resolver = MarkdownResourceResolver(rootURL: documentRootURL)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let resourceURL = resourceURL(for: requestURL)
        else {
            urlSchemeTask.didFailWithError(CocoaError(.fileReadNoSuchFile))
            return
        }

        do {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: resourceURL.path,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue else {
                throw CocoaError(.fileReadNoSuchFile)
            }

            let data = try Data(contentsOf: resourceURL)
            let contentType = UTType(filenameExtension: resourceURL.pathExtension)
            let mimeType = contentType?.preferredMIMEType ?? "application/octet-stream"
            let encoding = contentType?.conforms(to: .text) == true
                || contentType?.conforms(to: .javaScript) == true
                ? "utf-8"
                : nil
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: encoding
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Resources are loaded synchronously, so there is no outstanding task to cancel.
    }

    private func resourceURL(for requestURL: URL) -> URL? {
        switch requestURL.host {
        case "document":
            return resolver.resolveDocumentURL(requestURL)
        case "app":
            guard requestURL.path == "/highlight.min.js" else { return nil }
            return Bundle.main.url(
                forResource: "highlight.min",
                withExtension: "js",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "highlight.min", withExtension: "js")
        default:
            return nil
        }
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let rendered: RenderedMarkdown
    let documentRootURL: URL?
    let displayOptions: ReaderDisplayOptions
    var scrollAnchor: String?
    var onImageTap: ((NSImage) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(documentRootURL: documentRootURL, onImageTap: onImageTap)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "copyCode")
        configuration.userContentController.add(context.coordinator, name: "imageClicked")
        configuration.setURLSchemeHandler(
            context.coordinator.resourceHandler,
            forURLScheme: MarkdownResourceResolver.scheme
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = .clear
        context.coordinator.webView = webView
        context.coordinator.load(rendered, options: displayOptions, in: webView)
        context.coordinator.requestScroll(to: scrollAnchor)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onImageTap = onImageTap

        if context.coordinator.lastBodyHTML != rendered.bodyHTML {
            context.coordinator.load(rendered, options: displayOptions, in: webView)
        } else {
            context.coordinator.apply(displayOptions)
        }
        context.coordinator.requestScroll(to: scrollAnchor)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "copyCode")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "imageClicked")
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        fileprivate let resourceHandler: MarkdownResourceSchemeHandler
        fileprivate weak var webView: WKWebView?
        fileprivate var onImageTap: ((NSImage) -> Void)?
        fileprivate var lastBodyHTML: String?

        private var latestOptions: ReaderDisplayOptions?
        private var lastScrollAnchor: String?
        private var pageIsReady = false

        init(documentRootURL: URL?, onImageTap: ((NSImage) -> Void)?) {
            resourceHandler = MarkdownResourceSchemeHandler(documentRootURL: documentRootURL)
            self.onImageTap = onImageTap
        }

        fileprivate func load(
            _ rendered: RenderedMarkdown,
            options: ReaderDisplayOptions,
            in webView: WKWebView
        ) {
            lastBodyHTML = rendered.bodyHTML
            latestOptions = options
            lastScrollAnchor = nil
            pageIsReady = false

            let document = MarkdownHTMLDocument.make(
                bodyHTML: rendered.bodyHTML,
                options: options
            )
            let baseURL = URL(string: "\(MarkdownResourceResolver.scheme)://document/")
            webView.loadHTMLString(document, baseURL: baseURL)
        }

        fileprivate func apply(_ options: ReaderDisplayOptions) {
            guard latestOptions != options else { return }
            latestOptions = options
            guard pageIsReady else { return }
            evaluateSettings(options)
        }

        fileprivate func requestScroll(to anchor: String?) {
            guard lastScrollAnchor != anchor else { return }
            lastScrollAnchor = anchor
            guard pageIsReady, let anchor else { return }
            evaluateScroll(to: anchor)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageIsReady = true
            if let latestOptions {
                evaluateSettings(latestOptions)
            }
            if let lastScrollAnchor {
                evaluateScroll(to: lastScrollAnchor)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == MarkdownResourceResolver.scheme,
               let fileURL = resourceHandler.resolver.resolveDocumentURL(url) {
                NSWorkspace.shared.open(fileURL)
                decisionHandler(.cancel)
                return
            }

            if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "copyCode":
                guard let code = message.body as? String else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(code, forType: .string)
            case "imageClicked":
                guard let source = message.body as? String,
                      let requestURL = URL(string: source),
                      let fileURL = resourceHandler.resolver.resolveDocumentURL(requestURL),
                      let image = NSImage(contentsOf: fileURL)
                else {
                    return
                }
                onImageTap?(image)
            default:
                break
            }
        }

        private func evaluateSettings(_ options: ReaderDisplayOptions) {
            let settings = MarkdownHTMLDocument.settingsJSON(options)
            webView?.evaluateJavaScript("window.reader?.applySettings(\(settings));")
        }

        private func evaluateScroll(to anchor: String) {
            let encodedAnchor = javaScriptString(anchor)
            webView?.evaluateJavaScript("window.reader?.scrollToHeading(\(encodedAnchor));")
        }

        private func javaScriptString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value) else { return "\"\"" }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
