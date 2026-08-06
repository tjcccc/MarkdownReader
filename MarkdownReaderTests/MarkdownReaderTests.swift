//
//  MarkdownReaderTests.swift
//  MarkdownReaderTests
//
//  Created by taojiachun on 2024-12-02.
//

import Foundation
import Testing

struct MarkdownReaderTests {
    @Test func appRegistersMarkdownAsAViewableDocumentType() throws {
        let documentTypes = try #require(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes")
                as? [[String: Any]]
        )
        let markdownDocumentType = try #require(documentTypes.first { documentType in
            let contentTypes = documentType["LSItemContentTypes"] as? [String]
            return contentTypes?.contains("net.daringfireball.markdown") == true
        })

        #expect(markdownDocumentType["CFBundleTypeRole"] as? String == "Viewer")

        let importedTypes = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UTImportedTypeDeclarations")
                as? [[String: Any]]
        )
        let markdownDeclaration = try #require(importedTypes.first { declaration in
            declaration["UTTypeIdentifier"] as? String == "net.daringfireball.markdown"
        })
        let tags = try #require(markdownDeclaration["UTTypeTagSpecification"] as? [String: Any])
        let filenameExtensions = try #require(tags["public.filename-extension"] as? [String])

        #expect(Set(filenameExtensions) == Set(["md", "markdown"]))
        #expect(filenameExtensions.allSatisfy { !$0.hasPrefix(".") })
    }
}
