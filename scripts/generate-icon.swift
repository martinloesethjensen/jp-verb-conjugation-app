#!/usr/bin/env swift
// Renders the launch screen and the default iOS app icon into App/Assets.xcassets, and writes
// the 活 outline as App/Launch/SealGlyph.swift so the app's first frame draws the same glyph.
//
//     swift scripts/generate-icon.swift --font <ShipporiMinchoB1-Bold.ttf> [repo-root]
//
// The art is the seal from the paper-and-ink design: 活 (from 活用, "conjugation") in Mincho
// ink inside a stamp: the teacher's red circle in Light, a sumi brush circle in Dark. Everything
// is drawn in one 120-unit box: 活 at an em of 60 with its bounding box centred, the stamp
// scaled 0.84 about the centre, strokes at the board's width × 1.8. The font is used only here;
// it is never committed or bundled (SIL Open Font License 1.1).
// Mac icons are parked and left as they are.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fontURL = "https://github.com/google/fonts/raw/main/ofl/shipporiminchob1/ShipporiMinchoB1-Bold.ttf"
var args = Array(CommandLine.arguments.dropFirst())
guard let flag = args.firstIndex(of: "--font"), flag + 1 < args.count else {
    FileHandle.standardError.write("""
    usage: swift scripts/generate-icon.swift --font <ShipporiMinchoB1-Bold.ttf> [repo-root]
    Download the font (SIL Open Font License 1.1) from:
      \(fontURL)

    """.data(using: .utf8)!)
    exit(1)
}
let fontPath = args[flag + 1]
args.removeSubrange(flag...(flag + 1))
let root = URL(fileURLWithPath: args.first ?? FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("App/Assets.xcassets")
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha,
    ])!
}

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

func write(_ ctx: CGContext, to url: URL) throws {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 1) }
}

// MARK: The glyph, in the 120-unit box, y down, rounded to 0.01.

enum Step {
    case move(CGPoint), line(CGPoint), quad(CGPoint, CGPoint), cubic(CGPoint, CGPoint, CGPoint), close
}

func round2(_ p: CGPoint) -> CGPoint {
    CGPoint(x: (p.x * 100).rounded() / 100, y: (p.y * 100).rounded() / 100)
}

func glyphSteps() -> [Step] {
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: fontPath) as CFURL) as? [CTFontDescriptor],
          let descriptor = descriptors.first else {
        FileHandle.standardError.write("can't read a font from \(fontPath)\n".data(using: .utf8)!)
        exit(1)
    }
    let font = CTFontCreateWithFontDescriptor(descriptor, 60, nil)
    var chars: [UniChar] = Array("活".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count),
          let raw = CTFontCreatePathForGlyph(font, glyphs[0], nil) else {
        FileHandle.standardError.write("the font has no 活\n".data(using: .utf8)!)
        exit(1)
    }
    // Flip to y-down and centre the bounding box on (60, 60).
    let box = raw.boundingBoxOfPath
    var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 60 - box.midX, ty: 60 + box.midY)
    let path = raw.copy(using: &flip)!
    var steps: [Step] = []
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: steps.append(.move(round2(e.points[0])))
        case .addLineToPoint: steps.append(.line(round2(e.points[0])))
        case .addQuadCurveToPoint: steps.append(.quad(round2(e.points[1]), round2(e.points[0])))
        case .addCurveToPoint: steps.append(.cubic(round2(e.points[2]), round2(e.points[0]), round2(e.points[1])))
        case .closeSubpath: steps.append(.close)
        @unknown default: break
        }
    }
    return steps
}

let glyph = glyphSteps()

func glyphPath() -> CGPath {
    let p = CGMutablePath()
    for step in glyph {
        switch step {
        case let .move(to): p.move(to: to)
        case let .line(to): p.addLine(to: to)
        case let .quad(to, c): p.addQuadCurve(to: to, control: c)
        case let .cubic(to, c1, c2): p.addCurve(to: to, control1: c1, control2: c2)
        case .close: p.closeSubpath()
        }
    }
    return p
}

