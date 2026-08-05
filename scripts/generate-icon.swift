#!/usr/bin/env swift
// Renders a full-bleed navy app icon with a crisp SF Symbol (no letterboxing).
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Assets")
let iconset = assets.appendingPathComponent("AppIcon.iconset")

let navyTop = NSColor(red: 0.10, green: 0.14, blue: 0.28, alpha: 1)
let navyBottom = NSColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1)

let iconSizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func drawIcon(pixels: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer {
        NSGraphicsContext.restoreGraphicsState()
    }

    // Subtle navy gradient — full canvas, macOS applies squircle mask in Dock.
    if let ctx = NSGraphicsContext.current?.cgContext {
        let colors = [navyTop.cgColor, navyBottom.cgColor] as CFArray
        let space = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: CGFloat(pixels)),
                end: CGPoint(x: CGFloat(pixels), y: 0),
                options: []
            )
        }
    }

    // Soft top highlight for depth (Apple-style, very subtle).
    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.10),
        NSColor.white.withAlphaComponent(0),
    ])
    highlight?.draw(in: NSRect(x: 0, y: CGFloat(pixels) * 0.55, width: CGFloat(pixels), height: CGFloat(pixels) * 0.45), angle: 90)

    // White drive glyph — palette config keeps edges anti-aliased at every size.
    let pointSize = CGFloat(pixels) * 0.46
    let palette = NSImage.SymbolConfiguration(paletteColors: [.white])
    let sizing = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    let config = palette.applying(sizing)

    guard let base = NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: "Stoguard"),
          let symbol = base.withSymbolConfiguration(config) else {
        return rep
    }

    let symSize = symbol.size
    let inset = CGFloat(pixels) * 0.06
    let maxSide = CGFloat(pixels) - inset * 2
    let scale = min(maxSide / symSize.width, maxSide / symSize.height, 1)
    let w = symSize.width * scale
    let h = symSize.height * scale
    let x = (CGFloat(pixels) - w) / 2
    let y = (CGFloat(pixels) - h) / 2 - CGFloat(pixels) * 0.02 // optical center nudge

    symbol.draw(in: NSRect(x: x, y: y, width: w, height: h))

    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try data.write(to: url)
}

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for entry in iconSizes {
    guard let rep = drawIcon(pixels: entry.px) else {
        fputs("Failed to render \(entry.name)\n", stderr)
        exit(1)
    }
    let out = iconset.appendingPathComponent(entry.name)
    try writePNG(rep, to: out)
    print("wrote \(entry.name)")
}

// Master 1024 for preview / marketing
if let master = drawIcon(pixels: 1024) {
    try writePNG(master, to: assets.appendingPathComponent("icon-1024.png"))
    print("wrote icon-1024.png")
}

// Build .icns
let icnsPath = assets.appendingPathComponent("AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icnsPath.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
print("wrote AppIcon.icns")
