// Presents a document image in a modal child window that dims the entire
// reader window, including its title bar and toolbar.

import AppKit
import SwiftUI

struct ImageLightboxPresenter: NSViewRepresentable {
    let image: NSImage?
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> ImageLightboxAnchorView {
        ImageLightboxAnchorView()
    }

    func updateNSView(_ view: ImageLightboxAnchorView, context: Context) {
        view.onDismiss = onDismiss
        view.image = image
    }

    static func dismantleNSView(_ view: ImageLightboxAnchorView, coordinator: ()) {
        view.image = nil
    }
}

/// A zero-size view that tracks its document window and owns the lightbox window.
@MainActor
final class ImageLightboxAnchorView: NSView {
    var onDismiss: (() -> Void)?
    var image: NSImage? {
        didSet {
            guard image !== oldValue else { return }
            updatePresentation()
        }
    }

    private(set) var lightboxWindow: ImageLightboxWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePresentation()
    }

    private func updatePresentation() {
        lightboxWindow?.dismiss()
        lightboxWindow = nil
        guard let image, let parent = window else { return }
        let lightbox = ImageLightboxWindow(image: image, parent: parent) { [weak self] in
            self?.onDismiss?()
        }
        lightboxWindow = lightbox
        lightbox.present()
    }
}

@MainActor
final class ImageLightboxWindow: NSWindow {
    // Matches the rounded corners of standard titled windows so the backdrop
    // does not spill outside the document window.
    private static let cornerRadius: CGFloat = 16

    private weak var parentReaderWindow: NSWindow?
    private let onDismiss: () -> Void
    private var frameObservers: [NSObjectProtocol] = []

    init(image: NSImage, parent: NSWindow, onDismiss: @escaping () -> Void) {
        parentReaderWindow = parent
        self.onDismiss = onDismiss
        super.init(contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        appearance = parent.appearance
        contentView = NSHostingView(rootView: ImageLightboxContent(
            image: image,
            cornerRadius: parent.styleMask.contains(.fullScreen) ? 0 : Self.cornerRadius,
            onDismiss: onDismiss
        ))
        setAccessibilityLabel("Image preview")
    }

    override var canBecomeKey: Bool { true }

    func present() {
        guard let parent = parentReaderWindow else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            frameObservers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.followParentFrame() }
            })
        }
        frameObservers.append(center.addObserver(
            forName: NSWindow.willCloseNotification, object: parent, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        })
        alphaValue = 0
        parent.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        frameObservers.forEach(NotificationCenter.default.removeObserver)
        frameObservers.removeAll()
        let parent = parentReaderWindow
        parent?.removeChildWindow(self)
        orderOut(nil)
        if parent?.isVisible == true { parent?.makeKey() }
    }

    private func followParentFrame() {
        guard let parent = parentReaderWindow else { return }
        setFrame(parent.frame, display: true)
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onDismiss()
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct ImageLightboxContent: View {
    let image: NSImage
    let cornerRadius: CGFloat
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityAddTraits(.isModal)
    }
}
