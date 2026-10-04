//
//  MarkdownReaderApp.swift
//  MarkdownReader
//
//  Created by taojiachun on 2024-12-02.
//

import SwiftUI

@main
struct MarkdownReaderApp: App {
    @NSApplicationDelegateAdaptor(ReaderAppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownReaderDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 1200, height: 820)
        .restorationBehavior(.disabled)
        .commands {
            // Reader-only: no document creation. Commands that save, duplicate,
            // rename, move, or revert are removed by ReaderMenuCleaner.
            CommandGroup(replacing: .newItem) {}
            SidebarCommands()
            ReaderFindCommands()
        }
    }
}
