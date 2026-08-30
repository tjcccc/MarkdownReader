//
//  MarkdownFrontMatter.swift
//  MarkdownReaderShared
//
//  Recognizes YAML frontmatter at the very start of a Markdown document.
//

import Foundation

struct MarkdownFrontMatter: Equatable {
    let yaml: String?
    let markdown: String

    static func extract(from source: String) -> Self {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)

        guard !lines.isEmpty else {
            return Self(yaml: nil, markdown: source)
        }

        if lines[0].first == "\u{feff}" {
            lines[0].removeFirst()
        }

        guard lines[0].trimmingCharacters(in: .whitespaces) == "---",
              let closingIndex = lines.indices.dropFirst().first(where: {
                  let delimiter = lines[$0].trimmingCharacters(in: .whitespaces)
                  return delimiter == "---" || delimiter == "..."
              }),
              closingIndex > 1
        else {
            return Self(yaml: nil, markdown: source)
        }

        let yamlLines = lines[1..<closingIndex]
        guard yamlLines.contains(where: { looksLikeYAMLKey(String($0)) }) else {
            return Self(yaml: nil, markdown: source)
        }

        let yaml = yamlLines.joined(separator: "\n")
        let bodyStart = lines.index(after: closingIndex)
        let markdown = bodyStart < lines.endIndex
            ? lines[bodyStart...].joined(separator: "\n")
            : ""
        return Self(yaml: yaml, markdown: markdown)
    }

    private static func looksLikeYAMLKey(_ line: String) -> Bool {
        line.range(
            of: #"^\s*[A-Za-z0-9_-]+\s*:"#,
            options: .regularExpression
        ) != nil
    }
}
