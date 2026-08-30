//
//  MarkdownQuickLookHTMLDocument.swift
//  MarkdownReaderShared
//
//  Builds the self-contained, script-free page hosted by Quick Look.
//

import Foundation

enum MarkdownQuickLookHTMLDocument {
    static func make(bodyHTML: String) -> String {
        let safeBodyHTML = replacingImages(in: bodyHTML)

        return #"""
        <!doctype html>
        <html data-theme="system">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'none'; style-src 'unsafe-inline'">
          <style>
            :root,
            html[data-theme="system"] {
              color-scheme: light;
              --canvas: #ffffff;
              --foreground: #1f2328;
              --muted: #59636e;
              --border: #d1d9e0;
              --border-muted: #d8dee4;
              --subtle: #f6f8fa;
              --accent: #0969da;
              --selection: #b6d7ff;
              --quote-border: #d1d9e0;
              --code-bg: #f6f8fa;
            }

            @media (prefers-color-scheme: dark) {
              html[data-theme="system"] {
                color-scheme: dark;
                --canvas: #0d1117;
                --foreground: #e6edf3;
                --muted: #9198a1;
                --border: #3d444d;
                --border-muted: #30363d;
                --subtle: #151b23;
                --accent: #4493f8;
                --selection: #264f78;
                --quote-border: #3d444d;
                --code-bg: #151b23;
              }
            }

            * {
              box-sizing: border-box;
            }

            html {
              min-height: 100%;
              padding: 0 48px;
              background: var(--canvas);
            }

            body {
              min-height: 100vh;
              width: 75%;
              margin: 0 auto;
              padding: 36px 0 72px;
              color: var(--foreground);
              background: var(--canvas);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              font-size: 17px;
              line-height: 1.6;
              overflow-wrap: break-word;
            }

            ::selection {
              background: var(--selection);
            }

            .markdown-body {
              width: 100%;
            }

            .markdown-body > :first-child {
              margin-top: 0 !important;
            }

            .markdown-body > :last-child {
              margin-bottom: 0 !important;
            }

            a {
              color: var(--accent);
              text-decoration: none;
            }

            a:hover {
              text-decoration: underline;
            }

            p,
            blockquote,
            ul,
            ol,
            dl,
            table,
            pre,
            details {
              margin-top: 0;
              margin-bottom: 1em;
            }

            h1,
            h2,
            h3,
            h4,
            h5,
            h6 {
              margin-top: 1.5em;
              margin-bottom: 0.65em;
              font-weight: 600;
              line-height: 1.25;
            }

            h1 {
              padding-bottom: 0.3em;
              border-bottom: 1px solid var(--border-muted);
              font-size: 2em;
            }

            h2 {
              padding-bottom: 0.3em;
              border-bottom: 1px solid var(--border-muted);
              font-size: 1.5em;
            }

            h3 { font-size: 1.25em; }
            h4 { font-size: 1em; }
            h5 { font-size: 0.875em; }
            h6 { color: var(--muted); font-size: 0.85em; }

            strong {
              font-weight: 600;
            }

            hr {
              height: 0.25em;
              margin: 1.5em 0;
              padding: 0;
              border: 0;
              background: var(--border-muted);
            }

            blockquote {
              padding: 0 1em;
              color: var(--muted);
              border-left: 0.25em solid var(--quote-border);
            }

            blockquote > :first-child { margin-top: 0; }
            blockquote > :last-child { margin-bottom: 0; }

            ul,
            ol {
              padding-left: 2em;
            }

            li + li {
              margin-top: 0.25em;
            }

            li > p {
              margin-top: 1em;
            }

            .task-list-item {
              list-style: none;
            }

            .task-list-item input {
              margin: 0 0.45em 0.25em -1.55em;
              vertical-align: middle;
              pointer-events: none;
            }

            table {
              display: block;
              width: max-content;
              max-width: 100%;
              overflow: auto;
              border-spacing: 0;
              border-collapse: collapse;
              font-variant-numeric: tabular-nums;
            }

            tr {
              border-top: 1px solid var(--border-muted);
              background: var(--canvas);
            }

            tr:nth-child(2n) {
              background: var(--subtle);
            }

            th,
            td {
              padding: 6px 13px;
              border: 1px solid var(--border);
              text-align: left;
            }

            th {
              font-weight: 600;
            }

            code,
            kbd,
            pre,
            samp {
              font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, monospace;
            }

            :not(pre) > code {
              margin: 0;
              padding: 0.2em 0.4em;
              border-radius: 6px;
              background: var(--code-bg);
              font-size: 0.85em;
              white-space: break-spaces;
            }

            pre:not(.frontmatter) {
              padding: 16px;
              overflow: auto;
              border-radius: 8px;
              background: var(--code-bg);
              font-size: 0.85em;
              line-height: 1.55;
              tab-size: 4;
            }

            pre:not(.frontmatter) code {
              display: block;
              min-width: max-content;
              padding: 0;
              color: inherit;
              background: transparent;
              white-space: pre;
            }

            pre.frontmatter {
              margin: 0 0 1.4em;
              padding: 14px 16px;
              overflow: auto;
              border: 1px solid var(--border);
              border-radius: 8px;
              background: var(--code-bg);
              font-size: 0.82em;
              line-height: 1.5;
              tab-size: 2;
            }

            pre.frontmatter code {
              display: block;
              min-width: max-content;
              padding: 0;
              color: inherit;
              background: transparent;
              white-space: pre;
            }

            .image-placeholder {
              color: var(--muted);
              font-style: italic;
            }

            sub,
            sup {
              position: relative;
              vertical-align: baseline;
              font-size: 0.75em;
              line-height: 0;
            }

            sup { top: -0.5em; }
            sub { bottom: -0.25em; }

            @media (max-width: 700px) {
              html {
                padding: 0 24px;
              }

              body {
                width: 100%;
                padding: 28px 0 56px;
              }
            }
          </style>
        </head>
        <body>
          <main class="markdown-body">
        \#(safeBodyHTML)
          </main>
        </body>
        </html>
        """#
    }

    private static func replacingImages(in bodyHTML: String) -> String {
        let fullRange = NSRange(bodyHTML.startIndex..., in: bodyHTML)
        let withAltText = imageWithAltTextPattern.stringByReplacingMatches(
            in: bodyHTML,
            range: fullRange,
            withTemplate: #"<span class="image-placeholder">&#x1F5BC; $1</span>"#
        )
        return imagePattern.stringByReplacingMatches(
            in: withAltText,
            range: NSRange(withAltText.startIndex..., in: withAltText),
            withTemplate: #"<span class="image-placeholder">&#x1F5BC; Image</span>"#
        )
    }

    private static let imageWithAltTextPattern = try! NSRegularExpression(
        pattern: #"<img\b(?=[^>]*\balt="([^"]*)")[^>]*>"#,
        options: .caseInsensitive
    )
    private static let imagePattern = try! NSRegularExpression(
        pattern: #"<img\b[^>]*>"#,
        options: .caseInsensitive
    )
}
