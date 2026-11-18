/// A visual theme for every overlay. Themes change the look only; behavior, sizes and timing stay
/// as configured. The Minimal theme takes its colors from the user's settings.
public enum Theme: String, Codable, CaseIterable, Sendable {
    case minimal
    /// Hotaru, a hand-drawn firefly whose tail lantern is the only light: it lights the ring,
    /// flashes on a click and becomes the laser point. Direction art from Claude Design,
    /// implemented in code.
    case hotaru
    /// Ink ensō ring, seal-stamp clicks, bleeding ink-brush laser, hanji-paper tags.
    /// Parked after the concept round (black ink on white slides is hard to see): the code stays,
    /// but it is not offered in the menu or Settings.
    case brushInk
    /// Soft light: glass ring, droplet ripples, glow laser, frosted keycaps.
    /// Parked after the concept round (not distinctive enough); kept in code, not offered.
    case keynoteGlow
    /// Dark-mode developer HUD: neon reticle, target-lock brackets on click, neon beam laser,
    /// terminal keycaps. Reads on dark editor slides and on light slides.
    case cyberpunk

    /// Themes offered in the menu and Settings, in menu order.
    public static let offered: [Theme] = [.hotaru, .cyberpunk, .minimal]

    public var isParked: Bool { self == .brushInk || self == .keynoteGlow }

    public var title: String {
        switch self {
        case .minimal: "Minimal"
        case .hotaru: "Hotaru"
        case .brushInk: "Brush & Ink"
        case .keynoteGlow: "Keynote Glow"
        case .cyberpunk: "Cyberpunk"
        }
    }
}

/// Hotaru's palette, from the character sheet (0xRRGGBB).
public enum HotaruPalette {
    public static let nightInk: UInt32 = 0x2B2620 // outlines
    public static let body: UInt32 = 0x3A342C // abdomen
    public static let head: UInt32 = 0x4A483C
    public static let collar: UInt32 = 0xCF5F40 // ember pronotum, the identity mark
    public static let wingRear: UInt32 = 0xE6ECDD
    public static let wingFront: UInt32 = 0xF1F4EA
    public static let eye: UInt32 = 0xFBF6EA
    public static let blush: UInt32 = 0xE58C7A
    public static let lanternCore: UInt32 = 0xFFF8D2
    public static let lanternRim: UInt32 = 0xF2D04A
    public static let lanternGlow: UInt32 = 0xFFC33C
    public static let lanternDim: UInt32 = 0xD8D1A6
    public static let trail: UInt32 = 0xFFB830
}

/// Fixed colors of the Cyberpunk theme (0xRRGGBB).
public enum CyberPalette {
    public static let night: UInt32 = 0x0B0F1A
    public static let cyan: UInt32 = 0x00E5FF
    public static let magenta: UInt32 = 0xFF2BD6
    public static let acid: UInt32 = 0xB6FF00
}

/// Every color and style switch a theme decides, as plain values.
public struct ThemeStyle: Equatable, Sendable {
    public var ring: RGBA
    /// Drawn just outside the ring so it stays visible on both light and dark slides.
    public var ringOutline: RGBA?
    public var rippleLeft: RGBA
    public var rippleRight: RGBA
    public var rippleMiddle: RGBA
    public var laser: RGBA
    /// Multiplies the laser trail length from settings (an ink stroke lingers longer than light).
    public var laserTrailScale: Double
    public var pen: RGBA
    public var highlighter: RGBA
    public var keycapBackground: RGBA
    public var keycapBorder: RGBA
    public var keycapText: RGBA
    public var keycapCornerRadius: Double

    public func ripple(for button: MouseButton) -> RGBA {
        switch button {
        case .left: rippleLeft
        case .right: rippleRight
        case .middle: rippleMiddle
        }
    }
}

extension RGBA {
    /// 0xRRGGBB.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha)
    }
}

