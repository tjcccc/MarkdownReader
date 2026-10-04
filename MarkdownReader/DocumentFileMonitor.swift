// Watches the opened Markdown file so the reader re-renders after external edits.

import Foundation

@MainActor
final class DocumentFileMonitor {
    private let url: URL
    private var lastText: String
    private let onChange: @MainActor (String) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pendingRead: DispatchWorkItem?
    private var needsRewatch = false
    private var missingFileRetries = 0

    init(url: URL, currentText: String, onChange: @escaping @MainActor (String) -> Void) {
        self.url = url
        lastText = currentText
        self.onChange = onChange
    }

    func start() {
        watch()
    }

    func stop() {
        pendingRead?.cancel()
        pendingRead = nil
        needsRewatch = false
        source?.cancel()
        source = nil
    }

    /// Asynchronously yields the file's text each time it changes on disk.
    static func changes(of url: URL, currentText: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            let monitor = DocumentFileMonitor(url: url, currentText: currentText) { text in
                continuation.yield(text)
            }
            monitor.start()
            continuation.onTermination = { _ in
                Task { @MainActor in monitor.stop() }
            }
        }
    }

    private func watch() {
        source?.cancel()
        source = nil
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            // An atomic save can briefly remove the file; look again for a few
            // seconds, then stop until the document is reopened.
            missingFileRetries += 1
            if missingFileRetries <= 20 { scheduleRead(after: 0.25, rewatch: true) }
            return
        }
        missingFileRetries = 0
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let source = self.source else { return }
                // Editors that save atomically replace the file, so the old
                // descriptor stops receiving events and must be reopened.
                let replaced = !source.data.isDisjoint(with: [.delete, .rename, .revoke])
                self.scheduleRead(after: 0.1, rewatch: replaced)
            }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    private func scheduleRead(after delay: TimeInterval, rewatch: Bool) {
        pendingRead?.cancel()
        needsRewatch = needsRewatch || rewatch
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.needsRewatch {
                    self.needsRewatch = false
                    self.watch()
                }
                self.readIfChanged()
            }
        }
        pendingRead = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func readIfChanged() {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              text != lastText
        else { return }
        lastText = text
        onChange(text)
    }
}
