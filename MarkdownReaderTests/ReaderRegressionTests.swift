//
//  ReaderRegressionTests.swift
//  MarkdownReaderTests
//
//  Regressions for heading anchors, linked files, search, the image lightbox,
//  and reloading after external file changes.
//

import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit
@testable import MarkdownReader

@MainActor
private final class PageLoadWaiter: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var continuation: CheckedContinuation<Void, Never>?
    var activeHeadingAnchors: [String] = []

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let anchor = message.body as? String { activeHeadingAnchors.append(anchor) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class CancelSpyView: NSView {
    var cancelCount = 0
    override func cancelOperation(_ sender: Any?) { cancelCount += 1 }
}

@MainActor
private struct LoadedPage {
    let webView: WKWebView
    let container: MarkdownReaderWebContainer
    let window: NSWindow
    let waiter: PageLoadWaiter

    func close() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "activeHeadingChanged")
        webView.stopLoading()
        window.close()
    }

    func evaluate<T>(_ script: String, as type: T.Type = T.self) async throws -> T {
        try #require(try await webView.evaluateJavaScript(script) as? T)
    }

    func waitUntil(_ condition: () async throws -> Bool) async throws -> Bool {
        for _ in 0..<150 {
            if try await condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// Counts find-highlight yellow pixels in a snapshot of the page.
    func highlightedPixelCount() async throws -> Int {
        let image = try await webView.takeSnapshot(configuration: nil)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        var count = 0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.8, color.greenComponent > 0.8, color.blueComponent < 0.4 { count += 1 }
            }
        }
        return count
    }

    static func load(_ markdown: String, height: CGFloat = 500) async throws -> LoadedPage {
        let rendered = MarkdownHTMLRenderer.render(markdown)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(
            MarkdownResourceSchemeHandler(documentRootURL: nil),
            forURLScheme: MarkdownResourceResolver.scheme
        )
        let waiter = PageLoadWaiter()
        configuration.userContentController.add(waiter, name: "activeHeadingChanged")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = waiter
        let container = MarkdownReaderWebContainer(webView: webView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: height),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            webView.loadHTMLString(
                MarkdownHTMLDocument.make(bodyHTML: rendered.bodyHTML, options: ReaderDisplayOptions(
                    fontSize: 17, lineHeight: 1.6, contentWidthPercentage: 75,
                    theme: .light, syntaxHighlighting: false
                )),
                baseURL: URL(string: "\(MarkdownResourceResolver.scheme)://document/")
            )
        }
        return LoadedPage(webView: webView, container: container, window: window, waiter: waiter)
    }
}

@Suite(.serialized)
struct ReaderRegressionTests {
    // MARK: Heading anchors

    @Test func untitledHeadingsKeepLaterAnchorsAlignedWithTheDOM() {
        let result = MarkdownHTMLRenderer.render("# ![](banner.png)\n\n## A\n\n#\n\n## B")
        #expect(result.toc.map(\.title) == ["A", "B"])
        #expect(result.toc.map(\.id) == [0, 1])
        #expect(result.toc.map(\.anchor) == ["heading-1", "heading-3"])
    }

    @Test @MainActor
    func outlineAnchorsPointAtTheirHeadingsInThePage() async throws {
        let markdown = "# ![](banner.png)\n\n## Alpha\n\n#\n\n## Beta *formatted*"
        let page = try await LoadedPage.load(markdown)
        defer { page.close() }
        for item in MarkdownHTMLRenderer.render(markdown).toc {
            let text: String = try await page.evaluate(
                "document.getElementById('\(item.anchor)').textContent.trim()"
            )
            #expect(text == item.title)
        }
    }

    @Test @MainActor
    func noHeadingIsActiveUntilTheFirstHeadingIsVisible() async throws {
        let filler = Array(repeating: "Introductory text above every heading.\n\n", count: 40).joined()
        let page = try await LoadedPage.load("\(filler)# First\n\n\(filler)")
        defer { page.close() }
        #expect(try await page.waitUntil { page.waiter.activeHeadingAnchors.last == "" })
        _ = try await page.webView.evaluateJavaScript(
            "window.scrollTo(0, document.getElementById('heading-0').offsetTop - 24);"
        )
        #expect(try await page.waitUntil { page.waiter.activeHeadingAnchors.last == "heading-0" })
        _ = try await page.webView.evaluateJavaScript("window.scrollTo(0, 0);")
        #expect(try await page.waitUntil { page.waiter.activeHeadingAnchors.last == "" })
    }

