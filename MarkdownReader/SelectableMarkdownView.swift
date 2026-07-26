//
//  SelectableMarkdownView.swift
//  MarkdownReader
//
//  A read-only, fully selectable text view for the rendered Markdown document.
//  Backed by AppKit's NSTextView so selection, ⌘A, Copy, and Find work across
//  the entire document natively (unlike per-block SwiftUI Text rendering).
//

import AppKit
import SwiftUI

struct SelectableMarkdownView: NSViewRepresentable {
    let attributedText: NSAttributedString
    var scrollTarget: NSRange?
    var onImageTap: ((NSImage) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        // Explicit TextKit 1 stack: the custom layout manager fixes inline-code
        // background fills on wrapped lines, and image hit-testing below needs
        // `layoutManager` anyway (accessing it would force the fallback lazily).
        let storage = NSTextStorage()
        let layoutManager = IndentAwareBackgroundLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = ReadingTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 24, height: 28)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.displaysLinkToolTips = true
        textView.delegate = context.coordinator
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.onImageTap = onImageTap
        textView.textStorage?.setAttributedString(attributedText)
        textView.reloadCodeBlockHeaders()
        context.coordinator.lastContent = attributedText

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ReadingTextView else { return }
        textView.onImageTap = onImageTap

        if context.coordinator.lastContent !== attributedText {
            textView.textStorage?.setAttributedString(attributedText)
            textView.reloadCodeBlockHeaders()
            context.coordinator.lastContent = attributedText
            context.coordinator.lastScroll = nil
            textView.window?.invalidateCursorRects(for: textView)
        }

        if let target = scrollTarget, target != context.coordinator.lastScroll {
            context.coordinator.lastScroll = target
            let length = textView.textStorage?.length ?? 0
            let location = min(max(0, target.location), length)
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var lastContent: NSAttributedString?
        var lastScroll: NSRange?

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL?
            switch link {
            case let value as URL: url = value
            case let value as String: url = URL(string: value)
            default: url = nil
            }
            guard let url else { return false }
            NSWorkspace.shared.open(url)
            return true
        }
    }
}

/// Button that insists on a pointing-hand cursor. Whether the pointer event is
/// routed to the button or to the text view underneath depends on tracking-area
/// dispatch, so both sides claim the cursor (see `ReadingTextView.mouseMoved`).
private final class PointingHandButton: NSButton {
    private var cursorArea: NSTrackingArea?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorArea { removeTrackingArea(cursorArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        cursorArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}

/// The language tag and copy button shown in a fenced code block's top strip.
/// An overlay rather than text so it stays out of the document's selection and
/// copied text.
private final class CodeBlockHeaderView: NSView {
    private static let buttonSize: CGFloat = 20
    private static let copySymbol = "doc.on.doc"
    private static let copiedSymbol = "checkmark"

    let characterRange: NSRange
    private let info: CodeBlockInfo
    private let button = PointingHandButton()
    private var resetTitleWork: DispatchWorkItem?

    init(info: CodeBlockInfo, characterRange: NSRange) {
        self.info = info
        self.characterRange = characterRange
        super.init(frame: .zero)

        var constraints: [NSLayoutConstraint] = []

        // Language sits at the leading edge, aligned with the code below it.
        if let language = info.language {
            let label = NSTextField(labelWithString: language)
            label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .tertiaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            constraints += [
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: CodeBlockMetrics.padding),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ]
        }

        button.isBordered = false
        button.bezelStyle = .smallSquare
        button.imagePosition = .imageOnly
        button.contentTintColor = .tertiaryLabelColor
        button.toolTip = "Copy code"
        button.setButtonType(.momentaryChange)
        button.target = self
        button.action = #selector(copyCode)
        button.translatesAutoresizingMaskIntoConstraints = false
        setSymbol(Self.copySymbol)

        addSubview(button)
        constraints += [
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -CodeBlockMetrics.padding),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            button.heightAnchor.constraint(equalToConstant: Self.buttonSize)
        ]
        NSLayoutConstraint.activate(constraints)
    }

