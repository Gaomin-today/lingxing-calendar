#!/usr/bin/env swift
import AppKit
import Foundation

// A deterministic, entirely native illustration. Run from the project root:
// swift -module-cache-path /tmp/lingxing-icon-cache scripts/make-icon.swift
// No fonts, external images, window server, or network access are required.

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillGradient(_ context: CGContext, path: CGPath, colors: [CGColor], start: CGPoint, end: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

func renderIcon(pixels: Int) throws -> Data {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    // Use the top-left origin for easily inspectable illustration coordinates.
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    context.setAllowsAntialiasing(true)

    // Warm porcelain edge with restrained depth, within standard macOS icon margins.
    let tile = rounded(CGRect(x: 62, y: 58, width: 900, height: 900), 205)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 25, color: color(0x203D31, alpha: 0.20))
    context.setFillColor(color(0xF7F4E9))
    context.addPath(tile)
    context.fillPath()
    context.restoreGState()

    let jadeTile = rounded(CGRect(x: 84, y: 80, width: 856, height: 856), 187)
    fillGradient(context, path: jadeTile, colors: [color(0x749780), color(0x3F6856), color(0x31513F)],
                 start: CGPoint(x: 200, y: 90), end: CGPoint(x: 750, y: 990))
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.13))
    context.setLineWidth(2)
    context.addPath(jadeTile)
    context.strokePath()

    // A single softly engraved ring recalls the cycle of seasons without extra symbols.
    if pixels >= 128 {
        context.setStrokeColor(color(0xE2E9CB, alpha: 0.12))
        context.setLineWidth(3)
        context.strokeEllipse(in: CGRect(x: 137, y: 135, width: 750, height: 750))
    }

    // The rounded seed spirit sits lightly above its grounding shadow.
    context.saveGState()
    context.setShadow(offset: .zero, blur: 22, color: color(0x132C1E, alpha: 0.20))
    context.setFillColor(color(0x213E2A, alpha: 0.24))
    context.fillEllipse(in: CGRect(x: 268, y: 767, width: 488, height: 66))
    context.restoreGState()

    let body = CGPath(ellipseIn: CGRect(x: 210, y: 300, width: 604, height: 510), transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -15), blur: 18, color: color(0x1C3827, alpha: 0.18))
    context.setFillColor(color(0xCBDDB8))
    context.addPath(body)
    context.fillPath()
    context.restoreGState()
    fillGradient(context, path: body, colors: [color(0xF2F2D9), color(0xDDE8C6), color(0xB7CFA8)],
                 start: CGPoint(x: 440, y: 300), end: CGPoint(x: 600, y: 830))
    context.addPath(body)
    context.setStrokeColor(color(0xF5F6E5, alpha: 0.35))
    context.setLineWidth(3)
    context.strokePath()

    // Short curved shoot and one broad, legible leaf: the same silhouette as SpiritView.
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: 504, y: 330))
    stem.addCurve(to: CGPoint(x: 527, y: 241), control1: CGPoint(x: 482, y: 289), control2: CGPoint(x: 493, y: 263))
    context.addPath(stem)
    context.setStrokeColor(color(0x253F2B))
    context.setLineWidth(pixels <= 32 ? 22 : 18)
    context.setLineCap(.round)
    context.strokePath()

    let leaf = CGMutablePath()
    leaf.move(to: CGPoint(x: 512, y: 256))
    leaf.addCurve(to: CGPoint(x: 688, y: 177), control1: CGPoint(x: 521, y: 179), control2: CGPoint(x: 634, y: 164))
    leaf.addCurve(to: CGPoint(x: 512, y: 256), control1: CGPoint(x: 675, y: 263), control2: CGPoint(x: 582, y: 297))
    leaf.closeSubpath()
    fillGradient(context, path: leaf, colors: [color(0xD1DCA0), color(0xAAC887)],
                 start: CGPoint(x: 606, y: 175), end: CGPoint(x: 570, y: 279))
    if pixels >= 64 {
        let vein = CGMutablePath()
        vein.move(to: CGPoint(x: 532, y: 251))
        vein.addQuadCurve(to: CGPoint(x: 655, y: 197), control: CGPoint(x: 589, y: 222))
        context.addPath(vein)
        context.setStrokeColor(color(0x789D68, alpha: 0.65))
        context.setLineWidth(5)
        context.strokePath()
    }

    // Eyes retain comfortable spacing even in the 16 px representation.
    context.setFillColor(color(0x2D4939))
    for x in [CGFloat(395), CGFloat(596)] {
        context.addPath(rounded(CGRect(x: x, y: 505, width: 31, height: 48), 15.5))
        context.fillPath()
    }
    context.setFillColor(color(0xBE8169, alpha: 0.37))
    context.fillEllipse(in: CGRect(x: 324, y: 573, width: 86, height: 31))
    context.fillEllipse(in: CGRect(x: 614, y: 573, width: 86, height: 31))

    let smile = CGMutablePath()
    smile.move(to: CGPoint(x: 481, y: 586))
    smile.addQuadCurve(to: CGPoint(x: 543, y: 586), control: CGPoint(x: 512, y: 621))
    context.addPath(smile)
    context.setStrokeColor(color(0x3F5B43))
    context.setLineWidth(pixels <= 32 ? 13 : 9)
    context.strokePath()

    let image = context.makeImage()!
    let representation = NSBitmapImageRep(cgImage: image)
    guard let png = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "LingxingIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot encode icon PNG"])
    }
    return png
}

let slots = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in slots {
    try renderIcon(pixels: size).write(to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil could not package the images in this execution environment. The complete PNG iconset is available at \(iconset.path). Re-run iconutil from a normal macOS Terminal if sandbox restrictions caused this failure.\n".utf8))
    exit(process.terminationStatus)
}
print("Generated Resources/AppIcon.icns and all 10 iconset representations (16–1024 px).")
