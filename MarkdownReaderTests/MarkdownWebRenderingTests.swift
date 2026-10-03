//
//  MarkdownWebRenderingTests.swift
//  MarkdownReaderTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import MarkdownReader

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var continuation: CheckedContinuation<Void, Error>?
    var activeHeadingAnchors: [String] = []

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == "activeHeadingChanged", let anchor = message.body as? String {
            activeHeadingAnchors.append(anchor)
        }
    }

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

@Suite(.serialized)
struct MarkdownWebRenderingTests {
    @Test @MainActor
    func findBarBackgroundDoesNotPaintOutsideItsBounds() throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let dirtyRect = NSRect(x: 0, y: 0, width: 100, height: 100)
        NSColor.systemPink.setFill()
        dirtyRect.fill()
        let originalColor = try #require(bitmap.colorAt(x: 50, y: 50))
        let bar = ReaderFindBarView(frame: NSRect(x: 0, y: 0, width: 100, height: 36))
        // AppKit can invalidate beyond a non-clipping view's bounds.
        bar.draw(dirtyRect)
        #expect(bitmap.colorAt(x: 50, y: 50) == originalColor)
    }

    @Test @MainActor
    func nativeFindBarSearchesRenderedTextWithoutReplaceOrReload() async throws {
        let paragraphs = Array(repeating: "Ordinary reading\ncontent.\n\n", count: 30).joined()
        let rendered = MarkdownHTMLRenderer.render(
            "# Search document\n\nNeedle first.\n\n\(paragraphs)**Nee**dle second.\n\n\(paragraphs)"
        )
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(
            MarkdownResourceSchemeHandler(documentRootURL: nil),
            forURLScheme: MarkdownResourceResolver.scheme
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let container = MarkdownReaderWebContainer(webView: webView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        defer {
            webView.stopLoading()
            window.close()
        }
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        try await withCheckedThrowingContinuation { continuation in
            waiter.continuation = continuation
            webView.loadHTMLString(
                MarkdownHTMLDocument.make(bodyHTML: rendered.bodyHTML, options: ReaderDisplayOptions(
                    fontSize: 17, lineHeight: 1.6, contentWidthPercentage: 75,
                    theme: .system, syntaxHighlighting: false
                )),
                baseURL: URL(string: "\(MarkdownResourceResolver.scheme)://document/")
            )
        }
        _ = try await webView.evaluateJavaScript("window.findTestDocument = document; void 0;")
        container.performFindAction(.showFindInterface)
        container.layoutSubtreeIfNeeded()
        #expect(container.isFindBarVisible)
        let bar = try #require(container.subviews.compactMap { $0 as? ReaderFindBarView }.first)
        #expect(bar.clipsToBounds)
        #expect(bar.frame.height == MarkdownReaderWebContainer.findBarHeight)
        #expect(webView.frame.minY == bar.frame.height)
        #expect(webView.frame.maxY == container.bounds.maxY)
        func descendants(of view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants(of: $0) }
        }
        let searchField = try #require(descendants(of: bar).compactMap { $0 as? NSSearchField }.first)
        #expect(searchField.currentEditor() != nil)
        #expect(!descendants(of: bar).compactMap { $0 as? NSButton }.contains {
            $0.title == "Replace" && !$0.isHiddenOrHasHiddenAncestor
        })
        let editor = try #require(searchField.currentEditor() as? NSTextView)
        editor.string = "Needle"
        editor.didChangeText()
        searchField.validateEditing()
        searchField.sendAction(searchField.action, to: searchField.target)
        container.performFindAction(.nextMatch)
        var selectedText = ""
        for _ in 0..<100 {
            selectedText = (try await webView.evaluateJavaScript("window.getSelection().toString()") as? String) ?? ""
            if selectedText == "Needle" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(selectedText == "Needle")
        let countCell = try #require(searchField.cell as? ReaderSearchFieldCell)
        for _ in 0..<100 {
            if countCell.matchSummary.hasSuffix("/2") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let firstSummary = countCell.matchSummary
        #expect(["1/2", "2/2"].contains(firstSummary))
        let otherSummary = firstSummary == "1/2" ? "2/2" : "1/2"
        let ordinaryCount = try await webView.evaluateJavaScript("window.reader.searchPosition('READING content.').total")
        #expect(ordinaryCount as? Int == 60)
        let literalCount = try await webView.evaluateJavaScript("window.reader.searchPosition('.*').total")
        #expect(literalCount as? Int == 0)
        let firstY = try #require(try await webView.evaluateJavaScript("window.scrollY") as? Double)
        container.performFindAction(.nextMatch)
        var nextY = firstY
        for _ in 0..<100 {
            nextY = try #require(try await webView.evaluateJavaScript("window.scrollY") as? Double)
            if abs(nextY - firstY) > 500 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(abs(nextY - firstY) > 500)
        for _ in 0..<100 {
            if countCell.matchSummary == otherSummary { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(countCell.matchSummary == otherSummary)
        container.performFindAction(.previousMatch)
        for _ in 0..<100 {
            let y = try #require(try await webView.evaluateJavaScript("window.scrollY") as? Double)
            if abs(y - firstY) < 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let previousY = try #require(try await webView.evaluateJavaScript("window.scrollY") as? Double)
        #expect(abs(previousY - firstY) < 1)
        for _ in 0..<100 {
            if countCell.matchSummary == firstSummary { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(countCell.matchSummary == firstSummary)
        editor.string = "no-such-match"
        editor.didChangeText()
        searchField.validateEditing()
        let status = try #require(descendants(of: bar).compactMap { $0 as? NSTextField }.first {
            $0.stringValue == "Not found"
        })
        for _ in 0..<100 {
            if !status.isHiddenOrHasHiddenAncestor { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!status.isHiddenOrHasHiddenAncestor)
        #expect(countCell.matchSummary == "0/0")
        editor.string = ""
        editor.didChangeText()
        searchField.validateEditing()
        #expect(status.isHidden)
        #expect(countCell.matchSummary.isEmpty)
        container.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        container.layoutSubtreeIfNeeded()
        #expect(!container.isFindBarVisible)
        #expect(webView.frame == container.bounds)
        #expect(window.firstResponder === webView)
        // A second Escape from the document must also be safe after dismissing Find.
        container.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(!container.isFindBarVisible)
        #expect(window.firstResponder === webView)
        let sameDocumentResult = try await webView.evaluateJavaScript("document === window.findTestDocument")
        let sameDocument = try #require(sameDocumentResult as? Bool)
        #expect(sameDocument)
    }

    @Test @MainActor
    func contentsLinksScrollToTitleAnchorsAndPreserveSidebarAnchors() async throws {
        let paragraphs = Array(repeating: "Reading content.\n\n", count: 30).joined()
        let rendered = MarkdownHTMLRenderer.render(
            """
            # Contents

            [A. Current status and evidence rules](#a-current-status-and-evidence-rules)
            [Repeated](#repeated-1)
            [Encoded](#caf%C3%A9-%E4%B8%AD%E6%96%87)
            [Sidebar anchor](#heading-1)
            [Malformed](#bad%ZZ)
            [Missing](#missing)

            \(paragraphs)
            ## A. Current status and evidence rules

            \(paragraphs)
            ## Repeated

            \(paragraphs)
            ## Repeated

            \(paragraphs)
            ## *Café* `中文`!

            \(paragraphs)
            """
        )
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(
            MarkdownResourceSchemeHandler(documentRootURL: nil),
            forURLScheme: MarkdownResourceResolver.scheme
        )
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 500),
            configuration: configuration
        )
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
        defer {
            window.close()
            webView.stopLoading()
        }

        try await withCheckedThrowingContinuation { continuation in
            waiter.continuation = continuation
            webView.loadHTMLString(
                MarkdownHTMLDocument.make(bodyHTML: rendered.bodyHTML, options: ReaderDisplayOptions(
                    fontSize: 17,
                    lineHeight: 1.6,
                    contentWidthPercentage: 75,
                    theme: .system,
                    syntaxHighlighting: false
                )),
                baseURL: URL(string: "\(MarkdownResourceResolver.scheme)://document/")
            )
        }

        for (linkIndex, headingIndex) in [(0, 1), (1, 3), (2, 4), (3, 1)] {
            // Dispatch a click to verify the handler scrolls to the intended section.
            _ = try await webView.evaluateJavaScript(
                """
                document.querySelectorAll('a')[\(linkIndex)].dispatchEvent(
                  new MouseEvent('click', {bubbles: true, cancelable: true})
                );
                """
            )
            var targetTop = Double.infinity
            for _ in 0..<100 {
                targetTop = try #require(try await webView.evaluateJavaScript(
                    "document.getElementById('heading-\(headingIndex)').getBoundingClientRect().top"
                ) as? Double)
                if abs(targetTop - 24) < 1 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(abs(targetTop - 24) < 1)
        }
        let anchors = try #require(try await webView.evaluateJavaScript(
            "Array.from(document.querySelectorAll('h1, h2')).map(heading => heading.id)"
        ) as? [String])
        #expect(anchors == rendered.toc.map(\.anchor))
        // Missing and malformed fragments must stay in the document.
        for linkIndex in [4, 5] {
            let result = try await webView.evaluateJavaScript(
                """
                (() => {
                  let failed = false;
                  const onError = () => { failed = true; };
                  window.addEventListener('error', onError);
                  const event = new MouseEvent('click', {bubbles: true, cancelable: true});
                  document.querySelectorAll('a')[\(linkIndex)].dispatchEvent(event);
                  window.removeEventListener('error', onError);
                  return event.defaultPrevented && !failed;
                })()
                """
            )
            let handled = try #require(result as? Bool)
            #expect(handled)
        }
    }

    @Test @MainActor
    func backReturnsToClickedLinkAfterReflowAndClearsSavedPosition() async throws {
        let paragraphs = Array(repeating: "A paragraph that wraps when the reading font grows.\n\n", count: 35).joined()
        let rendered = MarkdownHTMLRenderer.render(
            "# Start\n\n\(paragraphs)[Jump to target](#target)\n\n[Jump to last](#last)\n\n[Missing](#missing)\n\n\(paragraphs)"
                + "## Target\n\n\(paragraphs)## Last\n\n\(paragraphs)"
        )
        var backAvailability: [Bool] = []
        var requestID: UUID?
        var scrollAnchor: String?
        var fontSize = 17.0
        func reader() -> MarkdownWebView {
            MarkdownWebView(
                rendered: rendered,
                documentRootURL: nil,
                displayOptions: ReaderDisplayOptions(
                    fontSize: fontSize,
                    lineHeight: 1.6,
                    contentWidthPercentage: 75,
                    theme: .system,
                    syntaxHighlighting: false
                ),
                scrollAnchor: scrollAnchor,
                backRequestID: requestID,
                onBackAvailabilityChange: { backAvailability.append($0) }
            )
        }
        let hostingView = NSHostingView(rootView: reader())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.close() }
        func descendant(of view: NSView) -> WKWebView? {
            if let webView = view as? WKWebView { return webView }
            return view.subviews.lazy.compactMap { descendant(of: $0) }.first
        }
        var loadedWebView: WKWebView?
        for _ in 0..<100 {
            if let webView = descendant(of: hostingView),
               (try? await webView.evaluateJavaScript("Boolean(window.reader)")) as? Bool == true,
               !backAvailability.isEmpty {
                loadedWebView = webView
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let webView = try #require(loadedWebView)
        func number(_ expression: String) async throws -> Double {
            try #require(try await webView.evaluateJavaScript(expression) as? Double)
        }
        func expectBackAvailability(_ available: Bool) async throws {
            for _ in 0..<100 {
                if backAvailability.last == available { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(backAvailability.last == available)
        }
        func expectTop(_ expression: String, _ expected: Double) async throws {
            var actual = Double.infinity
            for _ in 0..<100 {
                actual = try await number(expression)
                if abs(actual - expected) < 1 { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(abs(actual - expected) < 1, "\(expression): expected \(expected), got \(actual)")
        }
        try await expectBackAvailability(false)
        _ = try await webView.evaluateJavaScript("document.querySelectorAll('a')[2].click();")
        try await expectBackAvailability(false)
        scrollAnchor = "heading-1"
        hostingView.rootView = reader()
        try await expectTop("document.getElementById('heading-1').getBoundingClientRect().top", 24)
        try await expectBackAvailability(false)
        scrollAnchor = nil
        hostingView.rootView = reader()

        let sourceTop = try await number(
            """
            (() => {
              const source = document.querySelector('a');
              window.scrollTo({top: window.scrollY + source.getBoundingClientRect().top - 160, behavior: 'instant'});
              const top = source.getBoundingClientRect().top;
              source.click();
              return top;
            })()
            """
        )
        try await expectBackAvailability(true)
        try await expectTop("document.getElementById('heading-1').getBoundingClientRect().top", 24)
        fontSize = 26
        hostingView.rootView = reader()
        for _ in 0..<100 {
            if (try? await webView.evaluateJavaScript("getComputedStyle(document.body).fontSize")) as? String == "26px" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        _ = try await webView.evaluateJavaScript("window.scrollBy({top: 130, behavior: 'instant'});")
        let destinationY = try await number("window.scrollY")
        requestID = UUID()
        hostingView.rootView = reader()
        try await expectBackAvailability(false)
        try await expectTop("document.querySelector('a').getBoundingClientRect().top", sourceTop)
        let returnedY = try await number("window.scrollY")
        #expect(abs(returnedY - destinationY) > 100)

        // Back consumes the saved link; another Back has no effect.
        requestID = UUID()
        hostingView.rootView = reader()
        try await Task.sleep(for: .milliseconds(100))
        try await expectTop("window.scrollY", returnedY)
        try await expectBackAvailability(false)
        // Sidebar navigation after returning must not resurrect the saved link.
        scrollAnchor = "heading-2"
        hostingView.rootView = reader()
        try await expectTop("document.getElementById('heading-2').getBoundingClientRect().top", 24)
        try await expectBackAvailability(false)
        scrollAnchor = nil
        hostingView.rootView = reader()
        // A second successful link replaces the first saved return position.
        _ = try await webView.evaluateJavaScript("document.querySelector('a').click();")
        try await expectBackAvailability(true)
        try await expectTop("document.getElementById('heading-1').getBoundingClientRect().top", 24)
        let nextSourceTop = try await number(
            """
            (() => {
              const link = document.querySelectorAll('a')[1];
              window.scrollTo({top: window.scrollY + link.getBoundingClientRect().top - 140, behavior: 'instant'});
              const top = link.getBoundingClientRect().top;
              link.click();
              return top;
            })()
            """
        )
        try await expectBackAvailability(true)
        try await expectTop("document.getElementById('heading-2').getBoundingClientRect().top", 24)
        window.setContentSize(NSSize(width: 700, height: 500))
        hostingView.layoutSubtreeIfNeeded()
        try await expectTop("window.innerWidth", 700)
        requestID = UUID()
        hostingView.rootView = reader()
        try await expectBackAvailability(false)
        try await expectTop("document.querySelectorAll('a')[1].getBoundingClientRect().top", nextSourceTop)

    }

    @Test @MainActor
    func sidebarRevealsActiveHeadingWithoutMovingDocument() async throws {
        let markdown = (0..<80).map { index in
            "## Section \(index) with a long title that wraps onto two lines in the sidebar\n\n"
                + Array(repeating: "Paragraph of reading content.\n\n", count: 8).joined()
        }.joined()
        let hostingView = NSHostingView(rootView: ContentView(
            document: MarkdownReaderDocument(text: markdown)
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.close() }

        func descendant<ViewType: NSView>(of view: NSView, matching type: ViewType.Type) -> ViewType? {
            if let match = view as? ViewType { return match }
            for subview in view.subviews {
                if let match = descendant(of: subview, matching: type) { return match }
            }
            return nil
        }

        var loadedWebView: WKWebView?
        for _ in 0..<100 {
            if let webView = descendant(of: hostingView, matching: WKWebView.self),
               (try? await webView.evaluateJavaScript("Boolean(window.reader)")) as? Bool == true {
                loadedWebView = webView
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let webView = try #require(loadedWebView)
        let tableView = try #require(descendant(of: hostingView, matching: NSTableView.self))
        #expect(tableView.numberOfRows == 80)

        func revealRect(for row: Int) -> NSRect {
            tableView.rect(ofRow: row).insetBy(dx: 0, dy: -8).intersection(tableView.bounds)
        }

        for headingID in [70, 71, 20, 19, 79, 0] {
            let targetScrollY = try #require(try await webView.evaluateJavaScript(
                """
                (() => {
                  const target = document.getElementById('heading-\(headingID)');
                  window.scrollTo(0, window.scrollY + target.getBoundingClientRect().top - 24);
                  return window.scrollY;
                })()
                """
            ) as? Double)
            for _ in 0..<100 {
                if tableView.selectedRow == headingID,
                   tableView.visibleRect.contains(revealRect(for: headingID)) {
                    break
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(tableView.selectedRow == headingID)
            #expect(tableView.visibleRect.contains(revealRect(for: headingID)))
            let actualScrollY = try #require(
                try await webView.evaluateJavaScript("window.scrollY") as? Double
            )
            #expect(abs(actualScrollY - targetScrollY) < 1)
        }
    }

    @Test @MainActor
    func activeHeadingTracksScrollingNavigationAndLayoutChanges() async throws {
        let paragraphs = Array(repeating: "A paragraph with enough content to scroll.\n\n", count: 20)
            .joined()
        let rendered = MarkdownHTMLRenderer.render(
            "# Title\n\n\(paragraphs)## Section\n\n\(paragraphs)### Last heading\n\nShort ending."
        )
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let waiter = NavigationWaiter()
        configuration.userContentController.add(waiter, name: "activeHeadingChanged")
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 500),
            configuration: configuration
        )
        webView.navigationDelegate = waiter
        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
        defer {
            window.close()
            configuration.userContentController.removeScriptMessageHandler(forName: "activeHeadingChanged")
            webView.stopLoading()
        }

        try await withCheckedThrowingContinuation { continuation in
            waiter.continuation = continuation
            webView.loadHTMLString(
                MarkdownHTMLDocument.make(
                    bodyHTML: rendered.bodyHTML,
                    options: ReaderDisplayOptions(
                        fontSize: 17,
                        lineHeight: 1.6,
                        contentWidthPercentage: 75,
                        theme: .system,
                        syntaxHighlighting: false
                    )
                ),
                baseURL: nil
            )
        }

        func expectActiveHeading(_ anchor: String) async throws {
            for _ in 0..<100 {
                if waiter.activeHeadingAnchors.last == anchor { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(waiter.activeHeadingAnchors.last == anchor)
        }

        try await expectActiveHeading("heading-0")
        _ = try await webView.evaluateJavaScript(
            "window.scrollTo(0, document.getElementById('heading-1').offsetTop - 24);"
        )
        try await expectActiveHeading("heading-1")
        _ = try await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight);")
        try await expectActiveHeading("heading-2")
        _ = try await webView.evaluateJavaScript("window.reader.scrollToHeading('heading-0');")
        try await expectActiveHeading("heading-0")
        _ = try await webView.evaluateJavaScript("window.reader.scrollToHeading('heading-1');")
        try await expectActiveHeading("heading-1")
        try await Task.sleep(for: .milliseconds(500))
        _ = try await webView.evaluateJavaScript(
            "window.reader.applySettings({fontSize: 32, lineHeight: 2, contentWidthPercentage: 75, theme: 'dark', syntaxHighlighting: false});"
        )
        try await expectActiveHeading("heading-0")
        #expect(waiter.activeHeadingAnchors.allSatisfy { anchor in
            rendered.toc.contains { $0.anchor == anchor }
        })
    }

    private struct Diagnostics: Decodable {
        let tableCount: Int
        let codeBlockCount: Int
        let frontMatterCount: Int
        let frontMatterToolbarCount: Int
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

    private struct QuickLookDiagnostics: Decodable {
        let frontMatterCount: Int
        let frontMatterText: String
        let frontMatterWidth: Double
        let markdownWidth: Double
        let bodyFontSize: String
        let headingFontSize: String
        let scriptCount: Int
        let imageCount: Int
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
        ---
        name: web-renderer
        description: Compact metadata panel.
        ---

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
                    frontMatterCount: document.querySelectorAll('pre.frontmatter').length,
                    frontMatterToolbarCount: document.querySelectorAll('pre.frontmatter .code-toolbar').length,
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
        #expect(diagnostics.frontMatterCount == 1)
        #expect(diagnostics.frontMatterToolbarCount == 0)
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

    @Test @MainActor
    func quickLookUsesWebKitLayoutAndKeepsFrontMatterInOnePanel() async throws {
        let rendered = MarkdownHTMLRenderer.render(
            """
            ---
            name: make-gpt-image
            description: Generate one or more raster images from a natural-language prompt.
            ---

            # Make GPT Image

            A readable paragraph with `inline code`.

            ```text
            $make-gpt-image {prompt} [--output PATH]
            ```

            ![remote](https://example.com/image.png)
            """
        )
        let page = MarkdownQuickLookHTMLDocument.make(bodyHTML: rendered.bodyHTML)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1_200, height: 900),
            configuration: configuration
        )
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter

        try await withCheckedThrowingContinuation { continuation in
            waiter.continuation = continuation
            webView.loadHTMLString(page, baseURL: nil)
        }

        let diagnosticsJSON = try #require(
            try await webView.evaluateJavaScript(
                """
                (() => {
                  const markdown = document.querySelector('.markdown-body');
                  const frontMatter = document.querySelector('pre.frontmatter');
                  return JSON.stringify({
                    frontMatterCount: document.querySelectorAll('pre.frontmatter').length,
                    frontMatterText: frontMatter?.textContent || '',
                    frontMatterWidth: frontMatter?.getBoundingClientRect().width || 0,
                    markdownWidth: markdown?.getBoundingClientRect().width || 0,
                    bodyFontSize: getComputedStyle(document.body).fontSize,
                    headingFontSize: getComputedStyle(document.querySelector('h1')).fontSize,
                    scriptCount: document.querySelectorAll('script').length,
                    imageCount: document.querySelectorAll('img').length
                  });
                })()
                """
            ) as? String
        )
        let diagnostics = try JSONDecoder().decode(
            QuickLookDiagnostics.self,
            from: Data(diagnosticsJSON.utf8)
        )

        #expect(!configuration.defaultWebpagePreferences.allowsContentJavaScript)
        #expect(diagnostics.frontMatterCount == 1)
        #expect(diagnostics.frontMatterText.contains("name: make-gpt-image"))
        #expect(diagnostics.frontMatterText.contains("description: Generate one or more"))
        #expect(abs(diagnostics.frontMatterWidth - diagnostics.markdownWidth) < 0.5)
        #expect(diagnostics.bodyFontSize == "17px")
        #expect(diagnostics.headingFontSize == "34px")
        #expect(diagnostics.scriptCount == 0)
        #expect(diagnostics.imageCount == 0)
    }

}
