//
//  FavoritesStoreTests.swift
//  MarkdownReaderTests
//

import Foundation
import Testing
@testable import MarkdownReader

@MainActor
@Suite(.serialized)
struct FavoritesStoreTests {
    private let folder: URL
    private let suiteName = "MarkdownReaderFavoritesTests-\(UUID().uuidString)"

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownReaderFavorites-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func makeStore() -> FavoritesStore {
        FavoritesStore(defaults: UserDefaults(suiteName: suiteName)!, key: "favorites")
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func document(_ name: String, in directory: URL? = nil) throws -> URL {
        let url = (directory ?? folder).appendingPathComponent(name)
        try Data("# \(name)".utf8).write(to: url)
        return url
    }

    @Test func togglingAddsNewestFirstAndRemoves() throws {
        defer { cleanUp() }
        let store = makeStore()
        let first = try document("first.md")
        let second = try document("second.md")

        store.toggle(first)
        store.toggle(second)
        #expect(store.favorites.map(\.name) == ["second.md", "first.md"])
        #expect(store.isFavorite(first) && store.isFavorite(second))

        store.toggle(first)
        #expect(store.favorites.map(\.name) == ["second.md"])
        #expect(!store.isFavorite(first))
        #expect(!store.isFavorite(nil))
    }

    @Test func favoritesPersistAcrossLaunches() throws {
        defer { cleanUp() }
        let url = try document("kept.md")
        makeStore().toggle(url)
        let relaunched = makeStore()
        #expect(relaunched.favorites.map(\.name) == ["kept.md"])
        #expect(relaunched.isFavorite(url))
    }

    @Test func renamedAndMovedFilesStayFavorites() throws {
        defer { cleanUp() }
        let store = makeStore()
        let original = try document("draft.md")
        store.toggle(original)

        let renamed = folder.appendingPathComponent("final.md")
        try FileManager.default.moveItem(at: original, to: renamed)
        let favorite = try #require(store.favorites.first)
        guard case .available(let resolved) = store.resolve(favorite) else {
            Issue.record("renamed favorite did not resolve")
            return
        }
        #expect(FavoritesStore.normalizedPath(resolved) == FavoritesStore.normalizedPath(renamed))
        #expect(store.isFavorite(renamed))
        #expect(store.favorites.first?.name == "final.md")

        let subfolder = folder.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let moved = subfolder.appendingPathComponent("final.md")
        try FileManager.default.moveItem(at: renamed, to: moved)
        store.refreshLocations()
        #expect(store.isFavorite(moved))
    }

    @Test func deletedAndTrashedFilesResolveAsMissing() throws {
        defer { cleanUp() }
        let store = makeStore()
        let deleted = try document("deleted.md")
        let trashed = try document("trashed.md")
        store.toggle(deleted)
        store.toggle(trashed)

        try FileManager.default.removeItem(at: deleted)
        var trashURL: NSURL?
        try FileManager.default.trashItem(at: trashed, resultingItemURL: &trashURL)
        defer { if let trashURL { try? FileManager.default.removeItem(at: trashURL as URL) } }

        for favorite in store.favorites {
            #expect(store.resolve(favorite) == .missing, "\(favorite.name)")
        }
        let missing = try #require(store.favorites.first)
        store.remove(missing)
        #expect(store.favorites.count == 1)
        store.clear()
        #expect(store.favorites.isEmpty)
    }

    @Test func duplicateNamesShowTheirFolder() throws {
        defer { cleanUp() }
        let store = makeStore()
        let other = folder.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        store.toggle(try document("README.md"))
        store.toggle(try document("README.md", in: other))
        store.toggle(try document("unique.md"))

        let names = store.favorites.map(store.displayName(for:))
        #expect(names == ["unique.md", "README.md — other", "README.md — \(folder.lastPathComponent)"])
    }
}
