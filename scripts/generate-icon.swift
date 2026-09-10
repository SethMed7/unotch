import AppKit
import Foundation

// Renders the app icon from the brand geometry in brand/logo/icon.svg
// (1024 grid, charcoal tile, paper screen, mint side notch). brand/BRAND.md is canon.

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift generate-icon.swift <AppIcon.iconset>\n", stderr)
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func scaled(_ value: CGFloat, by scale: CGFloat) -> CGFloat { value * scale }

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
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
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

    let scale = CGFloat(pixels) / 1024
    let tile = NSBezierPath(
        roundedRect: NSRect(
            x: scaled(48, by: scale),
            y: scaled(48, by: scale),
            width: scaled(928, by: scale),
            height: scaled(928, by: scale)
        ),
        xRadius: scaled(205, by: scale),
        yRadius: scaled(205, by: scale)
    )
    NSColor(red: 0.082, green: 0.098, blue: 0.106, alpha: 1).setFill()
    tile.fill()

    let screen = NSBezierPath(
        roundedRect: NSRect(
            x: scaled(176, by: scale), y: scaled(256, by: scale),
            width: scaled(672, by: scale), height: scaled(512, by: scale)
        ),
        xRadius: scaled(80, by: scale), yRadius: scaled(80, by: scale)
    )
    screen.lineWidth = scaled(64, by: scale)
    NSColor(red: 244.0 / 255, green: 247.0 / 255, blue: 246.0 / 255, alpha: 1).setStroke()
    screen.stroke()

    // AppKit's y axis is inverted relative to the SVG's top-left origin.
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: x * scale, y: (1024 - y) * scale)
    }
    let notch = NSBezierPath()
    notch.move(to: p(144, 392))
    notch.line(to: p(280, 392))
    notch.curve(to: p(336, 448), controlPoint1: p(311, 392), controlPoint2: p(336, 417))
    notch.line(to: p(336, 576))
    notch.curve(to: p(280, 632), controlPoint1: p(336, 607), controlPoint2: p(311, 632))
    notch.line(to: p(144, 632))
    notch.close()
    NSColor(red: 59.0 / 255, green: 226.0 / 255, blue: 155.0 / 255, alpha: 1).setFill()
    notch.fill()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

for variant in variants {
    let data = try renderIcon(pixels: variant.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(variant.name))
}
