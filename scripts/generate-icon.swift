#!/usr/bin/env swift
// Renders the app icon and launch image into App/Assets.xcassets.
//
//     swift scripts/generate-icon.swift
//
// The art: a dark aurora (violet, teal, pink) with a frosted glass tile carrying 活
// (from 活用, "conjugation"). Everything is drawn with CoreGraphics and CoreText so the
// icon can be regenerated and tweaked without a design tool.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("App/Assets.xcassets")

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha]
    )!
}

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    return ctx
}

func write(_ ctx: CGContext, to url: URL) throws {
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 1) }
}

/// A soft blob of colour: opaque in the middle, transparent at `radius`.
func blob(_ ctx: CGContext, at center: CGPoint, radius: CGFloat, hex: UInt32, alpha: CGFloat = 1) {
    let gradient = CGGradient(
        colorsSpace: space,
        // A gaussian-like falloff, so no blob has a visible edge.
        colors: [1.0, 0.78, 0.46, 0.2, 0.06, 0].map { color(hex, alpha * $0) } as CFArray,
        locations: [0, 0.2, 0.42, 0.65, 0.85, 1]
    )!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// The aurora, laid out in unit coordinates (0,0 bottom-left to 1,1 top-right) of `rect`.
func aurora(_ ctx: CGContext, in rect: CGRect) {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
    let r = min(rect.width, rect.height)
    blob(ctx, at: p(0.22, 0.80), radius: r * 0.60, hex: 0x8A5BFF)   // violet, top left
    blob(ctx, at: p(0.84, 0.74), radius: r * 0.54, hex: 0x23D5C3)   // teal, top right
    blob(ctx, at: p(0.50, 0.08), radius: r * 0.58, hex: 0xFF5FA2, alpha: 0.9)   // pink, bottom
}

func tilePath(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.width * 0.26, cornerHeight: rect.width * 0.26, transform: nil)
}

func glyph(_ text: String, size: CGFloat, weight: String, color hex: UInt32, in rect: CGRect, ctx: CGContext, dy: CGFloat = 0) {
    let font = CTFontCreateWithName(weight as CFString, size, nil)
    let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color(hex)]
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.saveGState()
    ctx.textPosition = CGPoint(x: rect.midX - bounds.midX, y: rect.midY - bounds.midY + dy)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

