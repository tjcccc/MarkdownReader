// Hosts a native, read-only find bar above the persistent document web view.

import AppKit
import WebKit

@MainActor
final class ReaderFindBarView: NSView {
    /// Matches the transparent toolbar above the detail pane: the text background,
    /// plus the faint white tint the toolbar adds in Dark (measured on macOS 27).
    static let backgroundColor = NSColor(name: nil) { appearance in
        let base = NSColor.textBackgroundColor
        guard appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua else { return base }
        var tinted = base
        appearance.performAsCurrentDrawingAppearance {
            tinted = base.usingColorSpace(.sRGB)?.blended(withFraction: 0.027, of: .white) ?? base
        }
        return tinted
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { true }

    // A hairline separates the bar from the document.
    override func draw(_ dirtyRect: NSRect) {
        Self.backgroundColor.setFill()
        bounds.intersection(dirtyRect).fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.minY, width: bounds.width, height: 1)
            .intersection(dirtyRect).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

@MainActor
final class ReaderSearchFieldCell: NSSearchFieldCell {
    var matchSummary = "" {
        didSet { controlView?.needsDisplay = true }
    }

    // Reserve room even while counting so typing never moves under the result label.
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var textRect = super.searchTextRect(forBounds: rect)
        textRect.size.width = max(0, textRect.width - 72)
        return textRect
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: cellFrame, in: controlView)
        guard !matchSummary.isEmpty else { return }
        let label = NSAttributedString(string: matchSummary, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let size = label.size()
        let textRect = super.searchTextRect(forBounds: cellFrame)
        label.draw(at: NSPoint(x: textRect.maxX - size.width - 4,
                               y: cellFrame.midY - size.height / 2))
    }
}

@MainActor
final class MarkdownReaderWebContainer: NSView, NSSearchFieldDelegate {
    let webView: WKWebView
    let searchField = NSSearchField()
    private let findBar = ReaderFindBarView()
    private let matchNavigation = NSSegmentedControl(
        labels: ["", ""], trackingMode: .momentary, target: nil, action: nil
    )
    private let statusLabel = NSTextField(labelWithString: "Not found")
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private var searchGeneration = 0
    private(set) var isFindBarVisible = false
    var onFindBarHeightChange: ((CGFloat) -> Void)?
    static let findBarHeight: CGFloat = 36

    override var isFlipped: Bool { true }

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        addSubview(webView)
        findBar.isHidden = true
        addSubview(findBar)

        searchField.cell = ReaderSearchFieldCell(textCell: "")
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.isBezeled = true
        searchField.bezelStyle = .roundedBezel
        (searchField.cell as? NSSearchFieldCell)?.isScrollable = true
        searchField.placeholderString = "Find in Document"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.setAccessibilityLabel("Find in document")
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isHidden = true
        matchNavigation.segmentStyle = .rounded
        matchNavigation.target = self
        matchNavigation.action = #selector(navigateMatches)
        for (index, symbol, label) in [(0, "chevron.left", "Previous match"), (1, "chevron.right", "Next match")] {
            matchNavigation.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: label), forSegment: index)
            matchNavigation.setWidth(28, forSegment: index)
            matchNavigation.setToolTip(label, forSegment: index)
            matchNavigation.setEnabled(false, forSegment: index)
        }
        doneButton.bezelStyle = .rounded
        doneButton.target = self
        doneButton.action = #selector(closeFindBar)
        let stack = NSStackView(views: [searchField, statusLabel, matchNavigation, doneButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        findBar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: findBar.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: findBar.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: findBar.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let height = isFindBarVisible ? Self.findBarHeight : 0
        findBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
        webView.frame = NSRect(x: 0, y: height, width: bounds.width, height: max(0, bounds.height - height))
    }

    func performFindAction(_ action: NSTextFinder.Action) {
        switch action {
        case .showFindInterface:
            setFindBarVisible(true)
            window?.makeFirstResponder(searchField)
            searchField.selectText(nil)
        case .hideFindInterface:
            setFindBarVisible(false)
        case .nextMatch:
            search(backwards: false)
        case .previousMatch:
            search(backwards: true)
        default:
            break
        }
    }

    private func setFindBarVisible(_ visible: Bool) {
        guard visible != isFindBarVisible else { return }
        isFindBarVisible = visible
        findBar.isHidden = !visible
        needsLayout = true
        let height = visible ? Self.findBarHeight : 0
        DispatchQueue.main.async { [weak self] in self?.onFindBarHeightChange?(height) }
        if !visible {
            clearSearchHighlights()
            window?.makeFirstResponder(webView)
        } else if !searchField.stringValue.isEmpty {
            search(backwards: false)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        search(backwards: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            setFindBarVisible(false)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            search(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
            return true
        }
        return false
    }

    private func search(backwards: Bool) {
        let query = searchField.stringValue
        for index in 0...1 { matchNavigation.setEnabled(!query.isEmpty, forSegment: index) }
        searchGeneration += 1
        let generation = searchGeneration
        statusLabel.isHidden = true
        updateMatchSummary("")
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(query, configuration: configuration) { [weak self] result in
            guard let self, self.searchGeneration == generation, self.isFindBarVisible else { return }
            self.statusLabel.isHidden = query.isEmpty || result.matchFound
            if !query.isEmpty {
                if result.matchFound {
                    self.webView.callAsyncJavaScript(
                        "return window.reader.searchPosition(query);",
                        arguments: ["query": query], in: nil, in: .page
                    ) { [weak self] result in
                        guard let self, self.searchGeneration == generation, self.isFindBarVisible,
                              case let .success(value) = result,
                              let position = value as? [String: Int] else { return }
                        self.updateMatchSummary("\(position["current", default: 0])/\(position["total", default: 0])")
                    }
                } else {
                    self.updateMatchSummary("0/0")
                }
            }
            for index in 0...1 {
                self.matchNavigation.setEnabled(!query.isEmpty && result.matchFound, forSegment: index)
            }
        }
    }

    private func updateMatchSummary(_ summary: String) {
        (searchField.cell as? ReaderSearchFieldCell)?.matchSummary = summary
        searchField.setAccessibilityHelp(summary.isEmpty ? nil : "Match \(summary)")
    }

    private func clearSearchHighlights() {
        searchGeneration += 1
        statusLabel.isHidden = true
        updateMatchSummary("")
        // WebKit keeps painting the current match after an empty query; only a
        // failed search removes it, so search for text no document contains.
        webView.find("\u{1}\u{2}\(UUID().uuidString)", configuration: WKFindConfiguration()) { _ in }
    }

    override func cancelOperation(_ sender: Any?) {
        if isFindBarVisible {
            setFindBarVisible(false)
        } else {
            nextResponder?.tryToPerform(#selector(cancelOperation(_:)), with: sender)
        }
    }

    @objc private func navigateMatches(_ sender: NSSegmentedControl) {
        search(backwards: sender.selectedSegment == 0)
    }

    @objc private func closeFindBar(_ sender: Any?) { setFindBarVisible(false) }
}
