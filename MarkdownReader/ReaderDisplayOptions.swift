//
//  ReaderDisplayOptions.swift
//  MarkdownReader
//

import AppKit
import SwiftUI

@MainActor
enum ReaderChrome {
    static let backgroundColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(white: 40.0 / 255.0, alpha: 1)
        }
        return NSColor.windowBackgroundColor
    }
}

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

    var windowAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class ReaderWindowAppearanceView: NSView {
    var theme = ReaderTheme.system {
        didSet { applyAppearance() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearance()
    }

    func applyAppearance() {
        window?.appearance = theme.windowAppearance
    }
}

struct ReaderWindowAppearanceBridge: NSViewRepresentable {
    let theme: ReaderTheme

    func makeNSView(context: Context) -> ReaderWindowAppearanceView {
        let view = ReaderWindowAppearanceView(frame: .zero)
        view.theme = theme
        return view
    }

    func updateNSView(_ view: ReaderWindowAppearanceView, context: Context) {
        view.theme = theme
        view.applyAppearance()
    }
}

struct ReaderDisplayOptions: Equatable {
    static let defaultFontSize = 17.0
    static let defaultLineHeight = 1.6
    static let defaultContentWidthPercentage = 75.0
    static let fontSizeRange = 13.0...26.0
    static let lineHeightRange = 1.2...2.0
    static let contentWidthPercentageRange = 50.0...100.0
    static let contentWidthPercentageStep = 5.0
    static let legacyMaximumContentWidth = 1_200.0

    let fontSize: Double
    let lineHeight: Double
    let contentWidthPercentage: Double
    let theme: ReaderTheme
    let syntaxHighlighting: Bool

    init(
        fontSize: Double,
        lineHeight: Double,
        contentWidthPercentage: Double,
        theme: ReaderTheme,
        syntaxHighlighting: Bool
    ) {
        self.fontSize = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        self.lineHeight = min(max(lineHeight, Self.lineHeightRange.lowerBound), Self.lineHeightRange.upperBound)
        self.contentWidthPercentage = Self.normalizedContentWidthPercentage(
            contentWidthPercentage
        )
        self.theme = theme
        self.syntaxHighlighting = syntaxHighlighting
    }

    static func normalizedContentWidthPercentage(_ storedValue: Double) -> Double {
        guard storedValue.isFinite else { return defaultContentWidthPercentage }

        // Versions that first introduced this setting stored 640...1200 pixels
        // under the same preference key. Preserve the slider's approximate
        // position when that value is encountered.
        let percentage = storedValue > contentWidthPercentageRange.upperBound
            ? storedValue / legacyMaximumContentWidth * 100
            : storedValue
        let clampedPercentage = min(
            max(percentage, contentWidthPercentageRange.lowerBound),
            contentWidthPercentageRange.upperBound
        )
        return (clampedPercentage / contentWidthPercentageStep).rounded()
            * contentWidthPercentageStep
    }
}

struct ReaderSettingsToolbarButton: NSViewRepresentable {
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var contentWidthPercentage: Double
    @Binding var theme: ReaderTheme
    @Binding var syntaxHighlighting: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            image: NSImage(
                systemSymbolName: "gearshape",
                accessibilityDescription: "Reader Settings"
            ) ?? NSImage(),
            target: context.coordinator,
            action: #selector(Coordinator.togglePopover(_:))
        )
        button.bezelStyle = .toolbar
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Reader Settings"
        button.setAccessibilityLabel("Reader Settings")
        button.setAccessibilityIdentifier("reader-settings-button")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        guard !context.coordinator.isPopoverShown else { return }
        context.coordinator.updateContent(content)
    }

    private var content: ReaderSettingsView {
        ReaderSettingsView(
            fontSize: $fontSize,
            lineHeight: $lineHeight,
            contentWidthPercentage: $contentWidthPercentage,
            theme: $theme,
            syntaxHighlighting: $syntaxHighlighting
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        private let popover: NSPopover
        private let hostingController: NSHostingController<ReaderSettingsView>

        fileprivate var isPopoverShown: Bool {
            popover.isShown
        }

        init(content: ReaderSettingsView) {
            hostingController = NSHostingController(rootView: content)
            popover = NSPopover()
            super.init()

            popover.behavior = .transient
            popover.animates = true
            popover.contentViewController = hostingController
        }

        fileprivate func updateContent(_ content: ReaderSettingsView) {
            hostingController.rootView = content
        }

        @objc fileprivate func togglePopover(_ sender: NSButton) {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                hostingController.view.layoutSubtreeIfNeeded()
                popover.contentSize = hostingController.view.fittingSize
                popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            }
        }
    }
}

struct ReaderSettingsView: View {
    @Binding var fontSize: Double
    @Binding var lineHeight: Double
    @Binding var contentWidthPercentage: Double
    @Binding var theme: ReaderTheme
    @Binding var syntaxHighlighting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Font size")
                    Spacer()
                    Text("\(Int(fontSize.rounded())) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack(spacing: 10) {
                    Text("A")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Slider(
                        value: $fontSize,
                        in: ReaderDisplayOptions.fontSizeRange,
                        step: 1
                    )
                    .accessibilityLabel("Font size")
                    .accessibilityValue("\(Int(fontSize.rounded())) points")

                    Text("A")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
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
                )
                .accessibilityLabel("Line spacing")
                .accessibilityValue(
                    lineHeight.formatted(.number.precision(.fractionLength(1))) + " times"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reading width")
                    Spacer()
                    Text("\(Int(contentWidthPercentage.rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: $contentWidthPercentage,
                    in: ReaderDisplayOptions.contentWidthPercentageRange,
                    step: ReaderDisplayOptions.contentWidthPercentageStep
                )
                .accessibilityLabel("Reading width")
                .accessibilityValue("\(Int(contentWidthPercentage.rounded())) percent")
            }

            HStack(spacing: 12) {
                Text("Theme")
                    .fixedSize()

                Spacer(minLength: 12)

                Picker("Theme", selection: $theme) {
                    ForEach(ReaderTheme.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Syntax highlighting", isOn: $syntaxHighlighting)
                Text("Uses a fenced code block’s language when provided, or detects it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 12) {
                    Text("Quick Look Preview")

                    Spacer()

                    Button("Manage…") {
                        openQuickLookExtensionSettings()
                    }
                    .accessibilityHint(
                        "Opens macOS settings where the Quick Look extension can be enabled or disabled."
                    )
                }

                Text("Preview Markdown files in Finder by pressing Space. Managed by macOS.")
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
                    contentWidthPercentage = ReaderDisplayOptions.defaultContentWidthPercentage
                    theme = .system
                    syntaxHighlighting = true
                }
            }
        }
        .controlSize(.regular)
        .padding(20)
        .frame(width: 332)
    }

    private func openQuickLookExtensionSettings() {
        if let extensionsURL = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ), NSWorkspace.shared.open(extensionsURL) {
            return
        }

        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        )
    }
}