/// The frosted glass tile with the 活 glyph on it.
func glassTile(_ ctx: CGContext, rect: CGRect) {
    let path = tilePath(rect)
    let u = rect.width / 100   // one "percent" of the tile

    // Soft shadow around the tile, drawn only outside it so the glass stays clear.
    ctx.saveGState()
    ctx.addRect(rect.insetBy(dx: -rect.width, dy: -rect.height))
    ctx.addPath(path)
    ctx.clip(using: .evenOdd)
    ctx.setShadow(offset: CGSize(width: 0, height: -u * 5), blur: u * 12, color: color(0x000000, 0.38))
    ctx.addPath(path)
    ctx.setFillColor(color(0x000000, 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Glass body: a diagonal wash of white, strongest top left.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let body = CGGradient(
        colorsSpace: space,
        colors: [color(0xFFFFFF, 0.46), color(0xFFFFFF, 0.14)] as CFArray, locations: [0, 1]
    )!
    ctx.drawLinearGradient(body, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    // Specular sheen across the upper half.
    let sheen = CGGradient(
        colorsSpace: space,
        colors: [color(0xFFFFFF, 0.38), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        sheen,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY + rect.height * 0.35),
        options: []
    )

    // Thin inner highlight along the top edge.
    ctx.setStrokeColor(color(0xFFFFFF, 0.7))
    ctx.setLineWidth(u * 1.6)
    ctx.addPath(tilePath(rect.insetBy(dx: u * 0.8, dy: u * 0.8)))
    ctx.strokePath()
    ctx.restoreGState()

    // Crisp rim.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(color(0xFFFFFF, 0.6))
    ctx.setLineWidth(u * 1.4)
    ctx.strokePath()
    ctx.restoreGState()

    // The glyph, with a faint shadow so it lifts off the glass.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -u * 2.4), blur: u * 5, color: color(0x1B1050, 0.35))
    glyph("活", size: rect.width * 0.8, weight: "HiraginoSans-W8", color: 0xFFFFFF, in: rect, ctx: ctx, dy: -rect.width * 0.015)
    ctx.restoreGState()
}

// MARK: iOS icon: full-bleed 1024 square (the system applies the corner mask).

func iosIcon() -> CGContext {
    let size = 1024
    let ctx = makeContext(size, size)
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.setFillColor(color(0x0B1026))
    ctx.fill(full)
    aurora(ctx, in: full)
    glassTile(ctx, rect: CGRect(x: 1024 * 0.20, y: 1024 * 0.20, width: 1024 * 0.60, height: 1024 * 0.60))
    return ctx
}

// MARK: Mac icon: the same art in a rounded square inset on a transparent 1024 canvas.

func macIcon() -> CGContext {
    let size = 1024
    let ctx = makeContext(size, size)
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(0x000000, 0.4))
    ctx.addPath(path)
    ctx.setFillColor(color(0x0B1026))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.setFillColor(color(0x0B1026))
    ctx.fill(body)
    aurora(ctx, in: body)
    glassTile(ctx, rect: CGRect(x: body.minX + body.width * 0.20, y: body.minY + body.height * 0.20, width: body.width * 0.60, height: body.height * 0.60))
    ctx.restoreGState()
    return ctx
}

func scaled(_ source: CGContext, to size: Int) -> CGContext {
    let ctx = makeContext(size, size)
    ctx.draw(source.makeImage()!, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx
}

// MARK: Launch image: transparent PNG with a glow, the tile and the title. The
// launch background colour is the same navy, so the glow melts into it on any screen.

func launchImage(scale: Int) -> CGContext {
    let w = 360 * scale, h = 460 * scale
    let ctx = makeContext(w, h)
    let s = CGFloat(scale)
    let area = CGRect(x: 0, y: 0, width: w, height: h)

    // Aurora glow centred behind the tile, fading out before the edges.
    let tile = CGRect(x: (CGFloat(w) - 190 * s) / 2, y: 190 * s, width: 190 * s, height: 190 * s)
    blob(ctx, at: CGPoint(x: 125 * s, y: 335 * s), radius: 110 * s, hex: 0x8A5BFF, alpha: 0.85)
    blob(ctx, at: CGPoint(x: 240 * s, y: 320 * s), radius: 100 * s, hex: 0x23D5C3, alpha: 0.8)
    blob(ctx, at: CGPoint(x: 180 * s, y: 215 * s), radius: 110 * s, hex: 0xFF5FA2, alpha: 0.6)
    _ = area

    glassTile(ctx, rect: tile)

    // Title and tagline.
    glyph("早見表", size: 38 * s, weight: "HiraginoSans-W7", color: 0xFFFFFF, in: CGRect(x: 0, y: 112 * s, width: CGFloat(w), height: 44 * s), ctx: ctx)
    let tagline = CFAttributedStringCreate(nil, "VERB CONJUGATION" as CFString, [
        kCTFontAttributeName: CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 11 * s, nil),
        kCTForegroundColorAttributeName: color(0xFFFFFF, 0.72),
        kCTKernAttributeName: 3.2 * s,
    ] as CFDictionary)!
    let line = CTLineCreateWithAttributedString(tagline)
    let b = CTLineGetBoundsWithOptions(line, [])
    ctx.textPosition = CGPoint(x: (CGFloat(w) - b.width) / 2, y: 86 * s)
    CTLineDraw(line, ctx)
    return ctx
}

// MARK: Write everything.

let iconSet = assets.appendingPathComponent("AppIcon.appiconset")
try write(iosIcon(), to: iconSet.appendingPathComponent("icon-1024.png"))

let mac = macIcon()
for (name, px) in [
    ("mac-16.png", 16), ("mac-16@2x.png", 32), ("mac-32.png", 32), ("mac-32@2x.png", 64),
    ("mac-128.png", 128), ("mac-128@2x.png", 256), ("mac-256.png", 256), ("mac-256@2x.png", 512),
    ("mac-512.png", 512), ("mac-512@2x.png", 1024),
] {
    try write(px == 1024 ? mac : scaled(mac, to: px), to: iconSet.appendingPathComponent(name))
}

let launchSet = assets.appendingPathComponent("LaunchImage.imageset")
for scale in 1...3 {
    try write(launchImage(scale: scale), to: launchSet.appendingPathComponent("launch-image@\(scale)x.png"))
}
print("wrote icon and launch image into \(assets.path)")
