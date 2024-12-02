//
//  ContentView.swift
//  MarkdownReader
//
//  Created by taojiachun on 2024-12-02.
//

import SwiftUI
import MarkdownUI

struct MarkdownView: View {
    let content: String
    
    var body: some View {
        Markdown(content)
            .padding(32)
    }
}

struct ContentView: View {
    @Binding var document: MarkdownReaderDocument

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                MarkdownView(content: document.text)
            }
        }
    }
}

#Preview {
    ContentView(document: .constant(MarkdownReaderDocument()))
}
