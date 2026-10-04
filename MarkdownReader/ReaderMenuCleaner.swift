// Trims standard menus for a read-only, one-document-per-window reader.
// SwiftUI can only replace whole command groups (replacing the save group also
// drops Close, Close All, and Share), so individual items are handled by action.

import AppKit

@MainActor
final class ReaderAppDelegate: NSObject, NSApplicationDelegate {
    private var menuObserver: NSObjectProtocol?
    private var cleanupScheduled = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // One document per window: no tabs, and no Show Tab Bar / Show All Tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Pick up favorites renamed or moved while the app was in the background.
        FavoritesStore.shared.refreshLocations()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ReaderMenuCleaner.clean(NSApp.mainMenu)
        // SwiftUI rebuilds menus when commands change; clean up after each rebuild.
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didAddItemNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleCleanup() }
        }
    }

    private func scheduleCleanup() {
        guard !cleanupScheduled else { return }
        cleanupScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.cleanupScheduled = false
            ReaderMenuCleaner.clean(NSApp.mainMenu)
        }
    }
}

@MainActor
enum ReaderMenuCleaner {
    /// Document commands that would modify, copy, or relocate the file. Removed
    /// with their shortcuts.
    static let documentActions: Set<Selector> = [
        #selector(NSDocument.save(_:)),
        #selector(NSDocument.saveAs(_:)),
        #selector(NSDocument.duplicate(_:)),
        #selector(NSDocument.rename(_:)),
        #selector(NSDocument.move(_:)),
        #selector(NSDocument.revertToSaved(_:)),
        #selector(NSDocument.browseVersions(_:)),
    ]

    /// Editing commands that never apply to the document. Hidden, but their
    /// shortcuts stay active because the find field still needs undo and paste.
    static let editingActions: Set<Selector> = [
        Selector(("undo:")),
        Selector(("redo:")),
        #selector(NSText.cut(_:)),
        #selector(NSText.paste(_:)),
        #selector(NSTextView.pasteAsPlainText(_:)),
        #selector(NSText.delete(_:)),
    ]

    static func clean(_ menu: NSMenu?) {
        guard let menu else { return }
        var changed = false
        var index = menu.items.count - 1
        while index >= 0 {
            let item = menu.items[index]
            let previousAction = index > 0 ? menu.items[index - 1].action : nil
            if let submenu = item.submenu {
                if isRevertItem(item, after: previousAction) {
                    menu.removeItem(item)
                    changed = true
                } else {
                    clean(submenu)
                }
            } else if let action = item.action, documentActions.contains(action) {
                menu.removeItem(item)
                changed = true
            } else if let action = item.action, editingActions.contains(action), !item.isHidden {
                item.allowsKeyEquivalentWhenHidden = true
                item.isHidden = true
                changed = true
            }
            index -= 1
        }
        if changed { tidySeparators(in: menu) }
    }

    /// Revert To is a lazily filled submenu that AppKit inserts after launch,
    /// with the same icon and delegate as Open Recent and Share. Its position is
    /// what identifies it: it ends the document group, directly after Move To…
    /// (or after Close All once the save items are gone). If AppKit reorders the
    /// group, Revert To simply stays visible.
    private static let revertPredecessors: Set<Selector> = [
        #selector(NSDocument.move(_:)),
        Selector(("closeAll:")),
    ]

    private static func isRevertItem(_ item: NSMenuItem, after previousAction: Selector?) -> Bool {
        previousAction.map(revertPredecessors.contains) == true
    }

    /// Hides separators that would be leading, trailing, or doubled among the
    /// visible items.
    private static func tidySeparators(in menu: NSMenu) {
        var pendingSeparator: NSMenuItem?
        var hasVisibleItem = false
        for item in menu.items {
            if item.isSeparatorItem {
                item.isHidden = true
                if hasVisibleItem, pendingSeparator == nil { pendingSeparator = item }
            } else if !item.isHidden {
                pendingSeparator?.isHidden = false
                pendingSeparator = nil
                hasVisibleItem = true
            }
        }
    }
}
