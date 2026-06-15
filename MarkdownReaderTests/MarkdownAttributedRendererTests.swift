//
//  MarkdownAttributedRendererTests.swift
//  MarkdownReaderTests
//
//  Tests the Markdown -> NSAttributedString converter: heading extraction
//  (titles, levels, ranges) and inline / block styling.
//

import AppKit
import Testing
@testable import MarkdownReader

struct MarkdownAttributedRendererTests {

    @Test func extractsHeadingsWithLevelsAndOrder() {
        let markdown = """
        # Title

        Intro paragraph.

        ## Section A

        Body of A.

        ## Section B

        Body of B.
        """
        let result = MarkdownAttributedRenderer.render(markdown)

        #expect(result.toc.map(\.title) == ["Title", "Section A", "Section B"])
        #expect(result.toc.map(\.level) == [1, 2, 2])
    }

    @Test func headingRangesAreInBoundsAndAscending() {
        let markdown = "# One\n\ntext\n\n## Two\n\nmore\n\n### Three\n"
        let result = MarkdownAttributedRenderer.render(markdown)
        let length = result.text.length

        for item in result.toc {
            #expect(item.range.location >= 0)
            #expect(item.range.location + item.range.length <= length)
        }
        let locations = result.toc.map(\.range.location)
        #expect(locations == locations.sorted())
        #expect(Set(locations).count == locations.count)
    }

    @Test func headingRangeResolvesToHeadingText() {
        let result = MarkdownAttributedRenderer.render("# Alpha\n\nbody\n\n## Beta\n")
        guard let beta = result.toc.first(where: { $0.title == "Beta" }) else {
            Issue.record("Expected a 'Beta' heading")
            return
        }
        let text = result.text.attributedSubstring(from: beta.range).string
        #expect(text.contains("Beta"))
    }

    @Test func appliesBoldItalicAndInlineCode() {
        let result = MarkdownAttributedRenderer.render("This is **bold**, *italic*, and `code`.")
        let full = NSRange(location: 0, length: result.text.length)

        var sawBold = false
        var sawItalic = false
        var sawMonospaced = false
        result.text.enumerateAttribute(.font, in: full) { value, _, _ in
            guard let font = value as? NSFont else { return }
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) { sawBold = true }
            if traits.contains(.italic) { sawItalic = true }
            if traits.contains(.monoSpace) { sawMonospaced = true }
        }

        #expect(sawBold)
        #expect(sawItalic)
        #expect(sawMonospaced)
    }

    @Test func detectsFencedCodeBlock() {
        let markdown = "Before\n\n```\nlet x = 1\n```\n\nAfter"
        let result = MarkdownAttributedRenderer.render(markdown)

        #expect(result.text.string.contains("let x = 1"))

        var sawMonospaced = false
        result.text.enumerateAttribute(.font, in: NSRange(location: 0, length: result.text.length)) { value, _, _ in
            if let font = value as? NSFont, font.fontDescriptor.symbolicTraits.contains(.monoSpace) {
                sawMonospaced = true
            }
        }
        #expect(sawMonospaced)
    }

    @Test func capturesLinkAttribute() {
        let result = MarkdownAttributedRenderer.render("See [Swift](https://swift.org).")

        var linkURL: URL?
        result.text.enumerateAttribute(.link, in: NSRange(location: 0, length: result.text.length)) { value, _, _ in
            if let url = value as? URL { linkURL = url }
        }
        #expect(linkURL?.absoluteString == "https://swift.org")
    }

    @Test func emptyDocumentHasNoHeadings() {
        let result = MarkdownAttributedRenderer.render("")
        #expect(result.toc.isEmpty)
        #expect(result.text.length == 0)
    }

    @Test func detectsImageSyntax() {
        // The image cannot load (relative path, no baseURL), so detection should
        // produce the placeholder rather than leaving the alt text as plain prose.
        let result = MarkdownAttributedRenderer.render("![logo](assets/logo.png)")
        let text = result.text.string
        #expect(text.contains("🖼"))
    }

    @Test func stripsHTMLComments() {
        let markdown = "Before\n\n<!-- hidden note -->\n\nAfter"
        let result = MarkdownAttributedRenderer.render(markdown)
        let text = result.text.string
        #expect(!text.contains("hidden note"))
        #expect(!text.contains("<!--"))
        #expect(text.contains("Before"))
        #expect(text.contains("After"))
    }

    @Test func rendersTableCellsAsTextTable() {
        let markdown = """
        | A | B |
        | - | - |
        | one | two |
        """
        let result = MarkdownAttributedRenderer.render(markdown)
        let text = result.text.string

        // Cell contents are present and pipe delimiters are gone.
        #expect(text.contains("one"))
        #expect(text.contains("two"))
        #expect(!text.contains("|"))

        // Cells carry NSTextTable paragraph styling (i.e. a real grid, not lines).
        var sawTextTable = false
        result.text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: result.text.length)) { value, _, _ in
            if let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty {
                if style.textBlocks.contains(where: { $0 is NSTextTableBlock }) { sawTextTable = true }
            }
        }
        #expect(sawTextTable)
    }
}
