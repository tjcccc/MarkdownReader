import AppKit
import SwiftUI

struct ReaderFindActions {
    let perform: (NSTextFinder.Action) -> Void
}

private struct ReaderFindActionsKey: FocusedValueKey {
    typealias Value = ReaderFindActions
}

extension FocusedValues {
    var readerFindActions: ReaderFindActions? {
        get { self[ReaderFindActionsKey.self] }
        set { self[ReaderFindActionsKey.self] = newValue }
    }
}

struct ReaderFindCommands: Commands {
    @FocusedValue(\.readerFindActions) private var actions

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                Button("Find…") { actions?.perform(.showFindInterface) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find Next") { actions?.perform(.nextMatch) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { actions?.perform(.previousMatch) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            .disabled(actions == nil)
        }
    }
}
