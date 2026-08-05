//
//  ReaderDisplayOptions.swift
//  MarkdownReader
//

import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct ReaderDisplayOptions: Equatable {
    static let defaultFontSize = 17.0
    static let defaultLineHeight = 1.6
    static let fontSizeRange = 13.0...26.0
    static let lineHeightRange = 1.2...2.0

    let fontSize: Double
    let lineHeight: Double
    let theme: ReaderTheme
    let syntaxHighlighting: Bool

    init(
        fontSize: Double,
        lineHeight: Double,
        theme: ReaderTheme,
        syntaxHighlighting: Bool
    ) {
        self.fontSize = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        self.lineHeight = min(max(lineHeight, Self.lineHeightRange.lowerBound), Self.lineHeightRange.upperBound)
        self.theme = theme
        self.syntaxHighlighting = syntaxHighlighting
    }
}

struct ReaderDisplayOptionsView: View {
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var theme: ReaderTheme
    @Binding var syntaxHighlighting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Display")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Font size")
                    Spacer()
                    Text("\(Int(fontSize.rounded())) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $fontSize,
                    in: ReaderDisplayOptions.fontSizeRange,
                    step: 1
                ) {
                    Text("Font size")
                } minimumValueLabel: {
                    Image(systemName: "textformat.size.smaller")
                } maximumValueLabel: {
                    Image(systemName: "textformat.size.larger")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Line spacing")
                    Spacer()
                    Text(lineHeight.formatted(.number.precision(.fractionLength(1))) + "×")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $lineHeight,
                    in: ReaderDisplayOptions.lineHeightRange,
                    step: 0.1
                ) {
                    Text("Line spacing")
                }
            }

            Picker("Theme", selection: $theme) {
                ForEach(ReaderTheme.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Syntax highlighting", isOn: $syntaxHighlighting)
                Text("Uses a fenced code block’s language when provided, or detects it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Spacer()
                Button("Reset") {
                    fontSize = ReaderDisplayOptions.defaultFontSize
                    lineHeight = ReaderDisplayOptions.defaultLineHeight
                    theme = .system
                    syntaxHighlighting = true
                }
            }
        }
        .padding(18)
        .frame(width: 320)
    }
}
