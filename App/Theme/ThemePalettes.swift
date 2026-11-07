import SwiftUI

// The twenty palettes from docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md.
// Every text token is at least 4.5:1 on paper and card (checked in the spec).
extension ThemePalette {
    private init(
        _ paper: UInt32, _ card: UInt32, _ ink: UInt32, _ muted: UInt32, _ rule: UInt32,
        _ mark: UInt32, _ markSoft: UInt32, _ good: UInt32, _ goodSoft: UInt32,
        _ button: UInt32, _ onButton: UInt32, _ accent: UInt32, fillsTypePills: Bool = false
    ) {
        self.init(
            paper: Color(hex: paper), card: Color(hex: card), ink: Color(hex: ink),
            muted: Color(hex: muted), rule: Color(hex: rule), mark: Color(hex: mark),
            markSoft: Color(hex: markSoft), good: Color(hex: good), goodSoft: Color(hex: goodSoft),
            button: Color(hex: button), onButton: Color(hex: onButton), accent: Color(hex: accent),
            fillsTypePills: fillsTypePills
        )
    }

    //                                  paper     card      ink       muted     rule      mark      markSoft  good      goodSoft  button    onButton  accent
    static let light = ThemePalette(0xF6F7F4, 0xFFFFFF, 0x1E2633, 0x5F6673, 0xDCE0D8, 0xC2372B, 0xFBECEB, 0x2E6B45, 0xE2F0E6, 0x1E2633, 0xFFFFFF, 0x1E2633)
    static let dark = ThemePalette(0x14171C, 0x1D2128, 0xE9EBE6, 0x9AA1AD, 0x2C323B, 0xEF6B5E, 0x3A2422, 0x6FBF8C, 0x1F3327, 0xE9EBE6, 0x14171C, 0x6FBF8C)
    static let pastel = ThemePalette(0xFBF5FA, 0xFFFFFF, 0x3A2E4A, 0x6E6280, 0xEDDFF0, 0xC43A5C, 0xFCE8EE, 0x3C7A5A, 0xE4F3EA, 0x3A2E4A, 0xFFFFFF, 0x9B7FE6, fillsTypePills: true)
    static let pastelDark = ThemePalette(0x1C1724, 0x262033, 0xF0E8F6, 0xB3A7C2, 0x3A3049, 0xF27A98, 0x3D2230, 0x8FD1AA, 0x1F3328, 0xD9C8F5, 0x1C1724, 0xB9A3EF, fillsTypePills: true)
    static let sand = ThemePalette(0xF2EBDF, 0xFBF7F0, 0x3B2F22, 0x6A5B47, 0xE0D3BD, 0xB5432A, 0xF6E3DA, 0x4F6B34, 0xE8EEDB, 0x3B2F22, 0xFBF7F0, 0xA8743A)
    static let sandDark = ThemePalette(0x1E1A15, 0x29231C, 0xF1E8DA, 0xB9AA94, 0x3D3428, 0xE8775A, 0x3D241B, 0xA9C47F, 0x2A3220, 0xF1E8DA, 0x1E1A15, 0xC08A4A)
    static let matcha = ThemePalette(0xEEF1E6, 0xFBFCF7, 0x24361F, 0x5A6852, 0xD5DCCB, 0xB23A2E, 0xF6E2DF, 0x3F6B2A, 0xE1ECD6, 0x4A6B35, 0xFFFFFF, 0x5F8A43)
    static let latte = ThemePalette(0xF5EEE6, 0xFFFAF5, 0x4A3426, 0x735A4B, 0xE6D8CA, 0xB5442F, 0xF7E3DC, 0x4D6B3C, 0xE5EEDC, 0x8A5A3C, 0xFFFFFF, 0xA8714A)
    static let coffee = ThemePalette(0x1F1712, 0x2A201A, 0xF0E6DC, 0xB8A796, 0x3E3027, 0xF07A62, 0x3E231C, 0xA8C98A, 0x26301E, 0xD9B48F, 0x1F1712, 0xC8945F)
    static let iceCream = ThemePalette(0xFFF6F8, 0xFFFFFF, 0x3D2B3A, 0x75606F, 0xF3DDE4, 0xC7365E, 0xFDE6EC, 0x2F7D6A, 0xDFF3EC, 0x3D2B3A, 0xFFFFFF, 0xE07AA0, fillsTypePills: true)
    static let northernLights = ThemePalette(0x0D1622, 0x142233, 0xE6F1F2, 0x9FB4BF, 0x22364A, 0xFF7A8A, 0x3A1D28, 0x5FE3B0, 0x123A30, 0x5FE3B0, 0x0D1622, 0x3FCF98)
    static let nocturnal = ThemePalette(0x0B0B14, 0x141422, 0xD9D7F0, 0x9894B8, 0x25243A, 0xE8836F, 0x34201F, 0x8FC7A0, 0x1A2E24, 0xB9B3FF, 0x0B0B14, 0x8F86F0)
    static let halloween = ThemePalette(0x17121C, 0x231A2B, 0xF5EBDD, 0xB7A9BD, 0x3A2D44, 0xFF8A2A, 0x3B2516, 0x9AD36A, 0x25331D, 0xFF8A2A, 0x17121C, 0xFF8A2A)
    static let christmas = ThemePalette(0xF4F0E8, 0xFFFFFF, 0x163A2A, 0x56675C, 0xDDD7C9, 0xB3202C, 0xF8E4E3, 0x1F6B45, 0xE0EFE5, 0x163A2A, 0xFFFFFF, 0x1F6B45)
    // The halves added so every theme has a light and a dark palette.
    static let matchaDark = ThemePalette(0x141A12, 0x1C2419, 0xE6EDDC, 0xA6B29A, 0x2E3A28, 0xEC7A66, 0x3A2420, 0x9FCF7F, 0x22301C, 0xB5D39A, 0x141A12, 0x8FBF6A)
    static let iceCreamDark = ThemePalette(0x1F1720, 0x2A1F2B, 0xF6E6EE, 0xC3A9B8, 0x413041, 0xFF7A9A, 0x40202C, 0x7FD8BD, 0x1D3530, 0xF2A6C4, 0x1F1720, 0xF08AB0, fillsTypePills: true)
    static let christmasDark = ThemePalette(0x0F1D16, 0x16271E, 0xF1ECE0, 0xA9B8AD, 0x284034, 0xEF6B5E, 0x3A2220, 0x7FCF9A, 0x1A3326, 0xF1ECE0, 0x0F1D16, 0xD9B45A)
    static let northernLightsLight = ThemePalette(0xEEF5F6, 0xFFFFFF, 0x12283A, 0x4D6676, 0xD3E2E6, 0xC2364A, 0xFBE6EA, 0x1F7A5A, 0xDCF1E8, 0x12283A, 0xFFFFFF, 0x1FAE84)
    static let nocturnalLight = ThemePalette(0xF3F2FA, 0xFFFFFF, 0x24223F, 0x5F5B80, 0xE0DEF0, 0xBF3F30, 0xF9E5E2, 0x2F6F4A, 0xE0EFE6, 0x3D3680, 0xFFFFFF, 0x7A70E0)
    static let halloweenLight = ThemePalette(0xF6EFE4, 0xFFFAF2, 0x2E2135, 0x66586C, 0xE6D9C6, 0xB3361F, 0xF8E2DA, 0x4D7A2A, 0xE5EFD8, 0x2E2135, 0xFFFAF2, 0xE2701A)
}

