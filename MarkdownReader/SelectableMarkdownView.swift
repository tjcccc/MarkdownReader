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
        let textView = ReadingTextView()
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

/// NSTextView that keeps the text in a centered, common-width reading column,
/// shows a pointing-hand cursor over images, and reports image clicks.
private final class ReadingTextView: NSTextView {
    private let maxColumnWidth: CGFloat = 800
    var onImageTap: ((NSImage) -> Void)?
    private var imageTrackingAreas: [NSTrackingArea] = []

    override func layout() {
        let horizontal = max(24, (bounds.width - maxColumnWidth) / 2)
        if abs(textContainerInset.width - horizontal) > 0.5 {
            textContainerInset = NSSize(width: horizontal, height: textContainerInset.height)
        }
        super.layout()
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
        if imageAttachment(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if imageAttachment(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
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