// MARK: The two default stamps, in absolute box units. Same data as VerbKit's
// StampShape.teacher / .sumi (this script can't import VerbKit).

func teacherPath() -> CGPath {
    // M60 10C87 9 110 31 109 60c-1 28-23 50-51 49C31 108 10 87 11 59 12 34 31 14 57 11
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 60, y: 10))
    p.addCurve(to: CGPoint(x: 109, y: 60), control1: CGPoint(x: 87, y: 9), control2: CGPoint(x: 110, y: 31))
    p.addCurve(to: CGPoint(x: 58, y: 109), control1: CGPoint(x: 108, y: 88), control2: CGPoint(x: 86, y: 110))
    p.addCurve(to: CGPoint(x: 11, y: 59), control1: CGPoint(x: 31, y: 108), control2: CGPoint(x: 10, y: 87))
    p.addCurve(to: CGPoint(x: 57, y: 11), control1: CGPoint(x: 12, y: 34), control2: CGPoint(x: 31, y: 14))
    return p
}

func sumiPath() -> CGPath {
    // M98 34C88 16 70 9 52 12 28 16 12 38 14 62s22 44 46 46c22 2 40-10 47-30
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 98, y: 34))
    p.addCurve(to: CGPoint(x: 52, y: 12), control1: CGPoint(x: 88, y: 16), control2: CGPoint(x: 70, y: 9))
    p.addCurve(to: CGPoint(x: 14, y: 62), control1: CGPoint(x: 28, y: 16), control2: CGPoint(x: 12, y: 38))
    p.addCurve(to: CGPoint(x: 60, y: 108), control1: CGPoint(x: 16, y: 86), control2: CGPoint(x: 36, y: 106))
    p.addCurve(to: CGPoint(x: 107, y: 78), control1: CGPoint(x: 82, y: 110), control2: CGPoint(x: 100, y: 98))
    return p
}

struct Look {
    let paper: CGColor?
    let stamp: CGPath
    let stampWidth: CGFloat   // the board's base width
    let stampColor: CGColor
    let ink: CGColor
}

let light = Look(paper: color(0xF6F7F4), stamp: teacherPath(), stampWidth: 3, stampColor: color(0xC2372B), ink: color(0x1E2633))
let dark = Look(paper: color(0x14171C), stamp: sumiPath(), stampWidth: 7, stampColor: color(0xE9EBE6), ink: color(0xE9EBE6))
let tinted = Look(paper: color(0x000000), stamp: teacherPath(), stampWidth: 3, stampColor: color(0xFFFFFF, 0.6), ink: color(0xFFFFFF, 0.95))

/// Draws the seal filling a `px` square: optional paper, the stamp, then 活.
func seal(_ look: Look, px: Int, transparent: Bool) -> CGContext {
    let ctx = makeContext(px, px)
    if !transparent, let paper = look.paper {
        ctx.setFillColor(paper)
        ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
    }
    // Box units, y down.
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: CGFloat(px) / 120, y: -CGFloat(px) / 120)

    ctx.saveGState()
    ctx.translateBy(x: 60, y: 60)
    ctx.scaleBy(x: 0.84, y: 0.84)
    ctx.translateBy(x: -60, y: -60)
    ctx.addPath(look.stamp)
    ctx.setStrokeColor(look.stampColor)
    ctx.setLineWidth(look.stampWidth * 1.8)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.addPath(glyphPath())
    ctx.setFillColor(look.ink)
    ctx.fillPath()
    return ctx
}

// MARK: Generated Swift.

