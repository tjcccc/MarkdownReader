//
//  MarkdownHTMLDocument.swift
//  MarkdownReader
//
//  Builds the self-contained page hosted by MarkdownWebView. The Markdown body
//  comes from cmark-gfm; all presentation and document interactions live here.
//

import Foundation

enum MarkdownHTMLDocument {
    static func make(bodyHTML: String, options: ReaderDisplayOptions) -> String {
        let settings = settingsJSON(options)

        return #"""
        <!doctype html>
        <html data-theme="\#(options.theme.rawValue)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src markdown-reader-resource: data:; style-src 'unsafe-inline'; script-src markdown-reader-resource: 'unsafe-inline'">
          <base href="markdown-reader-resource://document/">
          <style>
            :root,
            html[data-theme="system"],
            html[data-theme="light"] {
              color-scheme: light;
              --canvas: #ffffff;
              --foreground: #1f2328;
              --muted: #59636e;
              --border: #d1d9e0;
              --border-muted: #d8dee4;
              --subtle: #f6f8fa;
              --subtle-alt: #f3f4f6;
              --accent: #0969da;
              --selection: #b6d7ff;
              --quote-border: #d1d9e0;
              --code-bg: #f6f8fa;
              --syntax-comment: #6e7781;
              --syntax-keyword: #cf222e;
              --syntax-title: #8250df;
              --syntax-attribute: #0550ae;
              --syntax-string: #0a3069;
              --syntax-variable: #953800;
              --syntax-literal: #0550ae;
              --syntax-meta: #116329;
              --syntax-addition: #1a7f37;
              --syntax-addition-bg: #dafbe1;
              --syntax-deletion: #cf222e;
              --syntax-deletion-bg: #ffebe9;
            }

            html[data-theme="dark"] {
              color-scheme: dark;
              --canvas: #0d1117;
              --foreground: #e6edf3;
              --muted: #9198a1;
              --border: #3d444d;
              --border-muted: #30363d;
              --subtle: #151b23;
              --subtle-alt: #161b22;
              --accent: #4493f8;
              --selection: #264f78;
              --quote-border: #3d444d;
              --code-bg: #151b23;
              --syntax-comment: #8b949e;
              --syntax-keyword: #ff7b72;
              --syntax-title: #d2a8ff;
              --syntax-attribute: #79c0ff;
              --syntax-string: #a5d6ff;
              --syntax-variable: #ffa657;
              --syntax-literal: #79c0ff;
              --syntax-meta: #7ee787;
              --syntax-addition: #aff5b4;
              --syntax-addition-bg: #033a16;
              --syntax-deletion: #ffdcd7;
              --syntax-deletion-bg: #67060c;
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
                --subtle-alt: #161b22;
                --accent: #4493f8;
                --selection: #264f78;
                --quote-border: #3d444d;
                --code-bg: #151b23;
                --syntax-comment: #8b949e;
                --syntax-keyword: #ff7b72;
                --syntax-title: #d2a8ff;
                --syntax-attribute: #79c0ff;
                --syntax-string: #a5d6ff;
                --syntax-variable: #ffa657;
                --syntax-literal: #79c0ff;
                --syntax-meta: #7ee787;
                --syntax-addition: #aff5b4;
                --syntax-addition-bg: #033a16;
                --syntax-deletion: #ffdcd7;
                --syntax-deletion-bg: #67060c;
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
              width: var(--reader-content-width-percentage, 75%);
              margin: 0 auto;
              padding: 36px 0 72px;
              color: var(--foreground);
              background: var(--canvas);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
              font-size: var(--reader-font-size, 17px);
              line-height: var(--reader-line-height, 1.6);
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
              scroll-margin-top: 24px;
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

            .code-block {
              position: relative;
              margin-bottom: 1em;
              border-radius: 8px;
              background: var(--code-bg);
            }

            .code-block pre {
              margin: 0;
              padding: 40px 16px 16px;
              overflow: auto;
              border-radius: inherit;
              background: transparent;
              font-size: 0.85em;
              line-height: 1.55;
              tab-size: 4;
            }

            .code-block pre code {
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

            .code-toolbar {
              position: absolute;
              z-index: 1;
              top: 8px;
              right: 10px;
              left: 14px;
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 12px;
              min-height: 24px;
              color: var(--muted);
              font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, monospace;
              font-size: 11px;
              line-height: 1;
              user-select: none;
            }

            .code-language:empty {
              display: block;
            }

            .copy-code {
              appearance: none;
              margin-left: auto;
              padding: 4px 7px;
              border: 1px solid transparent;
              border-radius: 6px;
              color: var(--muted);
              background: transparent;
              font: inherit;
              cursor: pointer;
            }

            .copy-code:hover {
              border-color: var(--border);
              color: var(--foreground);
              background: var(--subtle-alt);
            }

            .copy-code:focus-visible {
              outline: 2px solid var(--accent);
              outline-offset: 1px;
            }

            .hljs-comment,
            .hljs-quote { color: var(--syntax-comment); }
            .hljs-doctag,
            .hljs-keyword,
            .hljs-formula { color: var(--syntax-keyword); }
            .hljs-section,
            .hljs-name,
            .hljs-selector-tag,
            .hljs-deletion,
            .hljs-subst { color: var(--syntax-deletion); }
            .hljs-literal { color: var(--syntax-literal); }
            .hljs-string,
            .hljs-regexp,
            .hljs-addition,
            .hljs-attribute,
            .hljs-meta .hljs-string { color: var(--syntax-string); }
            .hljs-attr,
            .hljs-variable,
            .hljs-template-variable,
            .hljs-selector-class,
            .hljs-selector-attr,
            .hljs-selector-pseudo,
            .hljs-number { color: var(--syntax-attribute); }
            .hljs-symbol,
            .hljs-bullet,
            .hljs-link,
            .hljs-selector-id,
            .hljs-title { color: var(--syntax-title); }
            .hljs-meta { color: var(--syntax-meta); }
            .hljs-built_in,
            .hljs-title.class_,
            .hljs-class .hljs-title { color: var(--syntax-variable); }
            .hljs-emphasis { font-style: italic; }
            .hljs-strong { font-weight: 600; }
            .hljs-addition {
              color: var(--syntax-addition);
              background: var(--syntax-addition-bg);
            }
            .hljs-deletion {
              color: var(--syntax-deletion);
              background: var(--syntax-deletion-bg);
            }

            img {
              max-width: 100%;
              height: auto;
              border-radius: 6px;
              cursor: zoom-in;
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
          <script src="markdown-reader-resource://app/highlight.min.js"></script>
        </head>
        <body>
          <main class="markdown-body">
        \#(bodyHTML)
          </main>
          <script>
            (() => {
              let highlightingEnabled = null;
              let headings = Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, h6'));
              const headingsByTitleAnchor = new Map();
              let headingActivationOffset = 24;
              let scrollingElement = document.scrollingElement;
              let viewport = document.documentElement;
              let activeHeadingObserver = new ResizeObserver(scheduleActiveHeadingUpdate);
              let activeHeadingAnchor = null;
              let headingUpdatePending = false;

              function updateActiveHeading() {
                if (!headings.length) return;
                let activeHeading = headings[0];
                for (const heading of headings) {
                  if (heading.getBoundingClientRect().top > headingActivationOffset + 1) break;
                  activeHeading = heading;
                }
                if (scrollingElement.scrollHeight > viewport.clientHeight &&
                    window.scrollY + viewport.clientHeight >= scrollingElement.scrollHeight - 1) {
                  activeHeading = headings[headings.length - 1];
                }
                if (activeHeadingAnchor === activeHeading.id) return;
                activeHeadingAnchor = activeHeading.id;
                window.webkit?.messageHandlers?.activeHeadingChanged?.postMessage(activeHeading.id);
              }

              function scheduleActiveHeadingUpdate() {
                if (headingUpdatePending) return;
                headingUpdatePending = true;
                window.requestAnimationFrame(() => {
                  headingUpdatePending = false;
                  updateActiveHeading();
                });
              }

              function languageFor(code) {
                const languageClass = Array.from(code.classList)
                  .find(name => name.startsWith('language-'));
                return languageClass ? languageClass.slice('language-'.length) : '';
              }

              function decorateHeadings() {
                headings.forEach((heading, index) => {
                  heading.id = `heading-${index}`;
                  const base = (heading.textContent || '').trim().toLowerCase()
                    .replace(/[^\p{L}\p{M}\p{N}_\-\s]/gu, '')
                    .replace(/\s/g, '-');
                  let anchor = base;
                  let suffix = 0;
                  while (headingsByTitleAnchor.has(anchor)) {
                    anchor = `${base}-${++suffix}`;
                  }
                  headingsByTitleAnchor.set(anchor, heading);
                });
              }

              function decorateCodeBlocks() {
                document.querySelectorAll('pre > code').forEach(code => {
                  const pre = code.parentElement;
                  if (!pre || pre.parentElement?.classList.contains('code-block')) return;

                  code.dataset.rawCode = code.textContent || '';
                  if (pre.classList.contains('frontmatter')) return;

                  const wrapper = document.createElement('div');
                  wrapper.className = 'code-block';
                  pre.replaceWith(wrapper);
                  wrapper.appendChild(pre);

                  const toolbar = document.createElement('div');
                  toolbar.className = 'code-toolbar';
                  toolbar.setAttribute('aria-hidden', 'false');

                  const language = document.createElement('span');
                  language.className = 'code-language';
                  language.textContent = languageFor(code);

                  const copy = document.createElement('button');
                  copy.className = 'copy-code';
                  copy.type = 'button';
                  copy.textContent = 'Copy';
                  copy.setAttribute('aria-label', 'Copy code');
                  copy.addEventListener('click', event => {
                    event.preventDefault();
                    event.stopPropagation();
                    window.webkit?.messageHandlers?.copyCode?.postMessage(
                      code.dataset.rawCode || ''
                    );
                    copy.textContent = 'Copied';
                    window.setTimeout(() => { copy.textContent = 'Copy'; }, 1500);
                  });

                  toolbar.append(language, copy);
                  wrapper.appendChild(toolbar);
                });
              }

              function decorateImages() {
                document.querySelectorAll('img').forEach(image => {
                  image.addEventListener('click', event => {
                    event.preventDefault();
                    window.webkit?.messageHandlers?.imageClicked?.postMessage(image.src);
                  });
                });
              }

              function decorateInternalLinks() {
                document.querySelectorAll('a[href^="#"]').forEach(link => {
                  link.addEventListener('click', event => {
                    event.preventDefault();
                    let anchor = link.getAttribute('href')?.slice(1);
                    try {
                      anchor = decodeURIComponent(anchor || '');
                    } catch {
                      return;
                    }
                    const target = headingsByTitleAnchor.get(anchor) || document.getElementById(anchor);
                    if (!target) return;
                    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
                  });
                });
              }

              function applyHighlighting(enabled) {
                if (highlightingEnabled === enabled) return;

                document.querySelectorAll('pre > code').forEach(code => {
                  code.textContent = code.dataset.rawCode || '';
                  code.removeAttribute('data-highlighted');
                  code.classList.remove('hljs');

                  if (!enabled || !window.hljs) return;
                  const language = languageFor(code);
                  if (language && !window.hljs.getLanguage(language)) return;

                  try {
                    window.hljs.highlightElement(code);
                  } catch (_) {
                    code.textContent = code.dataset.rawCode || '';
                  }
                });

                highlightingEnabled = enabled;
              }

              function applySettings(settings) {
                document.documentElement.dataset.theme = settings.theme;
                document.documentElement.style.setProperty(
                  '--reader-font-size', `${settings.fontSize}px`
                );
                document.documentElement.style.setProperty(
                  '--reader-line-height', String(settings.lineHeight)
                );
                const contentWidthPercentage = Number(settings.contentWidthPercentage);
                if (Number.isFinite(contentWidthPercentage)) {
                  document.documentElement.style.setProperty(
                    '--reader-content-width-percentage', `${contentWidthPercentage}%`
                  );
                }
                applyHighlighting(Boolean(settings.syntaxHighlighting));
                scheduleActiveHeadingUpdate();
              }

              function scrollToHeading(anchor) {
                document.getElementById(anchor)?.scrollIntoView({
                  behavior: 'smooth',
                  block: 'start'
                });
              }

              decorateHeadings();
              decorateCodeBlocks();
              decorateImages();
              decorateInternalLinks();
              window.addEventListener('scroll', scheduleActiveHeadingUpdate, { passive: true });
              window.addEventListener('resize', scheduleActiveHeadingUpdate);
              activeHeadingObserver.observe(document.querySelector('.markdown-body'));
              window.reader = { applySettings, scrollToHeading };
              applySettings(\#(settings));
            })();
          </script>
        </body>
        </html>
        """#
    }

    static func settingsJSON(_ options: ReaderDisplayOptions) -> String {
        let object: [String: Any] = [
            "fontSize": options.fontSize,
            "lineHeight": options.lineHeight,
            "contentWidthPercentage": options.contentWidthPercentage,
            "theme": options.theme.rawValue,
            "syntaxHighlighting": options.syntaxHighlighting,
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        ) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
