// File-menu commands for favorites: toggle the focused document (⌘D) and open
// a favorite. Missing favorites are explained and removed when chosen.

import AppKit
import SwiftUI

/// The focused window's favorite state. Published by the window (rather than
/// read from the store in the command body) so the menu title stays current.
struct ReaderFavoriteToggle {
    let isFavorite: Bool
    let toggle: () -> Void
}

private struct ReaderFavoriteToggleKey: FocusedValueKey {
    typealias Value = ReaderFavoriteToggle
}

extension FocusedValues {
    var readerFavoriteToggle: ReaderFavoriteToggle? {
        get { self[ReaderFavoriteToggleKey.self] }
        set { self[ReaderFavoriteToggleKey.self] = newValue }
    }
}

struct FavoritesCommands: Commands {
    @FocusedValue(\.readerFavoriteToggle) private var favoriteToggle

    var body: some Commands {
        let store = FavoritesStore.shared
        CommandGroup(before: .saveItem) {
            Menu("Open Favorite") {
                if store.favorites.isEmpty {
                    Button("No Favorites") {}
                        .disabled(true)
                } else {
                    ForEach(store.favorites) { favorite in
                        Button(store.displayName(for: favorite)) {
                            FavoriteActions.open(favorite)
                        }
                        .help(favorite.path)
                    }
                    Divider()
                    Button("Clear Favorites…") {
                        FavoriteActions.confirmClear()
                    }
                }
            }
            Button(favoriteToggle?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites") {
                favoriteToggle?.toggle()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(favoriteToggle == nil)
            Divider()
        }
    }
}

@MainActor
enum FavoriteActions {
    static func open(_ favorite: FavoriteDocument, store: FavoritesStore = .shared) {
        switch store.resolve(favorite) {
        case .available(let url):
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        case .missing:
            store.remove(favorite)
            showMissingAlert(for: favorite)
        }
    }

    static func showMissingAlert(for favorite: FavoriteDocument) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "“\(favorite.name)” can’t be found"
        alert.informativeText = "The file may have been deleted, moved to the Trash, or stored on a drive that isn’t connected. It has been removed from Favorites."
        alert.addButton(withTitle: "OK")
        let folder = URL(fileURLWithPath: favorite.path).deletingLastPathComponent()
        let folderExists = FileManager.default.fileExists(atPath: folder.path)
        if folderExists { alert.addButton(withTitle: "Show Original Location") }
        if alert.runModal() == .alertSecondButtonReturn, folderExists {
            NSWorkspace.shared.open(folder)
        }
    }

    static func confirmClear(store: FavoritesStore = .shared) {
        let alert = NSAlert()
        alert.messageText = "Clear all favorites?"
        alert.informativeText = "The documents themselves are not affected."
        alert.addButton(withTitle: "Clear Favorites")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { store.clear() }
    }
}