#if DEBUG
private let previewPalettes: [(String, ThemePalette)] = [
    ("light", .light), ("dark", .dark), ("pastel", .pastel), ("pastelDark", .pastelDark),
    ("sand", .sand), ("sandDark", .sandDark), ("matcha", .matcha), ("latte", .latte),
    ("coffee", .coffee), ("iceCream", .iceCream), ("northernLights", .northernLights),
    ("nocturnal", .nocturnal), ("halloween", .halloween), ("christmas", .christmas),
    ("matchaDark", .matchaDark), ("iceCreamDark", .iceCreamDark), ("christmasDark", .christmasDark),
    ("northernLightsLight", .northernLightsLight), ("nocturnalLight", .nocturnalLight),
    ("halloweenLight", .halloweenLight),
]

#Preview("All palettes") {
    ScrollView {
        VStack(spacing: 8) {
            ForEach(previewPalettes, id: \.0) { name, palette in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).foregroundStyle(palette.ink).bold()
                        Text("muted").foregroundStyle(palette.muted)
                        HStack {
                            Text("mark").foregroundStyle(palette.mark)
                            Text("good").foregroundStyle(palette.good)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.card, in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.rule))
                    Text("Button")
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(palette.onButton)
                        .background(palette.button, in: Capsule())
                }
                .padding(10)
                .background(palette.paper)
            }
        }
    }
}
#endif
