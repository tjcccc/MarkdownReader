//
//  ReaderMenuCleanerTests.swift
//  MarkdownReaderTests
//

import AppKit
import Testing
@testable import MarkdownReader

@MainActor
private final class ActionSpy: NSObject {
    var pasteCount = 0
    @objc func paste(_ sender: Any?) { pasteCount += 1 }
}

@MainActor
struct ReaderMenuCleanerTests {
    private func item(_ title: String, _ action: String?, key: String = "") -> NSMenuItem {
        NSMenuItem(title: title, action: action.map { NSSelectorFromString($0) }, keyEquivalent: key)
    }

    private func visibleTitles(_ menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isHidden }.map { $0.isSeparatorItem ? "---" : $0.title }
    }

    @Test func fileMenuKeepsOnlyReaderCommands() {
        let file = NSMenu(title: "File")
        file.addItem(item("Open…", "openDocument:"))
        let recent = item("Open Recent", "submenuAction:")
        recent.submenu = NSMenu(title: "Open Recent")
        file.addItem(recent)
        file.addItem(.separator())
        for (title, action) in [
            ("Close", "performClose:"), ("Close All", "closeAll:"), ("Save", "saveDocument:"),
            ("Save As…", "saveDocumentAs:"), ("Duplicate", "duplicateDocument:"),
            ("Rename…", "renameDocument:"), ("Move To…", "moveDocument:"),
        ] {
            file.addItem(item(title, action))
        }
        let revert = item("Revert To", "submenuAction:")
        revert.submenu = NSMenu(title: "Revert To")
        file.addItem(revert)
        file.addItem(.separator())
        let share = item("Share", "submenuAction:")
        share.submenu = NSMenu(title: "Share")
        file.addItem(share)

        ReaderMenuCleaner.clean(file)
        #expect(visibleTitles(file) == ["Open…", "Open Recent", "---", "Close", "Close All", "---", "Share"])
    }

    @Test func lateInsertedRevertMenuAfterCloseAllIsRemoved() {
        let file = NSMenu(title: "File")
        file.addItem(item("Close", "performClose:"))
        file.addItem(item("Close All", "closeAll:"))
        file.addItem(.separator())
        let share = item("Share", "submenuAction:")
        share.submenu = NSMenu(title: "Share")
        file.addItem(share)
        ReaderMenuCleaner.clean(file)

        // AppKit inserts Revert To after launch, once the save items are gone.
        let revert = item("Revert To", "submenuAction:")
        revert.submenu = NSMenu(title: "Revert To")
        file.insertItem(revert, at: 2)
        ReaderMenuCleaner.clean(file)
        #expect(visibleTitles(file) == ["Close", "Close All", "---", "Share"])
    }

    @Test func editingItemsAreHiddenButKeepTheirShortcuts() throws {
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", "undo:", key: "z"))
        edit.addItem(item("Redo", "redo:", key: "Z"))
        edit.addItem(.separator())
        edit.addItem(item("Cut", "cut:", key: "x"))
        edit.addItem(item("Copy", "copy:", key: "c"))
        let paste = item("Paste", "paste:", key: "v")
        let spy = ActionSpy()
        paste.target = spy
        edit.addItem(paste)
        edit.addItem(item("Delete", "delete:"))
        edit.addItem(item("Select All", "selectAll:", key: "a"))

        ReaderMenuCleaner.clean(edit)
        #expect(visibleTitles(edit) == ["Copy", "Select All"])
        #expect(paste.isHidden && paste.allowsKeyEquivalentWhenHidden)

        let commandV = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "v",
            charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9
        ))
        #expect(edit.performKeyEquivalent(with: commandV))
        #expect(spy.pasteCount == 1)
    }

    @Test func windowTabbingIsDisabled() {
        #expect(!NSWindow.allowsAutomaticWindowTabbing)
    }
}
