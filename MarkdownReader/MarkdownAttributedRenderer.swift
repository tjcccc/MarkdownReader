//
//  MarkdownAttributedRenderer.swift
//  MarkdownReader
//
//  Converts Markdown source into a single styled NSAttributedString so the whole
//  document can be displayed in one NSTextView with native, document-wide text
//  selection. Also extracts a heading table of contents with character ranges so
//  the sidebar can scroll the text view to a heading.
//
//  Rendering uses pure AppKit attributed-string features so selection flows
//  through everything: prose via styled runs, tables via NSTextTable, and images
//  via NSTextAttachment (resolved relative to the document's folder).
//

import AppKit
import Foundation

/// A heading entry for the sidebar outline. `range` points at the heading text
/// inside the rendered `NSAttributedString` so the text view can scroll to it.
struct TOCItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let level: Int
    let range: NSRange
}

/// The result of rendering a Markdown document.
struct RenderedMarkdown {
    let text: NSAttributedString
    let toc: [TOCItem]
}

enum MarkdownAttributedRenderer {

    // MARK: Styling constants

    private enum Style {
        static let bodySize: CGFloat = 17
        static let codeScale: CGFloat = 0.92
        static let lineSpacing: CGFloat = 4
        static let paragraphSpacing: CGFloat = 12
        static let indentStep: CGFloat = 24
        static let quoteIndent: CGFloat = 20
        static let codeIndent: CGFloat = 12
        static let maxImageWidth: CGFloat = 760

        static let headingSizes: [Int: CGFloat] = [1: 31, 2: 25, 3: 21, 4: 19, 5: 17, 6: 16]

        static let codeBackground = dynamicColor(
            light: NSColor(white: 0, alpha: 0.05),
            dark: NSColor(white: 1, alpha: 0.08)
        )
        static let quoteBackground = dynamicColor(
            light: NSColor(white: 0, alpha: 0.035),
            dark: NSColor(white: 1, alpha: 0.06)
        )
    }

    /// Per-block resolved styling shared by every run inside the block.
    private struct BlockStyle {
        var font: NSFont
        var color: NSColor
        var paragraphStyle: NSParagraphStyle
        var isCode: Bool
        var backgroundColor: NSColor?
        var listMarker: String?
        var isThematicBreak: Bool
    }

    /// A maximal run of adjacent runs that share the same block presentation intent.
    private struct Block {
        let intent: PresentationIntent?
        var runs: [AttributedString.Runs.Run]
    }

    /// Builds a shared NSTextTable for all cells of one parsed table.
    private final class TableAccumulator {
        let table: NSTextTable
        private var rowNumbers: [Int: Int] = [:]
        private var nextRow = 0

        init(columns: Int) {
            table = NSTextTable()
            table.numberOfColumns = max(1, columns)
            table.layoutAlgorithm = .automaticLayoutAlgorithm
        }

        func rowNumber(forKey key: Int) -> Int {
            if let existing = rowNumbers[key] { return existing }
            let assigned = nextRow
            rowNumbers[key] = assigned
            nextRow += 1
            return assigned
        }
    }

    // MARK: Public API

    static func render(_ markdown: String, baseURL: URL? = nil) -> RenderedMarkdown {
        let cleaned = stripHTMLComments(markdown)

        let parsed: AttributedString
        do {
            parsed = try AttributedString(
                markdown: cleaned,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return RenderedMarkdown(
                text: NSAttributedString(string: cleaned, attributes: bodyAttributes()),
                toc: []
            )
        }

        let output = NSMutableAttributedString()
        var toc: [TOCItem] = []
        var tables: [Int: TableAccumulator] = [:]
        var previousWasTable = false

        for block in groupIntoBlocks(parsed) {
            if let table = tableCell(block.intent) {
                appendTableCell(block, info: table, into: output, parsed: parsed, accumulators: &tables)
                previousWasTable = true
                continue
            }

            if previousWasTable {
                output.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))
                previousWasTable = false
            }

            if let intent = block.intent, isCodeBlock(intent) {
                appendCodeBlock(block, into: output, parsed: parsed)
                continue
            }

            appendBlock(block, into: output, parsed: parsed, baseURL: baseURL, toc: &toc)
        }

