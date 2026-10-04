// Persists favorite documents as file bookmarks, so a favorite survives renames
// and moves on the same volume. The app sandbox is off, so ordinary
// (non-security-scoped) bookmarks are sufficient.

import Foundation
import Observation

struct FavoriteDocument: Codable, Identifiable, Equatable {
    let id: UUID
    var bookmark: Data
    /// Last resolved location, refreshed whenever the bookmark is resolved.
    var path: String
    let addedAt: Date

    var name: String { (path as NSString).lastPathComponent }
}

enum FavoriteResolution: Equatable {
    case available(URL)
    case missing
}

@MainActor
@Observable
final class FavoritesStore {
    static let shared = FavoritesStore()

    /// Most recently added first.
    private(set) var favorites: [FavoriteDocument] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults = .standard, key: String = "reader.favorites") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode([FavoriteDocument].self, from: data) {
            favorites = stored
        }
        refreshLocations()
    }

    func isFavorite(_ url: URL?) -> Bool {
        guard let url else { return false }
        return index(of: url) != nil
    }

    func toggle(_ url: URL) {
        refreshLocations()
        if let index = index(of: url) {
            favorites.remove(at: index)
        } else if let bookmark = try? url.bookmarkData() {
            favorites.insert(
                FavoriteDocument(id: UUID(), bookmark: bookmark, path: Self.normalizedPath(url), addedAt: Date()),
                at: 0
            )
        }
        save()
    }

    /// Resolves a favorite to its current location, following renames and moves.
    /// Deleted, trashed, and unreachable files resolve as missing.
    func resolve(_ favorite: FavoriteDocument) -> FavoriteResolution {
        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }) else { return .missing }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: favorites[index].bookmark,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.fileExists(atPath: url.path), !Self.isInTrash(url) else {
            return .missing
        }
        let path = Self.normalizedPath(url)
        var changed = false
        if favorites[index].path != path {
            favorites[index].path = path
            changed = true
        }
        if isStale, let renewed = try? url.bookmarkData() {
            favorites[index].bookmark = renewed
            changed = true
        }
        if changed { save() }
        return .available(url)
    }

    /// Updates stored locations of favorites that were renamed or moved.
    func refreshLocations() {
        for favorite in favorites { _ = resolve(favorite) }
    }

    func remove(_ favorite: FavoriteDocument) {
        favorites.removeAll { $0.id == favorite.id }
        save()
    }

    func clear() {
        favorites.removeAll()
        save()
    }

    /// The file name, plus its folder when another favorite has the same name.
    func displayName(for favorite: FavoriteDocument) -> String {
        let duplicates = favorites.filter { $0.name == favorite.name }.count > 1
        guard duplicates else { return favorite.name }
        let folder = ((favorite.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        return "\(favorite.name) — \(folder)"
    }

    private func index(of url: URL) -> Int? {
        let path = Self.normalizedPath(url)
        return favorites.firstIndex { $0.path == path }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        defaults.set(data, forKey: key)
    }

    static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }
}
