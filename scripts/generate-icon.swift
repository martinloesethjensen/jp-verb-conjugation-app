#!/usr/bin/env swift
// Renders the launch screen and the default iOS app icon into App/Assets.xcassets, and writes
// the 活 outline as App/Launch/SealGlyph.swift so the app's first frame draws the same glyph.
//
//     make icons FONT=<ShipporiMinchoB1-Bold.ttf>
//
// `make icons` compiles this file together with VerbKit's StampShape.swift and SVGPathData.swift,
// so every stamp is drawn from the same path data as the app. It also renders the nine alternate
// icon sets (one per theme; Light · Dark is the primary icon) and a small preview of each set for
// Settings › Theme (canvas board "App icons per palette").
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
    usage: make icons FONT=<ShipporiMinchoB1-Bold.ttf>
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

// MARK: Stamps, from VerbKit's StampShape (compiled in by `make icons`).

func cgPath(_ d: String) -> CGPath {
    func cg(_ p: SVGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }
    let p = CGMutablePath()
    for element in SVGPathData.parse(d) {
        switch element {
        case let .move(to): p.move(to: cg(to))
        case let .line(to): p.addLine(to: cg(to))
        case let .quad(to, c): p.addQuadCurve(to: cg(to), control: cg(c))
        case let .cubic(to, c1, c2): p.addCurve(to: cg(to), control1: cg(c1), control2: cg(c2))
        case .close: p.closeSubpath()
        }
    }
    return p
}

/// One face of an icon: paper (nil for a transparent launch image), the stamp in its two colours,
/// and 活 in ink.
struct Look {
    let paper: CGColor?
    let shape: StampShape
    let first: CGColor
    let second: CGColor
    let ink: CGColor

    init(paper: CGColor?, shape: StampShape, first: CGColor, second: CGColor? = nil, ink: CGColor) {
        self.paper = paper
        self.shape = shape
        self.first = first
        self.second = second ?? first
        self.ink = ink
    }

    /// The tinted face iOS recolours: black paper, the stamp at 60 % white, 活 at 95 %.
    func tinted() -> Look {
        Look(paper: color(0x000000), shape: shape, first: color(0xFFFFFF, 0.6), ink: color(0xFFFFFF, 0.95))
    }
}

let light = Look(paper: color(0xF6F7F4), shape: .teacher, first: color(0xC2372B), ink: color(0x1E2633))
let dark = Look(paper: color(0x14171C), shape: .sumi, first: color(0xE9EBE6), ink: color(0xE9EBE6))