    // The strip this sits in is the code box's top padding — no glyphs there, so
    // a partial repaint of it redraws the text view's background but not the
    // block's box. Painting the same composite here makes that impossible to see.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        CodeBlockMetrics.background.setFill()
        bounds.fill()
    }

    private func setSymbol(_ name: String) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Copy code")?
            .withSymbolConfiguration(configuration)
    }

    /// The copy button's frame, in the coordinates of the view holding this
    /// header — the text view uses it to show a pointing-hand cursor.
    /// `button.frame` (not `bounds`) is what's expressed in this view's space.
    var copyButtonFrame: NSRect {
        convert(button.frame, to: superview)
    }

    // Belt and braces with the text view's mouseMoved handling: whichever view
    // the pointer is routed to, the button reads as clickable.
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(button.frame, cursor: .pointingHand)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(info.code, forType: .string)

        setSymbol(Self.copiedSymbol)
        resetTitleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.setSymbol(Self.copySymbol) }
        resetTitleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}

/// Layout manager that adjusts `.backgroundColor` fills: it keeps them out of a
/// paragraph's indent area, and gives inline code spans a little side padding.
///
/// When a styled run wraps, NSLayoutManager builds the continuation line's fill
/// rect from the *line fragment* rect, whose left edge is the container edge —
/// not the *used* rect, whose left edge respects `headIndent`. On indented list
/// items that paints a stray highlighted strip in front of the wrapped text.
/// Clamping each rect's left edge to the line's used rect removes it.
private final class IndentAwareBackgroundLayoutManager: NSLayoutManager {
    /// Horizontal breathing room on each side of an inline code span. Attributed
    /// strings have no padding attribute, so it is applied to the fill rect.
    private let inlineCodePadding: CGFloat = 4

    /// Corner radius of the inline code chip.
    private let inlineCodeRadius: CGFloat = 4

    /// Fill rects arrive already offset by the draw origin; used rects are in
    /// container coordinates, so the origin is needed to compare them.
    private var drawOrigin: NSPoint = .zero

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawOrigin = origin
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>,
        count rectCount: Int,
        forCharacterRange charRange: NSRange,
        color: NSColor
    ) {
        guard charRange.location < (textStorage?.length ?? 0) else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }

        // NSTextView routes selection highlighting through this same method. A
        // selection band must still cover the indent to read as contiguous, so
        // only text-background fills (whose color is the `.backgroundColor`
        // attribute the layout manager passes straight through) get the left
        // clamp and the inline-code treatment. Height is fixed up for both.
        let attributeColor = textStorage?.attribute(.backgroundColor, at: charRange.location, effectiveRange: nil) as? NSColor
        let isTextBackground = attributeColor == color
        let isInlineCode = isTextBackground
            && textStorage?.attribute(.inlineCodeSpan, at: charRange.location, effectiveRange: nil) != nil

        let glyphRange = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        var usedRects: [NSRect] = []
        enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            usedRects.append(usedRect.offsetBy(dx: self.drawOrigin.x, dy: self.drawOrigin.y))
        }

        var clamped: [NSRect] = []
        clamped.reserveCapacity(rectCount)
        for index in 0..<rectCount {
            var rect = rectArray[index]
            // No match (empty layout, unusual line metrics): keep the rect as-is
            // rather than dropping a highlight.
            if let line = usedRects.first(where: { $0.minY <= rect.midY && rect.midY < $0.maxY }) {
                if isTextBackground, line.minX > rect.minX {
                    let width = rect.maxX - line.minX
                    guard width > 0 else { continue }
                    rect.origin.x = line.minX
                    rect.size.width = width
                }
                // A paragraph's last line fragment is taller than its glyphs by
                // `paragraphSpacing` (measured: +12pt; mid-paragraph lines have
                // no excess at all, line spacing sits inside the used rect).
                // Filling that would paint the gap between paragraphs — most
                // visibly as a tall band above a code block when selecting into it.
                if rect.maxY > line.maxY {
                    let height = line.maxY - rect.minY
                    guard height > 0 else { continue }
                    rect.size.height = height
                }
            }
            // Padding goes on after clamping, so a wrapped span keeps the same
            // inset on its continuation lines as everywhere else.
            if isInlineCode {
                rect = rect.insetBy(dx: -inlineCodePadding, dy: 0)
            }
            clamped.append(rect)
        }

        // Inline code is drawn here rather than by super so it can have rounded
        // corners; block fills keep the plain square fill.
        if isInlineCode {
            color.setFill()
            for rect in clamped {
                NSBezierPath(roundedRect: rect, xRadius: inlineCodeRadius, yRadius: inlineCodeRadius).fill()
            }
            return
        }

        clamped.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            super.fillBackgroundRectArray(base, count: buffer.count, forCharacterRange: charRange, color: color)
        }
    }
}

