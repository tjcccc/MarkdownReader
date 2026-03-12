//
//  ContentView.swift
//  MarkdownReader
//
//  Created by taojiachun on 2024-12-02.
//

import SwiftUI
import MarkdownUI

private struct MarkdownSection: Identifiable {
    let id: Int
    let content: String
    let headingTitle: String?
    let headingLevel: Int?
}

private struct TableOfContentsItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let level: Int
}

private struct ParsedMarkdown {
    let sections: [MarkdownSection]
    let tableOfContents: [TableOfContentsItem]
}

private enum MarkdownOutlineParser {
    static func parse(_ markdown: String) -> ParsedMarkdown {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var sections: [MarkdownSection] = []
        var tableOfContents: [TableOfContentsItem] = []
        var currentLines: [String] = []
        var currentHeadingTitle: String?
        var currentHeadingLevel: Int?
        var isInsideFence = false

        func flushSection() {
            guard !currentLines.isEmpty else { return }

            let id = sections.count
            sections.append(
                MarkdownSection(
                    id: id,
                    content: currentLines.joined(separator: "\n"),
                    headingTitle: currentHeadingTitle,
                    headingLevel: currentHeadingLevel
                )
            )

            if let currentHeadingTitle, let currentHeadingLevel {
                tableOfContents.append(
                    TableOfContentsItem(
                        id: id,
                        title: currentHeadingTitle,
                        level: currentHeadingLevel
                    )
                )
            }

            currentLines = []
            currentHeadingTitle = nil
            currentHeadingLevel = nil
        }

        for line in lines {
            if isFenceDelimiter(line) {
                isInsideFence.toggle()
                currentLines.append(line)
                continue
            }

            if !isInsideFence, let heading = parseHeading(line) {
                flushSection()
                currentHeadingTitle = heading.title
                currentHeadingLevel = heading.level
                currentLines.append(line)
                continue
            }

            currentLines.append(line)
        }

        flushSection()

        if sections.isEmpty {
            sections = [
                MarkdownSection(
                    id: 0,
                    content: markdown,
                    headingTitle: nil,
                    headingLevel: nil
                )
            ]
        }

        return ParsedMarkdown(sections: sections, tableOfContents: tableOfContents)
    }

    private static func parseHeading(_ line: String) -> (level: Int, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let hashCount = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashCount) else { return nil }

        let remainder = trimmed.dropFirst(hashCount)
        guard remainder.first?.isWhitespace == true else { return nil }

        let title = remainder
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s#+\s*$"#, with: "", options: .regularExpression)

        return title.isEmpty ? nil : (hashCount, title)
    }

    private static func isFenceDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }
}

struct MarkdownView: View {
    let content: String
    
    var body: some View {
        Markdown(content)
            .markdownTheme(.gitHub)
            .markdownTextStyle(\.text) {
                ForegroundColor(.primary)
            }
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.12))
                    .markdownMargin(top: 0, bottom: 5)
            }
            .markdownBlockStyle(\.heading1) { configuration in
                configuration.label
                    .markdownMargin(top: 5, bottom: 5)
            }
            .markdownBlockStyle(\.heading2) { configuration in
                configuration.label
                    .markdownMargin(top: 5, bottom: 5)
            }
            .markdownBlockStyle(\.heading3) { configuration in
                configuration.label
                    .markdownMargin(top: 4, bottom: 4)
            }
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.92))
            }
            .markdownBlockStyle(\.blockquote) { configuration in
                configuration.label
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color.primary.opacity(0.04))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .markdownBlockStyle(\.codeBlock) { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .relativeLineSpacing(.em(0.18))
                        .padding(14)
                }
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .textSelection(.enabled)
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct TableOfContentsRow: View {
    let item: TableOfContentsItem

    var body: some View {
        Text(item.title)
            .lineLimit(2)
            .padding(.leading, CGFloat(max(item.level - 1, 0) * 12))
    }
}

struct ContentView: View {
    let document: MarkdownReaderDocument
    @State private var selectedSectionID: Int?
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var hasAppliedInitialSidebarVisibility = false

    private var parsedMarkdown: ParsedMarkdown {
        MarkdownOutlineParser.parse(document.text)
    }

    private var preferredInitialSidebarVisibility: NavigationSplitViewVisibility {
        parsedMarkdown.tableOfContents.count >= 4 ? .all : .detailOnly
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if parsedMarkdown.tableOfContents.isEmpty {
                ContentUnavailableView(
                    "No Table of Contents",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add Markdown headings to show an outline here.")
                )
            } else {
                List(parsedMarkdown.tableOfContents, selection: $selectedSectionID) { item in
                    TableOfContentsRow(item: item)
                        .tag(Optional(item.id))
                }
                .listStyle(.sidebar)
                .navigationTitle("Contents")
            }
        } detail: {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(parsedMarkdown.sections) { section in
                            MarkdownView(content: section.content)
                                .id(section.id)
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: selectedSectionID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .top)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 440)
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            guard !hasAppliedInitialSidebarVisibility else { return }
            columnVisibility = preferredInitialSidebarVisibility
            hasAppliedInitialSidebarVisibility = true
        }
    }
}

#Preview {
    ContentView(document: MarkdownReaderDocument())
}
