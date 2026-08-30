//
//  MarkdownHTMLRenderer.swift
//  MarkdownReaderShared
//
//  Converts Markdown to safe GitHub-flavoured HTML for the app and Quick Look
//  extension, and extracts the heading outline used by the native sidebar.
//

import Darwin
import Foundation
import cmark_gfm
import cmark_gfm_extensions

struct TOCItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let level: Int
    let anchor: String
}

struct RenderedMarkdown: Equatable {
    let bodyHTML: String
    let toc: [TOCItem]
}

enum MarkdownHTMLRenderer {
    private typealias Node = UnsafeMutablePointer<cmark_node>

    private static let extensionNames = [
        "autolink",
        "strikethrough",
        "tagfilter",
        "tasklist",
        "table",
    ]

    static func render(_ markdown: String) -> RenderedMarkdown {
        cmark_gfm_core_extensions_ensure_registered()

        let source = MarkdownFrontMatter.extract(from: markdown)

        let options = CMARK_OPT_VALIDATE_UTF8
            | CMARK_OPT_FOOTNOTES
            | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE

        guard let parser = cmark_parser_new(options) else {
            return fallback(for: markdown)
        }
        defer { cmark_parser_free(parser) }

        for name in extensionNames {
            guard let syntaxExtension = cmark_find_syntax_extension(name) else { continue }
            cmark_parser_attach_syntax_extension(parser, syntaxExtension)
        }

        source.markdown.withCString { markdownSource in
            cmark_parser_feed(parser, markdownSource, source.markdown.utf8.count)
        }

        guard let document = cmark_parser_finish(parser) else {
            return fallback(for: markdown)
        }
        defer { cmark_node_free(document) }

        let toc = tableOfContents(in: document)
        guard let rendered = cmark_render_html(
            document,
            options,
            cmark_parser_get_syntax_extensions(parser)
        ) else {
            return fallback(for: markdown)
        }
        defer { free(rendered) }

        return RenderedMarkdown(
            bodyHTML: frontMatterHTML(source.yaml) + String(cString: rendered),
            toc: toc
        )
    }

    private static func tableOfContents(in document: Node) -> [TOCItem] {
        var items: [TOCItem] = []

        func visitChildren(of parent: Node) {
            var child = cmark_node_first_child(parent)
            while let node = child {
                if cmark_node_get_type(node) == CMARK_NODE_HEADING {
                    let title = plainText(in: node)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty {
                        let id = items.count
                        items.append(
                            TOCItem(
                                id: id,
                                title: title,
                                level: Int(cmark_node_get_heading_level(node)),
                                anchor: "heading-\(id)"
                            )
                        )
                    }
                }

                visitChildren(of: node)
                child = cmark_node_next(node)
            }
        }

        visitChildren(of: document)
        return items
    }

    private static func plainText(in node: Node) -> String {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_TEXT, CMARK_NODE_CODE:
            return cmark_node_get_literal(node).map(String.init(cString:)) ?? ""
        case CMARK_NODE_SOFTBREAK, CMARK_NODE_LINEBREAK:
            return " "
        default:
            var result = ""
            var child = cmark_node_first_child(node)
            while let current = child {
                result += plainText(in: current)
                child = cmark_node_next(current)
            }
            return result
        }
    }

    private static func fallback(for markdown: String) -> RenderedMarkdown {
        let source = MarkdownFrontMatter.extract(from: markdown)
        return RenderedMarkdown(
            bodyHTML: frontMatterHTML(source.yaml)
                + "<pre><code>\(escapeHTML(source.markdown))</code></pre>",
            toc: []
        )
    }

    private static func frontMatterHTML(_ yaml: String?) -> String {
        guard let yaml else { return "" }
        return "<pre class=\"frontmatter\"><code class=\"language-yaml\">"
            + escapeHTML(yaml)
            + "</code></pre>\n"
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