/// NSTextView that keeps the text in a centered, common-width reading column,
/// shows a pointing-hand cursor over images, and reports image clicks.
private final class ReadingTextView: NSTextView {
    private let maxColumnWidth: CGFloat = 800
    var onImageTap: ((NSImage) -> Void)?
    private var imageTrackingAreas: [NSTrackingArea] = []
    private var codeBlockHeaders: [CodeBlockHeaderView] = []

    override func layout() {
        let horizontal = max(24, (bounds.width - maxColumnWidth) / 2)
        if abs(textContainerInset.width - horizontal) > 0.5 {
            textContainerInset = NSSize(width: horizontal, height: textContainerInset.height)
        }
        super.layout()
        positionCodeBlockHeaders()
    }

    // MARK: Code block headers

    /// Rebuilds one header (language tag + copy button) per fenced code block.
    /// Call after the text storage changes; `layout()` only repositions them.
    func reloadCodeBlockHeaders() {
        for header in codeBlockHeaders { header.removeFromSuperview() }
        codeBlockHeaders.removeAll()

        guard let storage = textStorage else { return }
        storage.enumerateAttribute(.codeBlockInfo, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let info = value as? CodeBlockInfo else { return }
            let header = CodeBlockHeaderView(info: info, characterRange: range)
            addSubview(header)
            codeBlockHeaders.append(header)
        }
        positionCodeBlockHeaders()
    }

    private func positionCodeBlockHeaders() {
        guard !codeBlockHeaders.isEmpty, let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin

        for header in codeBlockHeaders {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: header.characterRange, actualCharacterRange: nil)
            let textRect = layoutManager
                .boundingRect(forGlyphRange: glyphRange, in: textContainer)
                .offsetBy(dx: origin.x, dy: origin.y)

            // `textRect` covers the code itself; above it sits the box's reserved
            // top padding. Centre the header in that strip — hugging the code line
            // reads as lopsided — and span the text width so the language tag
            // lines up with the code and the button sits at the right edge.
            // Span the full box width (text width plus its side padding) so the
            // strip it repaints has no uncovered edges; the tag and button are
            // inset by the same padding, keeping them aligned with the code.
            let reserved = CodeBlockMetrics.padding + CodeBlockMetrics.headerHeight
            let height = header.fittingSize.height
            let y = textRect.minY - (reserved + height) / 2
            header.frame = NSRect(
                x: textRect.minX - CodeBlockMetrics.padding,
                y: y,
                width: textRect.width + CodeBlockMetrics.padding * 2,
                height: height
            )
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    // NSTextView manages its own I-beam cursor in mouseMoved, so cursor rects and
    // even cursorUpdate get reset (the cursor "blinks" to the hand then back).
    // Install a visible-rect mouse-moved tracking area and intercept mouseMoved:
    // over an image we set the pointing hand and don't call super (so the I-beam
    // isn't restored); elsewhere super handles the I-beam as usual.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in imageTrackingAreas { removeTrackingArea(area) }
        imageTrackingAreas.removeAll()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        imageTrackingAreas.append(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if wantsPointingHand(at: point) {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if wantsPointingHand(at: point) {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    /// Images and copy buttons are clickable, so they get a hand instead of the
    /// I-beam NSTextView would otherwise restore.
    private func wantsPointingHand(at point: NSPoint) -> Bool {
        if codeBlockHeaders.contains(where: { $0.copyButtonFrame.contains(point) }) { return true }
        return imageAttachment(at: point) != nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let image = imageAttachment(at: point) {
            onImageTap?(image)
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: Attachment hit-testing

    private func imageAttachment(at point: NSPoint) -> NSImage? {
        var hit: NSImage?
        enumerateImageAttachments { image, rect in
            if rect.contains(point) { hit = image }
        }
        return hit
    }

    private func enumerateImageAttachments(_ body: (NSImage, NSRect) -> Void) {
        guard let layoutManager, let textContainer, let storage = textStorage else { return }
        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin

        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment, let image = attachment.image else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager
                .boundingRect(forGlyphRange: glyphRange, in: textContainer)
                .offsetBy(dx: origin.x, dy: origin.y)
            body(image, rect)
        }
    }
}
