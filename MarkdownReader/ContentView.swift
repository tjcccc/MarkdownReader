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
            .lineLimit(2)
            .padding(.leading, CGFloat(max(item.level - 1, 0) * 12))
    }
}

struct ContentView: View {
    let document: MarkdownReaderDocument

    @State private var rendered: RenderedMarkdown
    @State private var selectedTOCID: Int?
    @State private var scrollTarget: NSRange?
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var previewImage: NSImage?

    init(document: MarkdownReaderDocument, fileURL: URL? = nil) {
        self.document = document
        let result = MarkdownAttributedRenderer.render(
            document.text,
            baseURL: fileURL?.deletingLastPathComponent()
        )
        _rendered = State(initialValue: result)
        _columnVisibility = State(initialValue: result.toc.count >= 4 ? .all : .detailOnly)
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
                    List(rendered.toc, selection: $selectedTOCID) { item in
                        TableOfContentsRow(item: item)
                            .tag(Optional(item.id))
                    }
                    .listStyle(.sidebar)
                    .navigationTitle("Contents")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
        } detail: {
            SelectableMarkdownView(
                attributedText: rendered.text,
                scrollTarget: scrollTarget,
                onImageTap: { image in
                    withAnimation(.easeInOut(duration: 0.15)) { previewImage = image }
                }
            )
            .background(Color(nsColor: .textBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedTOCID) { _, newValue in
            guard let id = newValue,
                  let item = rendered.toc.first(where: { $0.id == id }) else { return }
            scrollTarget = item.range
        }
        .overlay {
            if let previewImage {
                ImageLightbox(image: previewImage) {
                    withAnimation(.easeInOut(duration: 0.15)) { self.previewImage = nil }
                }
                .transition(.opacity)
            }
        }
    }
}

/// A full-window image preview with a semi-transparent backdrop. Click anywhere
/// or press Escape to dismiss.
private struct ImageLightbox: View {
    let image: NSImage
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                .shadow(radius: 24)
                .padding(40)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .onExitCommand(perform: onDismiss)
    }
}

#Preview {
    ContentView(document: MarkdownReaderDocument())
}