    // MARK: Linked files

    @Test func resourcePathsArePercentDecodedOnce() throws {
        let root = URL(fileURLWithPath: "/tmp/MarkdownReaderDocument", isDirectory: true)
        let resolver = MarkdownResourceResolver(rootURL: root)
        let percent = try #require(URL(string: "markdown-reader-resource://document/100%25.png"))
        let literalEscape = try #require(URL(string: "markdown-reader-resource://document/a%2520b.png"))
        #expect(resolver.resolveDocumentURL(percent)?.lastPathComponent == "100%.png")
        #expect(resolver.resolveDocumentURL(literalEscape)?.lastPathComponent == "a%20b.png")
    }

    @Test func linkedFilesOnlyOpenDirectlyWhenTheyCannotRunCode() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownReaderLinks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func file(_ name: String) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            return url
        }
        func directory(_ name: String) throws -> URL {
            let url = folder.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        for name in ["notes.md", "image.png", "manual.pdf", "readme.txt", "clip.mov"] {
            #expect(MarkdownResourceResolver.opensLinkedFileDirectly(try file(name)), "\(name)")
        }
        for name in ["setup.command", "build.sh", "tool.py", "script.applescript", "page.html", "archive.zip"] {
            #expect(!MarkdownResourceResolver.opensLinkedFileDirectly(try file(name)), "\(name)")
        }
        for name in ["Payload.app", "assets"] {
            #expect(!MarkdownResourceResolver.opensLinkedFileDirectly(try directory(name)), "\(name)")
        }
        #expect(!MarkdownResourceResolver.opensLinkedFileDirectly(folder.appendingPathComponent("missing.png")))
    }

    // MARK: Search

    @Test @MainActor
    func searchIgnoresCodeToolbarLabels() async throws {
        let page = try await LoadedPage.load("Text before.\n\n```shell\necho done\n```\n")
        defer { page.close() }
        let copyCount: Int = try await page.evaluate("window.reader.searchPosition('copy').total")
        let languageCount: Int = try await page.evaluate("window.reader.searchPosition('shell').total")
        let codeCount: Int = try await page.evaluate("window.reader.searchPosition('echo').total")
        #expect(copyCount == 0)
        #expect(languageCount == 0)
        #expect(codeCount == 1)
        let copyFound = try await page.webView.find("Copy", configuration: WKFindConfiguration()).matchFound
        #expect(!copyFound)
        let labels: String = try await page.evaluate("""
            [getComputedStyle(document.querySelector('.code-language'), '::before').content,
             getComputedStyle(document.querySelector('.copy-code'), '::before').content].join('|')
            """)
        #expect(labels == "\"shell\"|\"Copy\"")
    }

    @Test @MainActor
    func closingFindRemovesTheMatchHighlight() async throws {
        let page = try await LoadedPage.load("# Title\n\nFind the Needle here.")
        defer { page.close() }
        page.container.performFindAction(.showFindInterface)
        let field = page.container.searchField
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.string = "Needle"
        editor.didChangeText()
        field.validateEditing()
        page.container.performFindAction(.nextMatch)
        #expect(try await page.waitUntil { try await page.highlightedPixelCount() > 0 })
        page.container.performFindAction(.hideFindInterface)
        #expect(try await page.waitUntil { try await page.highlightedPixelCount() == 0 })
    }

    @Test @MainActor
    func escapeWithFindClosedReachesTheNextResponder() async throws {
        let page = try await LoadedPage.load("# Title")
        defer { page.close() }
        let spy = CancelSpyView(frame: page.container.frame)
        page.window.contentView = spy
        spy.addSubview(page.container)
        page.container.cancelOperation(nil)
        #expect(spy.cancelCount == 1)
        page.container.performFindAction(.showFindInterface)
        page.container.cancelOperation(nil)
        #expect(spy.cancelCount == 1)
        #expect(!page.container.isFindBarVisible)
    }

    // MARK: Lightbox

    @Test @MainActor
    func lightboxCoversTheWholeWindowAndClosesWithEscape() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let anchor = ImageLightboxAnchorView()
        window.contentView = anchor
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        var dismissCount = 0
        anchor.onDismiss = { dismissCount += 1 }
        anchor.image = NSImage(size: NSSize(width: 40, height: 30))

        let lightbox = try #require(anchor.lightboxWindow)
        #expect(window.childWindows?.contains(lightbox) == true)
        #expect(lightbox.frame == window.frame)

        window.setFrame(NSRect(x: 120, y: 80, width: 800, height: 560), display: false)
        #expect(lightbox.frame == window.frame)

        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: lightbox.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
        lightbox.sendEvent(escape)
        #expect(dismissCount == 1)
        anchor.image = nil
        #expect(anchor.lightboxWindow == nil)
        #expect(window.childWindows?.contains(lightbox) != true)
        #expect(!lightbox.isVisible)
    }

    // MARK: External file changes

    @Test @MainActor
    func fileMonitorReportsInPlaceAndAtomicSaves() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownReaderMonitor-\(UUID().uuidString).md")
        try "# One".write(to: url, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        var texts: [String] = []
        let monitor = DocumentFileMonitor(url: url, currentText: "# One") { texts.append($0) }
        monitor.start()
        defer { monitor.stop() }

        func waitFor(_ text: String) async throws -> Bool {
            for _ in 0..<150 {
                if texts.last == text { return true }
                try await Task.sleep(for: .milliseconds(20))
            }
            return false
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("# Two".utf8))
        try handle.close()
        #expect(try await waitFor("# Two"))
        try "# Three".write(to: url, atomically: true, encoding: .utf8)
        #expect(try await waitFor("# Three"))
        try "# Four".write(to: url, atomically: true, encoding: .utf8)
        #expect(try await waitFor("# Four"))
        #expect(texts == ["# Two", "# Three", "# Four"])
    }

    @Test @MainActor
    func reloadedDocumentKeepsItsScrollPosition() async throws {
        let paragraphs = Array(repeating: "Paragraph text for scrolling.\n\n", count: 80).joined()
        var rendered = MarkdownHTMLRenderer.render("# Start\n\n\(paragraphs)")
        func reader() -> MarkdownWebView {
            MarkdownWebView(
                rendered: rendered,
                documentRootURL: nil,
                displayOptions: ReaderDisplayOptions(
                    fontSize: 17, lineHeight: 1.6, contentWidthPercentage: 75,
                    theme: .system, syntaxHighlighting: false
                )
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
        func webView(in view: NSView) -> WKWebView? {
            if let webView = view as? WKWebView { return webView }
            return view.subviews.lazy.compactMap { webView(in: $0) }.first
        }
        func pageIsReady(_ webView: WKWebView, marker: String) async -> Bool {
            let script = "Boolean(window.reader) && document.body.textContent.includes('\(marker)')"
            return (try? await webView.evaluateJavaScript(script)) as? Bool == true
        }
        var loaded: WKWebView?
        for _ in 0..<150 {
            if let candidate = webView(in: hostingView), await pageIsReady(candidate, marker: "Start") {
                loaded = candidate
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let page = try #require(loaded)
        _ = try await page.evaluateJavaScript("window.scrollTo(0, 1200);")

        rendered = MarkdownHTMLRenderer.render("# Start (edited)\n\n\(paragraphs)")
        hostingView.rootView = reader()
        var scrollY = 0.0
        for _ in 0..<150 {
            if await pageIsReady(page, marker: "edited") {
                scrollY = (try? await page.evaluateJavaScript("window.scrollY")) as? Double ?? 0
                if abs(scrollY - 1200) < 1 { break }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(abs(scrollY - 1200) < 1, "scrollY \(scrollY)")
    }
}
