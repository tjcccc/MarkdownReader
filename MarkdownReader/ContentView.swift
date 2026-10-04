//
//  ContentView.swift
//  MarkdownReader
//
//  Created by taojiachun on 2024-12-02.
//

import SwiftUI

private struct TableOfContentsRow: View {
    let item: TOCItem

    var body: some View {
        Text(item.title)
            .fontWeight(item.level <= 2 ? .bold : .regular)
            .lineLimit(2)
            .padding(.leading, CGFloat(max(item.level - 1, 0) * 12))
            // Keeps text off the selection capsule's edge.
            .padding(.horizontal, 2)
    }
}

struct ContentView: View {
    let document: MarkdownReaderDocument
    private let fileURL: URL?
    private let documentRootURL: URL?

    @State private var rendered: RenderedMarkdown
    @State private var selectedTOCID: Int?
    @State private var scrollAnchor: String?
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var previewImage: NSImage?
    @State private var backRequestID: UUID?
    @State private var canGoBack = false
    @State private var isBackHovered = false
    @State private var findRequest: MarkdownWebView.FindRequest?
    @State private var findBarHeight: CGFloat = 0

    @AppStorage("reader.fontSize") private var fontSize = ReaderDisplayOptions.defaultFontSize
    @AppStorage("reader.lineHeight") private var lineHeight = ReaderDisplayOptions.defaultLineHeight
    @AppStorage("reader.contentWidth") private var contentWidthPercentage =
        ReaderDisplayOptions.defaultContentWidthPercentage
    @AppStorage("reader.theme") private var theme = ReaderTheme.system
    @AppStorage("reader.syntaxHighlighting") private var syntaxHighlighting = true

    init(document: MarkdownReaderDocument, fileURL: URL? = nil) {
        self.document = document
        self.fileURL = fileURL
        documentRootURL = fileURL?.deletingLastPathComponent()
        let result = MarkdownHTMLRenderer.render(document.text)
        _rendered = State(initialValue: result)
        _columnVisibility = State(initialValue: result.toc.count >= 4 ? .all : .detailOnly)
    }

    private var displayOptions: ReaderDisplayOptions {
        ReaderDisplayOptions(
            fontSize: fontSize,
            lineHeight: lineHeight,
            contentWidthPercentage: contentWidthPercentage,
            theme: theme,
            syntaxHighlighting: syntaxHighlighting
        )
    }

    private var backButton: some View {
        Button {
            backRequestID = UUID()
        } label: {
            Image(systemName: "arrow.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    @ViewBuilder
    private var floatingBackButton: some View {
        if #available(macOS 26.0, *) {
            backButton.glassEffect(.regular.interactive(), in: Circle())
        } else {
            backButton
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if rendered.toc.isEmpty {
                    ContentUnavailableView(
                        "No Table of Contents",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Add Markdown headings to show an outline here.")
                    )
                } else {
                    List(rendered.toc, selection: Binding(
                        get: { selectedTOCID },
                        set: { newValue in
                            selectedTOCID = newValue
                            scrollAnchor = rendered.toc.first { $0.id == newValue }?.anchor
                        }
                    )) { item in
                        TableOfContentsRow(item: item)
                            .tag(Optional(item.id))
                    }
                    .listStyle(.sidebar)
                    .navigationTitle("Contents")
                    .background(TableOfContentsScrollBridge(selectedRow: selectedTOCID))
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
        } detail: {
            MarkdownWebView(
                rendered: rendered,
                documentRootURL: documentRootURL,
                displayOptions: displayOptions,
                scrollAnchor: scrollAnchor,
                onActiveHeadingChange: { anchor in
                    selectedTOCID = rendered.toc.first { $0.anchor == anchor }?.id
                    scrollAnchor = nil
                },
                onImageTap: { previewImage = $0 },
                backRequestID: backRequestID,
                onBackAvailabilityChange: { canGoBack = $0 },
                findRequest: findRequest,
                onFindBarHeightChange: { findBarHeight = $0 }
            )
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .topLeading) {
                if canGoBack && previewImage == nil {
                    floatingBackButton
                        .overlay {
                            Circle()
                                .fill(.primary.opacity(isBackHovered ? 0.12 : 0))
                                .allowsHitTesting(false)
                        }
                        .animation(.easeOut(duration: 0.12), value: isBackHovered)
                        .onHover { isBackHovered = $0 }
                        .onDisappear { isBackHovered = false }
                        .keyboardShortcut("[", modifiers: .command)
                        .help("Return to the link you clicked (⌘[)")
                        .padding(12)
                        .padding(.top, findBarHeight)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        // SwiftUI owns the hosted content's scheme; the window bridge below
        // covers AppKit surfaces such as the settings popover.
        .preferredColorScheme(theme.colorScheme(system: SystemAppearance.shared.colorScheme))
        .focusedSceneValue(\.readerFindActions, previewImage == nil ? ReaderFindActions { action in
            findRequest = .init(action: action)
        } : nil)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // The button toggles the bar and shows it as pressed while open;
                // ⌘F always opens and focuses it.
                Toggle("Search", systemImage: "magnifyingglass", isOn: Binding(
                    get: { findBarHeight > 0 },
                    set: { findRequest = .init(action: $0 ? .showFindInterface : .hideFindInterface) }
                ))
                .toggleStyle(.button)
                .disabled(previewImage != nil)
                .help("Find in document (⌘F)")
                .accessibilityIdentifier("reader-search-button")
            }
            ToolbarItem(placement: .primaryAction) {
                ReaderSettingsToolbarButton(
                    fontSize: $fontSize,
                    lineHeight: $lineHeight,
                    contentWidthPercentage: $contentWidthPercentage,
                    theme: $theme,
                    syntaxHighlighting: $syntaxHighlighting
                )
            }
        }
        .background {
            ReaderWindowAppearanceBridge(theme: theme)
                .frame(width: 0, height: 0)
            ImageLightboxPresenter(image: previewImage) { previewImage = nil }
                .frame(width: 0, height: 0)
        }
        .task(id: fileURL) {
            guard let fileURL else { return }
            for await text in DocumentFileMonitor.changes(of: fileURL, currentText: document.text) {
                reload(text)
            }
        }
        .onAppear {
            let normalized = ReaderDisplayOptions.normalizedContentWidthPercentage(
                contentWidthPercentage
            )
            if normalized != contentWidthPercentage {
                contentWidthPercentage = normalized
            }
        }
    }

    /// Re-renders after the file changes on disk; the web view keeps its scroll offset.
    private func reload(_ text: String) {
        let result = MarkdownHTMLRenderer.render(text)
        guard result != rendered else { return }
        scrollAnchor = nil
        rendered = result
    }
}

#Preview {
    ContentView(document: MarkdownReaderDocument())
}