extension AppSettings {
    /// The style in effect: the theme's preset, or the user's own colors for Minimal.
    public var style: ThemeStyle {
        switch theme {
        case .minimal:
            ThemeStyle(ring: ringColor, ringOutline: nil,
                       rippleLeft: rippleLeft, rippleRight: rippleRight, rippleMiddle: rippleMiddle,
                       laser: laserColor, laserTrailScale: 1,
                       pen: inkColor, highlighter: RGBA.highlighterYellow.withAlpha(0.4),
                       keycapBackground: RGBA(0.08, 0.08, 0.08, 0.82), keycapBorder: RGBA(1, 1, 1, 0.18),
                       keycapText: RGBA(1, 1, 1), keycapCornerRadius: 12)
        case .hotaru:
            // Everything is lit by the lantern: the ring is its rim color, the trail is amber,
            // the pen takes the ember collar color so it reads on light and dark slides.
            ThemeStyle(ring: RGBA(hex: HotaruPalette.lanternRim), ringOutline: RGBA(hex: HotaruPalette.nightInk, alpha: 0.3),
                       rippleLeft: RGBA(hex: HotaruPalette.lanternGlow), rippleRight: RGBA(hex: 0x6CB8FF), rippleMiddle: RGBA(hex: 0x6FD69A),
                       laser: RGBA(hex: HotaruPalette.trail), laserTrailScale: 1.2,
                       pen: RGBA(hex: HotaruPalette.collar), highlighter: RGBA(hex: HotaruPalette.lanternGlow, alpha: 0.45),
                       keycapBackground: RGBA(hex: HotaruPalette.nightInk, alpha: 0.94), keycapBorder: RGBA(hex: HotaruPalette.lanternRim, alpha: 0.6),
                       keycapText: RGBA(hex: HotaruPalette.lanternCore), keycapCornerRadius: 10)
        case .brushInk:
            ThemeStyle(ring: RGBA(hex: 0x1F1A17, alpha: 0.88), ringOutline: RGBA(hex: 0xF2EAD8, alpha: 0.7),
                       rippleLeft: RGBA(hex: 0xB8312F), rippleRight: RGBA(hex: 0x2F4A7A), rippleMiddle: RGBA(hex: 0x3E6B4F),
                       laser: RGBA(hex: 0x1F1A17), laserTrailScale: 2,
                       pen: RGBA(hex: 0x1F1A17), highlighter: RGBA(hex: 0xB8312F, alpha: 0.22),
                       keycapBackground: RGBA(hex: 0xF2EAD8, alpha: 0.97), keycapBorder: RGBA(hex: 0xCDBF9F),
                       keycapText: RGBA(hex: 0x2B2622), keycapCornerRadius: 3)
        case .keynoteGlow:
            ThemeStyle(ring: RGBA(1, 1, 1, 0.92), ringOutline: RGBA(hex: 0x1C2440, alpha: 0.38),
                       rippleLeft: RGBA(hex: 0x8FB8FF), rippleRight: RGBA(hex: 0xFFB27A), rippleMiddle: RGBA(hex: 0x7FD9B0),
                       laser: RGBA(hex: 0xFF4D6D), laserTrailScale: 1.3,
                       pen: RGBA(hex: 0x2E6BFF), highlighter: RGBA(hex: 0x7FE3FF, alpha: 0.32),
                       keycapBackground: RGBA(hex: 0x1C2033, alpha: 0.55), keycapBorder: RGBA(1, 1, 1, 0.35),
                       keycapText: RGBA(1, 1, 1), keycapCornerRadius: 14)
        case .cyberpunk:
            // Neon on night. The dark outline keeps the neon readable on white slides.
            ThemeStyle(ring: RGBA(hex: CyberPalette.cyan), ringOutline: RGBA(hex: CyberPalette.night, alpha: 0.6),
                       rippleLeft: RGBA(hex: CyberPalette.cyan), rippleRight: RGBA(hex: CyberPalette.magenta), rippleMiddle: RGBA(hex: CyberPalette.acid),
                       laser: RGBA(hex: CyberPalette.magenta), laserTrailScale: 1.1,
                       pen: RGBA(hex: CyberPalette.magenta), highlighter: RGBA(hex: CyberPalette.acid, alpha: 0.38),
                       keycapBackground: RGBA(hex: CyberPalette.night, alpha: 0.92), keycapBorder: RGBA(hex: CyberPalette.cyan, alpha: 0.9),
                       keycapText: RGBA(hex: CyberPalette.cyan), keycapCornerRadius: 3)
        }
    }
}
