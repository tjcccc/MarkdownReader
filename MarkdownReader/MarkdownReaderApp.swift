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
        DocumentGroup(newDocument: MarkdownReaderDocument()) { file in
            ContentView(document: file.$document)
                .frame(minWidth: 320, minHeight: 240)
                
        }
        .defaultSize(width: 600, height: 800)
    }
}
