// Draws the app icon (a white notch glyph on a black tile) and writes Resources/AppIcon.icns.
// Usage: swift Scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AlcoveRecreation-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    // Standard macOS icon grid: an 824pt tile centred on a 1024pt canvas.
    let unit = size / 1024
    let tile = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185 * unit, cornerHeight: 185 * unit, transform: nil)

    context.addPath(tilePath)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()

    // The notch glyph floats in the middle of the tile (same silhouette as the menu bar icon),
    // so it reads as a white notch on any background instead of a bite out of the tile.
    let width = 520 * unit, height = 210 * unit
    let ear = 40 * unit, corner = 84 * unit
    let left = tile.midX - width / 2, right = tile.midX + width / 2
    let top = tile.midY + height / 2, bottom = tile.midY - height / 2
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: left, y: top))
    notch.addQuadCurve(to: CGPoint(x: left + ear, y: top - ear), control: CGPoint(x: left + ear, y: top))
    notch.addLine(to: CGPoint(x: left + ear, y: bottom + corner))
    notch.addQuadCurve(to: CGPoint(x: left + ear + corner, y: bottom), control: CGPoint(x: left + ear, y: bottom))
    notch.addLine(to: CGPoint(x: right - ear - corner, y: bottom))
    notch.addQuadCurve(to: CGPoint(x: right - ear, y: bottom + corner), control: CGPoint(x: right - ear, y: bottom))
    notch.addLine(to: CGPoint(x: right - ear, y: top - ear))
    notch.addQuadCurve(to: CGPoint(x: right, y: top), control: CGPoint(x: right - ear, y: top))
    notch.closeSubpath()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    context.addPath(notch)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Hairline edge so the black tile still reads on a dark Dock or window.
    context.addPath(tilePath)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    context.setLineWidth(max(4 * unit, 0.5))
    context.strokePath()

    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
    return image.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
