import AppKit
import SwiftUI

struct TableOfContentsScrollBridge: NSViewRepresentable {
    let selectedRow: Int?

    func makeNSView(context: Context) -> TableOfContentsRevealView {
        TableOfContentsRevealView()
    }

    func updateNSView(_ view: TableOfContentsRevealView, context: Context) {
        view.selectedRow = selectedRow
        view.scheduleReveal()
    }
}

final class TableOfContentsRevealView: NSView {
    var selectedRow: Int?
    private var revealPending = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleReveal()
    }

    func scheduleReveal(attempt: Int = 0) {
        guard !revealPending else { return }
        revealPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.revealPending = false
            guard self.window != nil, let selectedRow = self.selectedRow else { return }
            guard let tableView = self.tableView(), selectedRow < tableView.numberOfRows else {
                if attempt < 3 { self.scheduleReveal(attempt: attempt + 1) }
                return
            }
            guard selectedRow >= 0 else { return }
            let target = tableView.rect(ofRow: selectedRow)
                .insetBy(dx: 0, dy: -8)
                .intersection(tableView.bounds)
            if !tableView.visibleRect.contains(target) {
                tableView.scrollToVisible(target)
                if attempt < 3 { self.scheduleReveal(attempt: attempt + 1) }
            }
        }
    }

    private func tableView() -> NSTableView? {
        var ancestor = superview
        while let view = ancestor {
            if let tableView = tableView(in: view) { return tableView }
            ancestor = view.superview
        }
        return nil
    }

    private func tableView(in view: NSView) -> NSTableView? {
        if let tableView = view as? NSTableView { return tableView }
        for subview in view.subviews {
            if let tableView = tableView(in: subview) { return tableView }
        }
        return nil
    }
}
