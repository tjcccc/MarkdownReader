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
              let rootURL
        else {
            return nil
        }

        // URL.path is already percent-decoded; decoding again would turn a
        // literal "%20" in a file name into a space.
        let relativePath = requestURL.path.drop(while: { $0 == "/" })
        guard !relativePath.isEmpty else { return nil }

        let candidate = rootURL
            .appendingPathComponent(String(relativePath))
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"

        guard candidate.path.hasPrefix(rootPath) else { return nil }
        return candidate
    }

    /// Whether a clicked document-relative link may open in its default app.
    /// Anything else, such as apps, scripts, packages, or folders, is only
    /// revealed in Finder so a link click can never launch code.
    static func opensLinkedFileDirectly(_ fileURL: URL) -> Bool {
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
        guard values?.isRegularFile == true, let type = values?.contentType else { return false }
        let viewable: [UTType] = [.image, .pdf, .audiovisualContent, .plainText]
        let executable: [UTType] = [.executable, .script, .shellScript]
        return viewable.contains { type.conforms(to: $0) }
            && !executable.contains { type.conforms(to: $0) }
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
    var onActiveHeadingChange: ((String) -> Void)?
    var onImageTap: ((NSImage) -> Void)?
    var backRequestID: UUID?
    var onBackAvailabilityChange: ((Bool) -> Void)?
    var findRequest: FindRequest?
    var onFindBarHeightChange: ((CGFloat) -> Void)?

    struct FindRequest: Equatable {
        let id = UUID()
        let action: NSTextFinder.Action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            documentRootURL: documentRootURL,
            onImageTap: onImageTap,
            onActiveHeadingChange: onActiveHeadingChange,
            onBackAvailabilityChange: onBackAvailabilityChange
        )
    }

    func makeNSView(context: Context) -> MarkdownReaderWebContainer {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "copyCode")
        configuration.userContentController.add(context.coordinator, name: "imageClicked")
        configuration.userContentController.add(context.coordinator, name: "activeHeadingChanged")
        configuration.userContentController.add(context.coordinator, name: "backAvailabilityChanged")
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
        let container = MarkdownReaderWebContainer(webView: webView)
        container.onFindBarHeightChange = onFindBarHeightChange
        context.coordinator.requestFind(findRequest, in: container)
        return container
    }

    func updateNSView(_ container: MarkdownReaderWebContainer, context: Context) {
        let webView = container.webView
        container.onFindBarHeightChange = onFindBarHeightChange
        context.coordinator.onImageTap = onImageTap
        context.coordinator.onActiveHeadingChange = onActiveHeadingChange
        context.coordinator.onBackAvailabilityChange = onBackAvailabilityChange

        if context.coordinator.lastBodyHTML != rendered.bodyHTML {
            context.coordinator.load(rendered, options: displayOptions, in: webView)
        } else {
            context.coordinator.apply(displayOptions)
        }
        context.coordinator.requestScroll(to: scrollAnchor)
        context.coordinator.goBack(backRequestID)
        context.coordinator.requestFind(findRequest, in: container)
    }

    static func dismantleNSView(_ container: MarkdownReaderWebContainer, coordinator: Coordinator) {
        let webView = container.webView
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "copyCode")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "imageClicked")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "activeHeadingChanged")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "backAvailabilityChanged")
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        fileprivate let resourceHandler: MarkdownResourceSchemeHandler
        fileprivate weak var webView: WKWebView?
        fileprivate var onImageTap: ((NSImage) -> Void)?
        fileprivate var onActiveHeadingChange: ((String) -> Void)?
        fileprivate var onBackAvailabilityChange: ((Bool) -> Void)?
        fileprivate var lastBodyHTML: String?

        private var latestOptions: ReaderDisplayOptions?
        private var lastScrollAnchor: String?
        private var lastBackRequestID: UUID?
        private var lastFindRequestID: UUID?
        private var pageIsReady = false
        private var pendingScrollY: Double?
        private var headingAnchors: Set<String> = []

        init(
            documentRootURL: URL?,
            onImageTap: ((NSImage) -> Void)?,
            onActiveHeadingChange: ((String) -> Void)? = nil,
            onBackAvailabilityChange: ((Bool) -> Void)? = nil
        ) {
            resourceHandler = MarkdownResourceSchemeHandler(documentRootURL: documentRootURL)
            self.onImageTap = onImageTap
            self.onActiveHeadingChange = onActiveHeadingChange
            self.onBackAvailabilityChange = onBackAvailabilityChange
        }

        fileprivate func load(
            _ rendered: RenderedMarkdown,
            options: ReaderDisplayOptions,
            in webView: WKWebView
        ) {
            let isReload = pageIsReady
            lastBodyHTML = rendered.bodyHTML
            latestOptions = options
            lastScrollAnchor = nil
            pageIsReady = false
            pendingScrollY = nil
            headingAnchors = Set(rendered.toc.map(\.anchor))

            let document = MarkdownHTMLDocument.make(
                bodyHTML: rendered.bodyHTML,
                options: options
            )
            let baseURL = URL(string: "\(MarkdownResourceResolver.scheme)://document/")
            guard isReload else {
                webView.loadHTMLString(document, baseURL: baseURL)
                return
            }
            // Keep the reading position when the file changes on disk.
            webView.evaluateJavaScript("window.scrollY") { [weak self, weak webView] value, _ in
                guard let self, let webView, self.lastBodyHTML == rendered.bodyHTML else { return }
                self.pendingScrollY = value as? Double
                webView.loadHTMLString(document, baseURL: baseURL)
            }
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

        fileprivate func requestFind(_ request: FindRequest?, in container: MarkdownReaderWebContainer) {
            guard let request, lastFindRequestID != request.id else { return }
            lastFindRequestID = request.id
            container.performFindAction(request.action)
        }

        fileprivate func goBack(_ requestID: UUID?) {
            guard pageIsReady, let requestID, lastBackRequestID != requestID else { return }
            lastBackRequestID = requestID
            webView?.evaluateJavaScript("window.reader?.goBack();")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageIsReady = true
            if let latestOptions {
                evaluateSettings(latestOptions)
            }
            if let pendingScrollY {
                self.pendingScrollY = nil
                webView.evaluateJavaScript("window.scrollTo(0, \(pendingScrollY));")
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
                if MarkdownResourceResolver.opensLinkedFileDirectly(fileURL) {
                    NSWorkspace.shared.open(fileURL)
                } else if FileManager.default.fileExists(atPath: fileURL.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
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
            case "activeHeadingChanged":
                // Content above the first heading or under an untitled heading
                // has no outline row, so it clears the selection.
                guard message.frameInfo.isMainFrame,
                      let anchor = message.body as? String else { return }
                onActiveHeadingChange?(headingAnchors.contains(anchor) ? anchor : "")
            case "backAvailabilityChanged":
                guard message.frameInfo.isMainFrame,
                      let available = message.body as? Bool else { return }
                onBackAvailabilityChange?(available)
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
