import SwiftUI
import VerbKit

/// A theme half's results stamp: its shape and its two colours, from the canvas board "Themed
/// first frame" (the same faces as the planned alternate icons). A shape with one colour uses
/// it for both.
struct ThemeStamp: Equatable {
    let shape: StampShape
    let first: Color
    let second: Color

    private init(_ shape: StampShape, _ first: UInt32, _ second: UInt32? = nil) {
        self.shape = shape
        self.first = Color(hex: first)
        self.second = Color(hex: second ?? first)
    }

    static func stamp(for theme: ThemeID, isDark: Bool) -> ThemeStamp {
        switch (theme, isDark) {
        case (.light, false): ThemeStamp(.teacher, 0xC2372B)
        case (.light, true): ThemeStamp(.sumi, 0xE9EBE6)
        case (.pastel, false): ThemeStamp(.rings, 0xC9B6F2, 0xF2B8CF)
        case (.pastel, true): ThemeStamp(.rings, 0xB9A3EF, 0xF27A98)
        case (.sand, false): ThemeStamp(.raked, 0xA8743A)
        case (.sand, true): ThemeStamp(.raked, 0xC08A4A)
        case (.matcha, false): ThemeStamp(.enso, 0x4A6B35)
        case (.matcha, true): ThemeStamp(.enso, 0x8FBF6A)
        case (.latte, false): ThemeStamp(.heart, 0xA8714A)
        case (.latte, true): ThemeStamp(.mug, 0xC8945F)
        case (.iceCream, false): ThemeStamp(.scoop, 0xE07AA0)
        case (.iceCream, true): ThemeStamp(.scoop, 0xF08AB0)
        case (.northernLights, false): ThemeStamp(.aurora, 0x1FAE84, 0x7C5FD6)
        case (.northernLights, true): ThemeStamp(.aurora, 0x5FE3B0, 0xA78BFA)
        case (.nocturnal, false): ThemeStamp(.moon, 0x7A70E0, 0x3D3680)
        case (.nocturnal, true): ThemeStamp(.moon, 0x8F86F0, 0xB9B3FF)
        case (.halloween, false): ThemeStamp(.pumpkin, 0xE2701A, 0x4D7A2A)
        case (.halloween, true): ThemeStamp(.pumpkin, 0xFF8A2A, 0x9AD36A)
        case (.christmas, false): ThemeStamp(.wreath, 0x1F6B45, 0xB3202C)
        case (.christmas, true): ThemeStamp(.wreath, 0x7FCF9A, 0xEF6B5E)
        }
    }
}
