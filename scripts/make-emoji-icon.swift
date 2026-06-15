#!/usr/bin/env swift
//
// make-emoji-icon.swift
//
// Renders an Apple color emoji onto a macOS-style rounded-square background and
// writes a PNG at the requested pixel size. Run once per size to populate the
// app icon set. Uses Core Text via AppKit so color emoji render correctly.
//
// Usage:
//   swift make-emoji-icon.swift <emoji> <output.png> <sizePx>
// Example:
//   swift make-emoji-icon.swift 📒 icon_1024.png 1024
//
// To restyle the icon, change the emoji, gradient colors, or sizes below.
//

import AppKit

let args = CommandLine.arguments
let emoji = args.count > 1 ? args[1] : "📒"
let outPath = args.count > 2 ? args[2] : "icon_1024.png"
let pixels = args.count > 3 ? (Int(args[3]) ?? 1024) : 1024

let dim = CGFloat(pixels)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels, pixelsHigh: pixels,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Could not create bitmap rep") }
rep.size = NSSize(width: dim, height: dim)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// The icon is the emoji itself on a transparent background (no squircle), so
// there is no white box behind it. `body` defines the drawable area used to size
// the emoji; set `drawBackground = true` if a filled rounded square is wanted.
let margin = dim * (100.0 / 1024.0)
let body = NSRect(x: margin, y: margin, width: dim - 2 * margin, height: dim - 2 * margin)

let drawBackground = false
if drawBackground {
    let radius = body.width * (185.0 / 824.0)
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    let top = NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.00, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.85, green: 0.88, blue: 0.94, alpha: 1)
    (NSGradient(starting: top, ending: bottom) ?? NSGradient(colors: [top])!).draw(in: path, angle: -90)
}

// Centered emoji. Multiplier controls how much of the icon the emoji fills
// (emoji glyphs render smaller than their point size, so this is > 1).
let fontSize = body.width * 1.02
let font = NSFont(name: "Apple Color Emoji", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
let string = NSAttributedString(string: emoji, attributes: [.font: font])
let textSize = string.size()
let origin = NSPoint(x: (dim - textSize.width) / 2, y: (dim - textSize.height) / 2)
string.draw(at: origin)

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("Could not encode PNG") }
do {
    try data.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath) (\(pixels)px)")
} catch {
    fatalError("Could not write \(outPath): \(error)")
}