/// The ten sets from the board's SETS table: (theme raw value, light face, dark face). Paper and
/// ink are each half's palette tokens; stamps and colours match App's ThemeStamp.
let sets: [(String, Look, Look)] = [
    ("light", light, dark),
    ("pastel",
     Look(paper: color(0xFBF5FA), shape: .rings, first: color(0xC9B6F2), second: color(0xF2B8CF), ink: color(0x3A2E4A)),
     Look(paper: color(0x1C1724), shape: .rings, first: color(0xB9A3EF), second: color(0xF27A98), ink: color(0xF0E8F6))),
    ("sand",
     Look(paper: color(0xF2EBDF), shape: .raked, first: color(0xA8743A), ink: color(0x3B2F22)),
     Look(paper: color(0x1E1A15), shape: .raked, first: color(0xC08A4A), ink: color(0xF1E8DA))),
    ("matcha",
     Look(paper: color(0xEEF1E6), shape: .enso, first: color(0x4A6B35), ink: color(0x24361F)),
     Look(paper: color(0x141A12), shape: .enso, first: color(0x8FBF6A), ink: color(0xE6EDDC))),
    ("latte",
     Look(paper: color(0xF5EEE6), shape: .heart, first: color(0xA8714A), ink: color(0x4A3426)),
     Look(paper: color(0x1F1712), shape: .mug, first: color(0xC8945F), ink: color(0xF0E6DC))),
    ("iceCream",
     Look(paper: color(0xFFF6F8), shape: .scoop, first: color(0xE07AA0), ink: color(0x3D2B3A)),
     Look(paper: color(0x1F1720), shape: .scoop, first: color(0xF08AB0), ink: color(0xF6E6EE))),
    ("northernLights",
     Look(paper: color(0xEEF5F6), shape: .aurora, first: color(0x1FAE84), second: color(0x7C5FD6), ink: color(0x12283A)),
     Look(paper: color(0x0D1622), shape: .aurora, first: color(0x5FE3B0), second: color(0xA78BFA), ink: color(0xE6F1F2))),
    ("nocturnal",
     Look(paper: color(0xF3F2FA), shape: .moon, first: color(0x7A70E0), second: color(0x3D3680), ink: color(0x24223F)),
     Look(paper: color(0x0B0B14), shape: .moon, first: color(0x8F86F0), second: color(0xB9B3FF), ink: color(0xD9D7F0))),
    ("halloween",
     Look(paper: color(0xF6EFE4), shape: .pumpkin, first: color(0xE2701A), second: color(0x4D7A2A), ink: color(0x2E2135)),
     Look(paper: color(0x17121C), shape: .pumpkin, first: color(0xFF8A2A), second: color(0x9AD36A), ink: color(0xF5EBDD))),
    ("christmas",
     Look(paper: color(0xF4F0E8), shape: .wreath, first: color(0x1F6B45), second: color(0xB3202C), ink: color(0x163A2A)),
     Look(paper: color(0x0F1D16), shape: .wreath, first: color(0x7FCF9A), second: color(0xEF6B5E), ink: color(0xF1ECE0))),
]

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
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for stroke in look.shape.strokes {
        ctx.addPath(cgPath(stroke.d))
        ctx.setStrokeColor(stroke.usesSecondColor ? look.second : look.first)
        ctx.setLineWidth(stroke.baseWidth * 1.8)
        ctx.strokePath()
    }
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
try write(seal(light.tinted(), px: 1024, transparent: false), to: iconSet.appendingPathComponent("icon-1024-tinted.png"))

func iconEntry(_ file: String, _ appearance: String?) -> [String: Any] {
    var entry: [String: Any] = ["filename": file, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
    if let appearance { entry["appearances"] = [["appearance": "luminosity", "value": appearance]] }
    return entry
}

// The nine alternate icon sets, named AppIcon-<theme> as VerbKit's AppIconMatching expects.
for (theme, day, night) in sets where theme != "light" {
    let set = assets.appendingPathComponent("AppIcon-\(theme).appiconset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    try write(seal(day, px: 1024, transparent: false), to: set.appendingPathComponent("icon-1024.png"))
    try write(seal(night, px: 1024, transparent: false), to: set.appendingPathComponent("icon-1024-dark.png"))
    try write(seal(day.tinted(), px: 1024, transparent: false), to: set.appendingPathComponent("icon-1024-tinted.png"))
    try writeJSON(["images": [
        iconEntry("icon-1024.png", nil), iconEntry("icon-1024-dark.png", "dark"), iconEntry("icon-1024-tinted.png", "tinted"),
    ], "info": info], to: set.appendingPathComponent("Contents.json"))
}

// A 44 pt preview of every set, light and dark, for Settings › Theme (the app can't read its own
// alternate icons back as images).
for (theme, day, night) in sets {
    let set = assets.appendingPathComponent("IconPreview-\(theme).imageset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    var images: [[String: Any]] = []
    for (name, look, isDark) in [("preview", day, false), ("preview-dark", night, true)] {
        for scale in 2...3 {
            let file = "\(name)@\(scale)x.png"
            try write(seal(look, px: 44 * scale, transparent: false), to: set.appendingPathComponent(file))
            var entry: [String: Any] = ["filename": file, "idiom": "universal", "scale": "\(scale)x"]
            if isDark { entry["appearances"] = [["appearance": "luminosity", "value": "dark"]] }
            images.append(entry)
        }
    }
    try writeJSON(["images": images, "info": info], to: set.appendingPathComponent("Contents.json"))
}

let swiftDir = root.appendingPathComponent("App/Launch")
try FileManager.default.createDirectory(at: swiftDir, withIntermediateDirectories: true)
try swiftSource().write(to: swiftDir.appendingPathComponent("SealGlyph.swift"), atomically: true, encoding: .utf8)

print("wrote the launch image, the iOS icons, \(sets.count - 1) alternate icon sets, their previews and App/Launch/SealGlyph.swift (\(glyph.count) path steps)")
