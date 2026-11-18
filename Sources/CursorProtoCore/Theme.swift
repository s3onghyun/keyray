/// A visual theme for every overlay. Themes change the look only; behavior, sizes and timing stay
/// as configured. The Minimal theme takes its colors from the user's settings.
public enum Theme: String, Codable, CaseIterable, Sendable {
    case minimal
    /// A firefly companion that reacts to clicks and carries the laser's light; a ring of small
    /// lights; warm glow trail; night-teal plaques. "Firefly" is a working name.
    case firefly
    /// Ink ensō ring, seal-stamp clicks, bleeding ink-brush laser, hanji-paper tags.
    case brushInk
    /// Soft light: glass ring, droplet ripples, glow laser, frosted keycaps.
    case keynoteGlow

    public var title: String {
        switch self {
        case .minimal: "Minimal"
        case .firefly: "Firefly"
        case .brushInk: "Brush & Ink"
        case .keynoteGlow: "Keynote Glow"
        }
    }
}

/// Fixed colors of the firefly companion (0xRRGGBB).
public enum FireflyPalette {
    public static let body: UInt32 = 0x24505F
    public static let bodyShade: UInt32 = 0x1A3B47
    public static let face: UInt32 = 0xFFF3D6
    public static let cheek: UInt32 = 0xFF9E8A
    public static let eye: UInt32 = 0x1B1F24
    public static let light: UInt32 = 0xFFE27A
    public static let lightGlow: UInt32 = 0xFFC93C
    public static let wing: UInt32 = 0xDCEFF5
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
        case .firefly:
            // Night teal (the firefly's body) and its warm tail light.
            ThemeStyle(ring: RGBA(hex: 0xFFC93C), ringOutline: RGBA(hex: 0x1D3F4B, alpha: 0.6),
                       rippleLeft: RGBA(hex: 0xFFC93C), rippleRight: RGBA(hex: 0x6CB8FF), rippleMiddle: RGBA(hex: 0x6FD69A),
                       laser: RGBA(hex: 0xFFB830), laserTrailScale: 1.2,
                       pen: RGBA(hex: 0x1E5F74), highlighter: RGBA(hex: 0xFFE27A, alpha: 0.5),
                       keycapBackground: RGBA(hex: 0x1D3F4B, alpha: 0.94), keycapBorder: RGBA(hex: 0xFFC93C, alpha: 0.6),
                       keycapText: RGBA(hex: 0xFFF3D6), keycapCornerRadius: 10)
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
        }
    }
}
