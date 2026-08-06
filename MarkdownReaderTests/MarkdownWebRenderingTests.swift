//
//  MarkdownWebRenderingTests.swift
//  MarkdownReaderTests
//

import AppKit
import Foundation
import Testing
import WebKit
@testable import MarkdownReader

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    var continuation: CheckedContinuation<Void, Error>?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

struct MarkdownWebRenderingTests {
    private struct Diagnostics: Decodable {
        let tableCount: Int
        let codeBlockCount: Int
        let highlightedTokenCount: Int
        let fontSize: String
        let contentWidth: String
        let bodyLeft: Double
        let bodyContentLeft: Double
        let bodyContentRight: Double
        let markdownLeft: Double
        let markdownRight: Double
        let theme: String
        let imageLoaded: Bool
    }

    @Test @MainActor
    func loadsStylesHighlightsAndUpdatesOneDocumentInPlace() async throws {
        let documentRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownReaderWebRenderingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: documentRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: documentRoot) }
        let image = """
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="20">
          <rect width="32" height="20" fill="#0969da"/>
        </svg>
        """
        try Data(image.utf8).write(to: documentRoot.appendingPathComponent("sample.svg"))

        let markdown = """
        # Web renderer

        > A padded blockquote.

        ![Local image](sample.svg)

        | Current | Replacement |
        | --- | --- |
        | `ALIYUN_ACR_REGISTRY` | `AWS_ECR_REGISTRY` |

        ```swift
        struct ReaderOptions {
            let fontSize: Double
        }
        ```

        ```python
        def greet(name: str) -> str:
            return f"Hello, {name}!"
        ```
        """
        let rendered = MarkdownHTMLRenderer.render(markdown)
        let options = ReaderDisplayOptions(
            fontSize: 18,
            lineHeight: 1.7,
            contentWidthPercentage: 75,
            theme: .dark,
            syntaxHighlighting: true
        )
        let page = MarkdownHTMLDocument.make(bodyHTML: rendered.bodyHTML, options: options)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let resourceHandler = MarkdownResourceSchemeHandler(documentRootURL: documentRoot)
        configuration.setURLSchemeHandler(
            resourceHandler,
            forURLScheme: MarkdownResourceResolver.scheme
        )
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 2000, height: 900),
            configuration: configuration
        )
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter

        try await withCheckedThrowingContinuation { continuation in
            waiter.continuation = continuation
            webView.loadHTMLString(
                page,
                baseURL: URL(string: "\(MarkdownResourceResolver.scheme)://document/")
            )
        }

        let diagnosticsJSON = try #require(
            try await webView.evaluateJavaScript(
                """
                (() => {
                  const body = document.body;
                  const markdown = document.querySelector('.markdown-body');
                  const bodyRect = body.getBoundingClientRect();
                  const markdownRect = markdown.getBoundingClientRect();
                  const bodyStyle = getComputedStyle(body);
                  const paddingLeft = parseFloat(bodyStyle.paddingLeft);
                  const paddingRight = parseFloat(bodyStyle.paddingRight);
                  return JSON.stringify({
                    tableCount: document.querySelectorAll('table').length,
                    codeBlockCount: document.querySelectorAll('.code-block').length,
                    highlightedTokenCount: document.querySelectorAll('[class^="hljs-"]').length,
                    fontSize: bodyStyle.fontSize,
                    contentWidth: markdownRect.width + 'px',
                    bodyLeft: bodyRect.left,
                    bodyContentLeft: bodyRect.left + paddingLeft,
                    bodyContentRight: bodyRect.right - paddingRight,
                    markdownLeft: markdownRect.left,
                    markdownRight: markdownRect.right,
                    theme: document.documentElement.dataset.theme,
                    imageLoaded: Boolean(document.querySelector('img')?.complete &&
                      document.querySelector('img')?.naturalWidth > 0)
                  });
                })()
                """
            ) as? String
        )
        let diagnostics = try JSONDecoder().decode(
            Diagnostics.self,
            from: Data(diagnosticsJSON.utf8)
        )

        #expect(diagnostics.tableCount == 1)
        #expect(diagnostics.codeBlockCount == 2)
        #expect(diagnostics.highlightedTokenCount > 0)
        #expect(diagnostics.fontSize == "18px")
        #expect(diagnostics.contentWidth == "1428px")
        #expect(diagnostics.bodyLeft > 0)
        #expect(abs(diagnostics.bodyContentLeft - diagnostics.markdownLeft) < 0.5)
        #expect(abs(diagnostics.bodyContentRight - diagnostics.markdownRight) < 0.5)
        #expect(diagnostics.theme == "dark")
        #expect(diagnostics.imageLoaded)

        _ = try await webView.evaluateJavaScript(
            """
            window.reader.applySettings({
              fontSize: 14,
              lineHeight: 1.3,
              contentWidthPercentage: 100,
              theme: 'light',
              syntaxHighlighting: false
            });
            """
        )
        let updatedState = try #require(
            try await webView.evaluateJavaScript(
                """
                JSON.stringify({
                  fontSize: getComputedStyle(document.body).fontSize,
                  contentWidth: document.querySelector('.markdown-body').getBoundingClientRect().width + 'px',
                  theme: document.documentElement.dataset.theme,
                  highlightedBlocks: document.querySelectorAll('code.hljs').length
                })
                """
            ) as? String
        )

        #expect(updatedState.contains("\"fontSize\":\"14px\""))
        #expect(updatedState.contains("\"contentWidth\":\"1904px\""))
        #expect(updatedState.contains("\"theme\":\"light\""))
        #expect(updatedState.contains("\"highlightedBlocks\":0"))

        webView.setFrameSize(NSSize(width: 600, height: 900))
        let narrowContentWidth = try #require(
            try await webView.evaluateJavaScript(
                "document.querySelector('.markdown-body').getBoundingClientRect().width"
            ) as? Double
        )
        #expect(abs(narrowContentWidth - 552) < 0.5)

    }

}