func swiftSource() -> String {
    func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    func pt(_ p: CGPoint) -> String { "CGPoint(x: \(f(p.x)), y: \(f(p.y)))" }
    var lines: [String] = []
    for step in glyph {
        switch step {
        case let .move(to): lines.append("        p.move(to: \(pt(to)))")
        case let .line(to): lines.append("        p.addLine(to: \(pt(to)))")
        case let .quad(to, c): lines.append("        p.addQuadCurve(to: \(pt(to)), control: \(pt(c)))")
        case let .cubic(to, c1, c2): lines.append("        p.addCurve(to: \(pt(to)), control1: \(pt(c1)), control2: \(pt(c2)))")
        case .close: lines.append("        p.closeSubpath()")
        }
    }
    return """
    // Generated by scripts/generate-icon.swift from Shippori Mincho B1 Bold (SIL Open Font License 1.1).
    // Do not edit: rerun the script instead.
    import SwiftUI

    /// 活, outlined from Shippori Mincho B1 in the seal's 120-unit box (em 60, centred, y down):
    /// the same outline the launch image and the app icon are drawn with.
    enum SealGlyph {
        static func path(in rect: CGRect) -> Path {
            unit.applying(
                CGAffineTransform(scaleX: rect.width / 120, y: rect.height / 120)
                    .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
            )
        }

        private static let unit: Path = {
            var p = Path()
    \(lines.joined(separator: "\n"))
            return p
        }()
    }

    """
}

// MARK: Write everything.

let launchSet = assets.appendingPathComponent("LaunchImage.imageset")
for old in (try? FileManager.default.contentsOfDirectory(atPath: launchSet.path)) ?? [] where old.hasSuffix(".png") {
    try FileManager.default.removeItem(at: launchSet.appendingPathComponent(old))
}
var launchImages: [[String: Any]] = []
for (name, look, isDark) in [("launch-light", light, false), ("launch-dark", dark, true)] {
    for scale in 1...3 {
        let file = "\(name)@\(scale)x.png"
        try write(seal(look, px: 122 * scale, transparent: true), to: launchSet.appendingPathComponent(file))
        var entry: [String: Any] = ["filename": file, "idiom": "universal", "scale": "\(scale)x"]
        if isDark { entry["appearances"] = [["appearance": "luminosity", "value": "dark"]] }
        launchImages.append(entry)
    }
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try (String(data: data, encoding: .utf8)! + "\n").write(to: url, atomically: true, encoding: .utf8)
}

let info: [String: Any] = ["author": "xcode", "version": 1]
try writeJSON(["images": launchImages, "info": info], to: launchSet.appendingPathComponent("Contents.json"))

func colorEntry(_ hex: UInt32, dark: Bool) -> [String: Any] {
    func c(_ shift: UInt32) -> String { String(format: "%.3f", Double((hex >> shift) & 255) / 255) }
    var entry: [String: Any] = [
        "color": ["color-space": "srgb", "components": ["alpha": "1.000", "red": c(16), "green": c(8), "blue": c(0)]],
        "idiom": "universal",
    ]
    if dark { entry["appearances"] = [["appearance": "luminosity", "value": "dark"]] }
    return entry
}
try writeJSON(
    ["colors": [colorEntry(0xF6F7F4, dark: false), colorEntry(0x14171C, dark: true)], "info": info],
    to: assets.appendingPathComponent("LaunchBackground.colorset/Contents.json")
)

let iconSet = assets.appendingPathComponent("AppIcon.appiconset")
try write(seal(light, px: 1024, transparent: false), to: iconSet.appendingPathComponent("icon-1024.png"))
try write(seal(dark, px: 1024, transparent: false), to: iconSet.appendingPathComponent("icon-1024-dark.png"))
try write(seal(tinted, px: 1024, transparent: false), to: iconSet.appendingPathComponent("icon-1024-tinted.png"))

let swiftDir = root.appendingPathComponent("App/Launch")
try FileManager.default.createDirectory(at: swiftDir, withIntermediateDirectories: true)
try swiftSource().write(to: swiftDir.appendingPathComponent("SealGlyph.swift"), atomically: true, encoding: .utf8)

print("wrote the launch image, the iOS icons and App/Launch/SealGlyph.swift (\(glyph.count) path steps)")
