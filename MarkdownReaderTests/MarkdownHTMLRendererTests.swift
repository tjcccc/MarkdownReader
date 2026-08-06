//
//  MarkdownHTMLRendererTests.swift
//  MarkdownReaderTests
//

import AppKit
import Foundation
import Testing
@testable import MarkdownReader

struct MarkdownHTMLRendererTests {
    @Test func extractsHeadingsWithLevelsOrderAndAnchors() {
        let markdown = """
        # Title

        Intro paragraph.

        ## Section A

        ### Section B
        """
        let result = MarkdownHTMLRenderer.render(markdown)

        #expect(result.toc.map(\.title) == ["Title", "Section A", "Section B"])
        #expect(result.toc.map(\.level) == [1, 2, 3])
        #expect(result.toc.map(\.anchor) == ["heading-0", "heading-1", "heading-2"])
    }

    @Test func headingTitlesFlattenInlineFormatting() {
        let result = MarkdownHTMLRenderer.render("# An *important* `API` [guide](https://example.com)")

        #expect(result.toc.first?.title == "An important API guide")
    }

    @Test func rendersCommonInlineMarkup() {
        let result = MarkdownHTMLRenderer.render("This is **bold**, *italic*, and `code`.")

        #expect(result.bodyHTML.contains("<strong>bold</strong>"))
        #expect(result.bodyHTML.contains("<em>italic</em>"))
        #expect(result.bodyHTML.contains("<code>code</code>"))
    }

    @Test func preservesFencedCodeLanguageAndEscapesSource() {
        let result = MarkdownHTMLRenderer.render("```swift\nlet value = a < b\n```")

        #expect(result.bodyHTML.contains("<code class=\"language-swift\">"))
        #expect(result.bodyHTML.contains("let value = a &lt; b"))
    }

    @Test func codeBlockWithoutLanguageRemainsHighlightable() {
        let result = MarkdownHTMLRenderer.render("```\nplain text\n```")

        #expect(result.bodyHTML.contains("<pre><code>plain text"))
        #expect(!result.bodyHTML.contains("class=\"language-"))
    }

    @Test func rendersLinksAndImages() {
        let result = MarkdownHTMLRenderer.render(
            "See [Swift](https://swift.org).\n\n![logo](assets/logo.png)"
        )

        #expect(result.bodyHTML.contains("href=\"https://swift.org\""))
        #expect(result.bodyHTML.contains("src=\"assets/logo.png\""))
        #expect(result.bodyHTML.contains("alt=\"logo\""))
    }

    @Test func rendersGitHubTablesStrikethroughAndTaskLists() {
        let markdown = """
        | A | B |
        | - | - |
        | one | two |

        ~~old~~ new

        - [x] Complete
        - [ ] Pending
        """
        let result = MarkdownHTMLRenderer.render(markdown)

        #expect(result.bodyHTML.contains("<table>"))
        #expect(result.bodyHTML.contains("<th>A</th>"))
        #expect(result.bodyHTML.contains("<td>one</td>"))
        #expect(result.bodyHTML.contains("<del>old</del>"))
        #expect(result.bodyHTML.contains("type=\"checkbox\""))
        #expect(result.bodyHTML.contains("checked=\"\""))
    }

    @Test func rawHTMLAndCommentsCannotInjectPageContent() {
        let markdown = """
        Before

        <!-- hidden note -->

        <script>alert('unsafe')</script>

        After
        """
        let result = MarkdownHTMLRenderer.render(markdown)

        #expect(result.bodyHTML.contains("Before"))
        #expect(result.bodyHTML.contains("After"))
        #expect(!result.bodyHTML.contains("hidden note"))
        #expect(!result.bodyHTML.contains("<script>"))
        #expect(!result.bodyHTML.contains("alert('unsafe')"))
    }

    @Test func emptyDocumentProducesEmptyBodyAndOutline() {
        let result = MarkdownHTMLRenderer.render("")

        #expect(result.bodyHTML.isEmpty)
        #expect(result.toc.isEmpty)
    }
}

struct MarkdownHTMLDocumentTests {
    @Test func pageContainsBodySecurityPolicyAndInitialDisplayOptions() {
        let options = ReaderDisplayOptions(
            fontSize: 20,
            lineHeight: 1.8,
            contentWidthPercentage: 80,
            theme: .dark,
            syntaxHighlighting: false
        )
        let page = MarkdownHTMLDocument.make(
            bodyHTML: "<h1>Rendered</h1>",
            options: options
        )

        #expect(page.contains("<h1>Rendered</h1>"))
        #expect(page.contains("data-theme=\"dark\""))
        #expect(page.contains("default-src 'none'"))
        #expect(page.contains("markdown-reader-resource://app/highlight.min.js"))
        #expect(page.contains("\"fontSize\":20"))
        #expect(page.contains("\"lineHeight\":1.8"))
        #expect(page.contains("\"contentWidthPercentage\":80"))
        #expect(page.contains("\"syntaxHighlighting\":false"))
    }

    @Test func displayOptionsClampPersistedValuesToSupportedRanges() {
        let options = ReaderDisplayOptions(
            fontSize: 200,
            lineHeight: 0,
            contentWidthPercentage: 2_000,
            theme: .system,
            syntaxHighlighting: true
        )

        #expect(options.fontSize == ReaderDisplayOptions.fontSizeRange.upperBound)
        #expect(options.lineHeight == ReaderDisplayOptions.lineHeightRange.lowerBound)
        #expect(
            options.contentWidthPercentage ==
                ReaderDisplayOptions.contentWidthPercentageRange.upperBound
        )
        #expect(ReaderDisplayOptions.normalizedContentWidthPercentage(900) == 75)
        #expect(ReaderDisplayOptions.normalizedContentWidthPercentage(1_000) == 85)
        #expect(
            ReaderDisplayOptions.normalizedContentWidthPercentage(.infinity) ==
                ReaderDisplayOptions.defaultContentWidthPercentage
        )
    }

    @Test @MainActor func windowAppearanceReturnsToSystemAfterDarkMode() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let appearanceView = ReaderWindowAppearanceView(frame: .zero)
        window.contentView = appearanceView

        appearanceView.theme = .dark
        #expect(window.appearance?.name == .darkAqua)

        appearanceView.theme = .light
        #expect(window.appearance?.name == .aqua)

        appearanceView.theme = .system
        #expect(window.appearance == nil)
    }
}

struct MarkdownResourceResolverTests {
    @Test func resolvesFilesInsideDocumentDirectory() throws {
        let root = URL(fileURLWithPath: "/tmp/MarkdownReaderDocument", isDirectory: true)
        let resolver = MarkdownResourceResolver(rootURL: root)
        let request = try #require(
            URL(string: "markdown-reader-resource://document/assets/image.png")
        )

        #expect(
            resolver.resolveDocumentURL(request)?.path
                == "/tmp/MarkdownReaderDocument/assets/image.png"
        )
    }

    @Test func blocksParentDirectoryTraversalAndUnknownHosts() throws {
        let root = URL(fileURLWithPath: "/tmp/MarkdownReaderDocument", isDirectory: true)
        let resolver = MarkdownResourceResolver(rootURL: root)
        let traversal = try #require(
            URL(string: "markdown-reader-resource://document/%2E%2E/secret.txt")
        )
        let wrongHost = try #require(
            URL(string: "markdown-reader-resource://other/assets/image.png")
        )

        #expect(resolver.resolveDocumentURL(traversal) == nil)
        #expect(resolver.resolveDocumentURL(wrongHost) == nil)
    }
}