        return RenderedMarkdown(text: output, toc: toc)
    }

    // MARK: Block assembly

    private static func appendBlock(
        _ block: Block,
        into output: NSMutableAttributedString,
        parsed: AttributedString,
        baseURL: URL?,
        toc: inout [TOCItem]
    ) {
        let style = blockStyle(for: block.intent)
        let blockStart = output.length

        if style.isThematicBreak {
            output.append(NSAttributedString(
                string: String(repeating: "\u{2014}", count: 24),
                attributes: thematicBreakAttributes(style)
            ))
        }
        if let marker = style.listMarker {
            output.append(NSAttributedString(string: marker, attributes: baseAttributes(style)))
        }

        for run in block.runs {
            if let imageURL = run.imageURL {
                let alt = String(parsed[run.range].characters)
                output.append(imageAttachment(for: imageURL, altText: alt, baseURL: baseURL))
                continue
            }
            let text = String(parsed[run.range].characters)
            if text.isEmpty { continue }
            output.append(NSAttributedString(string: text, attributes: runAttributes(style, run: run)))
        }

        if let intent = block.intent, let level = headerLevel(intent) {
            let range = NSRange(location: blockStart, length: max(0, output.length - blockStart))
            let title = output.attributedSubstring(from: range).string
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                toc.append(TOCItem(id: toc.count, title: title, level: level, range: range))
            }
        }

        output.append(NSAttributedString(string: "\n", attributes: baseAttributes(style)))
    }

    /// Renders a fenced code block as one padded background box (an `NSTextBlock`
    /// shared across its lines), rather than a ragged per-glyph highlight.
    private static func appendCodeBlock(
        _ block: Block,
        into output: NSMutableAttributedString,
        parsed: AttributedString
    ) {
        let raw = block.runs.map { String(parsed[$0.range].characters) }.joined()
        let code = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))

        // Render as a single-cell NSTextTable: only table blocks (not plain
        // NSTextBlock) actually draw a background, and the cell fills uniformly
        // with even padding while wrapped lines stay indented inside the box.
        let table = NSTextTable()
        table.numberOfColumns = 1
        let cell = NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)
        cell.backgroundColor = Style.codeBackground
        cell.setWidth(14, type: .absoluteValueType, for: .padding)
        cell.setWidth(0, type: .absoluteValueType, for: .border)

        let paragraph = NSMutableParagraphStyle()
        paragraph.textBlocks = [cell]
        paragraph.lineSpacing = 4

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: round(Style.bodySize * Style.codeScale), weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        output.append(NSAttributedString(string: code + "\n", attributes: attributes))
        // Plain paragraph closes the table and adds a gap below the box.
        output.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))
    }

    private static func appendTableCell(
        _ block: Block,
        info: TableCellInfo,
        into output: NSMutableAttributedString,
        parsed: AttributedString,
        accumulators: inout [Int: TableAccumulator]
    ) {
        let accumulator: TableAccumulator
        if let existing = accumulators[info.tableIdentity] {
            accumulator = existing
        } else {
            accumulator = TableAccumulator(columns: info.columns)
            accumulators[info.tableIdentity] = accumulator
        }

        let rowNumber = accumulator.rowNumber(forKey: info.rowKey)
        let cellBlock = NSTextTableBlock(
            table: accumulator.table,
            startingRow: rowNumber,
            rowSpan: 1,
            startingColumn: info.column,
            columnSpan: 1
        )
        cellBlock.setBorderColor(.separatorColor)
        cellBlock.setWidth(1, type: .absoluteValueType, for: .border)
        cellBlock.setWidth(7, type: .absoluteValueType, for: .padding)

        let paragraph = NSMutableParagraphStyle()
        paragraph.textBlocks = [cellBlock]
        paragraph.lineSpacing = 2

        let cellFont: NSFont = info.isHeader
            ? .systemFont(ofSize: Style.bodySize, weight: .semibold)
            : .systemFont(ofSize: Style.bodySize)
        let cellStyle = BlockStyle(
            font: cellFont,
            color: .labelColor,
            paragraphStyle: paragraph,
            isCode: false,
            backgroundColor: nil,
            listMarker: nil,
            isThematicBreak: false
        )

        var appended = false
        for run in block.runs {
            let text = String(parsed[run.range].characters)
            if text.isEmpty { continue }
            output.append(NSAttributedString(string: text, attributes: runAttributes(cellStyle, run: run)))
            appended = true
        }
        if !appended {
            // Empty cells still need a paragraph so the grid keeps its shape.
            output.append(NSAttributedString(string: " ", attributes: baseAttributes(cellStyle)))
        }
        output.append(NSAttributedString(string: "\n", attributes: baseAttributes(cellStyle)))
    }

    // MARK: Images

    private static func imageAttachment(for imageURL: URL, altText: String, baseURL: URL?) -> NSAttributedString {
        if let image = loadImage(imageURL, baseURL: baseURL) {
            let attachment = NSTextAttachment()
            attachment.image = image
            let size = image.size
            let width = min(size.width, Style.maxImageWidth)
            let height = size.width > 0 ? size.height * (width / size.width) : size.height
            attachment.bounds = CGRect(x: 0, y: 0, width: width, height: height)

            let centered = NSMutableParagraphStyle()
            centered.alignment = .left
            centered.paragraphSpacing = Style.paragraphSpacing
            let result = NSMutableAttributedString(attachment: attachment)
            result.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: result.length))
            result.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))
            return result
        }

        // Fallback: a labelled placeholder so the reader still knows an image is here.
        let label = altText.isEmpty ? imageURL.lastPathComponent : altText
        var attributes = bodyAttributes()
        attributes[.foregroundColor] = NSColor.secondaryLabelColor
        return NSAttributedString(string: "🖼 \(label)\n", attributes: attributes)
    }

    private static func loadImage(_ imageURL: URL, baseURL: URL?) -> NSImage? {
        // Absolute file or already-resolvable URL.
        if imageURL.isFileURL, let image = NSImage(contentsOf: imageURL) { return image }

        // Resolve relative paths (e.g. "assets/urt.jpg") against the document folder.
        if let baseURL {
            let relative = imageURL.relativePath.isEmpty ? imageURL.absoluteString : imageURL.relativePath
            let resolved = URL(fileURLWithPath: relative, relativeTo: baseURL).standardizedFileURL
            if let image = NSImage(contentsOf: resolved) { return image }
        }
        return nil
    }

    // MARK: Block styling

    private static func blockStyle(for intent: PresentationIntent?) -> BlockStyle {
        guard let intent else { return bodyBlockStyle() }

        if isCodeBlock(intent) {
            let paragraph = makeParagraphStyle(lineSpacing: 4, indent: Style.codeIndent)
            return BlockStyle(
                font: .monospacedSystemFont(ofSize: round(Style.bodySize * Style.codeScale), weight: .regular),
                color: .labelColor,
                paragraphStyle: paragraph,
                isCode: true,
                backgroundColor: Style.codeBackground,
                listMarker: nil,
                isThematicBreak: false
            )
        }

        if let level = headerLevel(intent) {
            let size = Style.headingSizes[level] ?? Style.bodySize
            let weight: NSFont.Weight = level <= 2 ? .bold : .semibold
            let paragraph = makeParagraphStyle(lineSpacing: 2, paragraphSpacingBefore: 14)
            return BlockStyle(
                font: .systemFont(ofSize: size, weight: weight),
                color: .labelColor,
                paragraphStyle: paragraph,
                isCode: false,
                backgroundColor: nil,
                listMarker: nil,
                isThematicBreak: false
            )
        }

        if isThematicBreak(intent) {
            return BlockStyle(
                font: .systemFont(ofSize: Style.bodySize),
                color: .tertiaryLabelColor,
                paragraphStyle: makeParagraphStyle(),
                isCode: false,
                backgroundColor: nil,
                listMarker: nil,
                isThematicBreak: true
            )
        }

        if let list = listInfo(intent) {
            let indent = CGFloat(list.depth) * Style.indentStep
            let markerWidth: CGFloat = 28
            // The marker sits at `indent`; a tab advances to `indent + markerWidth`
            // where the text starts, and wrapped lines hang to the same column.
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = Style.lineSpacing
            paragraph.paragraphSpacing = Style.paragraphSpacing
            paragraph.firstLineHeadIndent = indent
            paragraph.headIndent = indent + markerWidth
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent + markerWidth)]
            paragraph.defaultTabInterval = markerWidth
            return BlockStyle(
                font: .systemFont(ofSize: Style.bodySize),
                color: .labelColor,
                paragraphStyle: paragraph,
                isCode: false,
                backgroundColor: nil,
                listMarker: list.marker,
                isThematicBreak: false
            )
        }

        if hasBlockquote(intent) {
            let paragraph = makeParagraphStyle(firstLineIndent: Style.quoteIndent, headIndent: Style.quoteIndent)
            return BlockStyle(
                font: .systemFont(ofSize: Style.bodySize),
                color: .secondaryLabelColor,
                paragraphStyle: paragraph,
                isCode: false,
                backgroundColor: Style.quoteBackground,
                listMarker: nil,
                isThematicBreak: false
            )
        }

        return bodyBlockStyle()
    }

    private static func bodyBlockStyle() -> BlockStyle {
        BlockStyle(
            font: .systemFont(ofSize: Style.bodySize),
            color: .labelColor,
            paragraphStyle: makeParagraphStyle(),
            isCode: false,
            backgroundColor: nil,
            listMarker: nil,
            isThematicBreak: false
        )
    }

    // MARK: Run (inline) styling

    private static func runAttributes(_ block: BlockStyle, run: AttributedString.Runs.Run) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: block.paragraphStyle
        ]

        var font = block.font
        var color = block.color

        if let background = block.backgroundColor {
            attributes[.backgroundColor] = background
        }

        let inline = run.inlinePresentationIntent ?? []
        if inline.contains(.code) && !block.isCode {
            font = .monospacedSystemFont(ofSize: round(block.font.pointSize * Style.codeScale), weight: .regular)
            attributes[.backgroundColor] = Style.codeBackground
        }

        font = applyingTraits(
            to: font,
            bold: inline.contains(.stronglyEmphasized),
            italic: inline.contains(.emphasized)
        )

        if inline.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        if let url = run.link {
            attributes[.link] = url
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            color = .linkColor
        }

        attributes[.font] = font
        attributes[.foregroundColor] = color
        return attributes
    }

    private static func baseAttributes(_ block: BlockStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: block.paragraphStyle,
            .font: block.font,
            .foregroundColor: block.color
        ]
        if let background = block.backgroundColor {
            attributes[.backgroundColor] = background
        }
        return attributes
    }

    private static func thematicBreakAttributes(_ block: BlockStyle) -> [NSAttributedString.Key: Any] {
        [
            .paragraphStyle: block.paragraphStyle,
            .font: NSFont.systemFont(ofSize: Style.bodySize),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
    }

    private static func bodyAttributes() -> [NSAttributedString.Key: Any] {
        baseAttributes(bodyBlockStyle())
    }

    // MARK: Block grouping

    private static func groupIntoBlocks(_ parsed: AttributedString) -> [Block] {
        var blocks: [Block] = []
        var previousIntent: PresentationIntent?
        var isFirst = true

        for run in parsed.runs {
            let intent = run.presentationIntent
            if isFirst || intent != previousIntent {
                blocks.append(Block(intent: intent, runs: [run]))
                isFirst = false
            } else {
                blocks[blocks.count - 1].runs.append(run)
            }
            previousIntent = intent
        }
        return blocks
    }

    // MARK: Intent inspection

    private struct TableCellInfo {
        let tableIdentity: Int
        let columns: Int
        let rowKey: Int
        let isHeader: Bool
        let column: Int
    }

    private static func tableCell(_ intent: PresentationIntent?) -> TableCellInfo? {
        guard let intent else { return nil }

        var tableIdentity: Int?
        var columns = 1
        var rowKey: Int?
        var isHeader = false
        var column = 0

        for component in intent.components {
            switch component.kind {
            case .table(let tableColumns):
                tableIdentity = component.identity
                columns = tableColumns.count
            case .tableHeaderRow:
                isHeader = true
                rowKey = component.identity
            case .tableRow:
                rowKey = component.identity
            case .tableCell(let columnIndex):
                column = columnIndex
            default:
                break
            }
        }

        guard let tableIdentity, let rowKey else { return nil }
        return TableCellInfo(tableIdentity: tableIdentity, columns: columns, rowKey: rowKey, isHeader: isHeader, column: column)
    }

    private static func headerLevel(_ intent: PresentationIntent) -> Int? {
        for component in intent.components {
            if case .header(let level) = component.kind { return level }
        }
        return nil
    }

    private static func isCodeBlock(_ intent: PresentationIntent) -> Bool {
        intent.components.contains { if case .codeBlock = $0.kind { return true } else { return false } }
    }

    private static func isThematicBreak(_ intent: PresentationIntent) -> Bool {
        intent.components.contains { if case .thematicBreak = $0.kind { return true } else { return false } }
    }

    private static func hasBlockquote(_ intent: PresentationIntent) -> Bool {
        intent.components.contains { if case .blockQuote = $0.kind { return true } else { return false } }
    }

    private static func listInfo(_ intent: PresentationIntent) -> (marker: String, depth: Int)? {
        var depth = 0
        var ordered = false
        var ordinal: Int?
        var sawList = false

        for component in intent.components {
            switch component.kind {
            case .orderedList:
                depth += 1; sawList = true; ordered = true
            case .unorderedList:
                depth += 1; sawList = true; ordered = false
            case .listItem(let value):
                ordinal = value
            default:
                break
            }
        }

        guard sawList else { return nil }
        let marker = ordered ? "\(ordinal ?? 1).\t" : "•\t"
        return (marker, max(depth, 1))
    }

    // MARK: Helpers

    private static func stripHTMLComments(_ markdown: String) -> String {
        markdown.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: "",
            options: .regularExpression
        )
    }

    private static func makeParagraphStyle(
        lineSpacing: CGFloat = Style.lineSpacing,
        paragraphSpacing: CGFloat = Style.paragraphSpacing,
        paragraphSpacingBefore: CGFloat = 0,
        firstLineIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        indent: CGFloat? = nil
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.paragraphSpacingBefore = paragraphSpacingBefore
        style.firstLineHeadIndent = indent ?? firstLineIndent
        style.headIndent = indent ?? headIndent
        return style
    }

    private static func applyingTraits(to font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        guard bold || italic else { return font }
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}

/// A light/dark adaptive color built from two static variants.
private func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }
}
