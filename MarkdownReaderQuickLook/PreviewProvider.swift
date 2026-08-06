//
//  PreviewProvider.swift
//  MarkdownReaderQuickLook
//

import Foundation
import OSLog
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.taojiachun.MarkdownReader.QuickLookPreview",
        category: "PreviewProvider"
    )

    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping (QLPreviewReply?, (any Error)?) -> Void
    ) {
        Self.logger.debug("Preparing Markdown preview")

        let hasSecurityScopedAccess = request.fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                request.fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: request.fileURL)
            guard let markdown = String(data: data, encoding: .utf8) else {
                throw PreviewError.unsupportedTextEncoding
            }

            let rendered = MarkdownHTMLRenderer.render(markdown)
            let document = MarkdownQuickLookHTMLDocument.make(bodyHTML: rendered.bodyHTML)
            Self.logger.debug("Prepared Markdown preview HTML")
            let reply = QLPreviewReply(
                dataOfContentType: .html,
                contentSize: CGSize(width: 900, height: 700)
            ) { _ in
                Self.logger.debug("Supplying HTML preview data")
                return Data(document.utf8)
            }
            reply.title = request.fileURL.lastPathComponent
            handler(reply, nil)
        } catch {
            Self.logger.error("Could not prepare preview: \(error.localizedDescription, privacy: .private)")
            handler(nil, error)
        }
    }
}

private enum PreviewError: LocalizedError {
    case unsupportedTextEncoding

    var errorDescription: String? {
        switch self {
        case .unsupportedTextEncoding:
            "MarkdownReader Quick Look supports UTF-8 Markdown files."
        }
    }
}
