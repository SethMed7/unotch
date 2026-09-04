import AppKit
import Foundation

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

    let mark = NSBezierPath()
    mark.lineWidth = scaled(84, by: scale)
    mark.lineCapStyle = .round
    mark.move(to: NSPoint(x: scaled(310, by: scale), y: scaled(716, by: scale)))
    mark.line(to: NSPoint(x: scaled(310, by: scale), y: scaled(466, by: scale)))
    mark.curve(
        to: NSPoint(x: scaled(714, by: scale), y: scaled(466, by: scale)),
        controlPoint1: NSPoint(x: scaled(310, by: scale), y: scaled(264, by: scale)),
        controlPoint2: NSPoint(x: scaled(714, by: scale), y: scaled(264, by: scale))
    )
    mark.line(to: NSPoint(x: scaled(714, by: scale), y: scaled(716, by: scale)))
    NSColor(red: 0.96, green: 0.97, blue: 0.97, alpha: 1).setStroke()
    mark.stroke()

    let status = NSBezierPath(
        ovalIn: NSRect(
            x: scaled(675, by: scale),
            y: scaled(729, by: scale),
            width: scaled(78, by: scale),
            height: scaled(78, by: scale)
        )
    )
    NSColor(red: 0.231, green: 0.886, blue: 0.608, alpha: 1).setFill()
    status.fill()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

for variant in variants {
    let data = try renderIcon(pixels: variant.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(variant.name))
}
