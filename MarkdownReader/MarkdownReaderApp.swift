//
//  MarkdownReaderApp.swift
//  MarkdownReader
//
//  Created by taojiachun on 2024-12-02.
//

import SwiftUI

@main
struct MarkdownReaderApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownReaderDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 1200, height: 820)
        .restorationBehavior(.disabled)
        .commands {
            SidebarCommands()
        }
    }
}
