import Foundation

/// An sRGB color with alpha, stored as plain numbers so settings stay Codable and AppKit-free.
public struct RGBA: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public func withAlpha(_ alpha: Double) -> RGBA { RGBA(red, green, blue, alpha) }

    /// Every channel clamped to 0...1.
    public var clamped: RGBA {
        RGBA(red.clamped(0, 1), green.clamped(0, 1), blue.clamped(0, 1), alpha.clamped(0, 1))
    }

    public static let amber = RGBA(1.00, 0.72, 0.10)
    public static let coral = RGBA(1.00, 0.33, 0.33)
    public static let sky = RGBA(0.25, 0.60, 1.00)
    public static let mint = RGBA(0.20, 0.85, 0.55)
    public static let laserRed = RGBA(1.00, 0.15, 0.20)
    public static let highlighterYellow = RGBA(1.00, 0.92, 0.10)
}

public enum MouseButton: String, Codable, CaseIterable, Sendable {
    case left, right, middle
}

/// When the ring around the cursor is drawn.
public enum RingMode: String, Codable, CaseIterable, Sendable {
    /// Always, except after `idleHideSeconds` without movement.
    case always
    /// Only while a mouse button is held (and briefly after release).
    case clickOnly
    case off
}

public enum KeycapMode: String, Codable, CaseIterable, Sendable {
    /// Only combinations with ⌘, ⌃ or ⌥, plus function keys and Escape.
    case shortcutsOnly
    /// Every key, including plain typing.
    case allKeys
    case off
}

public enum InkTool: String, Codable, CaseIterable, Sendable {
    case pen, arrow, highlighter
}

/// How an ink stroke gets its mouse input.
public enum InkInput: String, Codable, CaseIterable, Sendable {
    /// The overlay takes the mouse while ink mode is armed, and gives it back on its own
    /// `inkAutoReleaseSeconds` after the last stroke, or on Esc or the shortcut.
    /// Ink already on screen never blocks clicks.
    case captureWhileDrawing
    /// The overlay never takes the mouse: strokes follow drags that also reach the app underneath.
    case passThrough
}

/// Every user-adjustable value. Unknown or missing keys decode to defaults, and `normalized`
/// clamps out-of-range numbers, so an old or hand-edited preference can never break the app.
public struct AppSettings: Codable, Equatable, Sendable {
    public var enabled = true
    /// Hotaru on first launch.
    public var theme = Theme.hotaru
    /// Set after Hotaru has waved hello once.
    public var greeted = false

    public var ringMode = RingMode.always
    public var ringDiameter = 44.0
    public var ringLineWidth = 3.0
    public var ringColor = RGBA.amber
    public var ringOpacity = 0.85
    /// 0 turns idle auto-hide off.
    public var idleHideSeconds = 2.0

    public var ripplesEnabled = true
    public var rippleLeft = RGBA.amber
    public var rippleRight = RGBA.sky
    public var rippleMiddle = RGBA.mint
    public var rippleDuration = 0.45
    public var rippleDiameter = 70.0

    /// Off until the user turns keycaps on, because they need Input Monitoring.
    public var keycapMode = KeycapMode.off
    /// Keycap HUD center as a fraction of the screen's visible frame (0,0 = bottom left).
    public var keycapPosition = UnitPoint(x: 0.5, y: 0.12)
    public var keycapShowRepeatCount = true
    public var keycapHideActivationKeys = true
    public var keycapLingerSeconds = 1.6
    /// Shortcut Subtitles: say what a shortcut does in the frontmost app, under the keycaps.
    public var keycapSubtitles = true
    /// The user's own VS Code keybindings.json, if imported; it names shortcuts in VS Code.
    public var vscodeKeybindings: ImportedKeybindings?

    public var laserColor = RGBA.laserRed
    public var laserTrailSeconds = 0.45
    public var laserWidth = 10.0

    public var inkTool = InkTool.pen
    public var inkInput = InkInput.captureWhileDrawing
    public var inkColor = RGBA.coral
    public var inkHoldSeconds = 3.0
    public var inkFadeSeconds = 1.0
    public var inkAutoReleaseSeconds = 2.5

    public var hideWhileSystemSettingsFrontmost = true

    public init() {}

    public static let `default` = AppSettings()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        enabled = v(.enabled, d.enabled)
        theme = v(.theme, d.theme)
        greeted = v(.greeted, d.greeted)
        keycapSubtitles = v(.keycapSubtitles, d.keycapSubtitles)
        vscodeKeybindings = v(.vscodeKeybindings, d.vscodeKeybindings)
        ringMode = v(.ringMode, d.ringMode)
        ringDiameter = v(.ringDiameter, d.ringDiameter)
        ringLineWidth = v(.ringLineWidth, d.ringLineWidth)
        ringColor = v(.ringColor, d.ringColor)
        ringOpacity = v(.ringOpacity, d.ringOpacity)
        idleHideSeconds = v(.idleHideSeconds, d.idleHideSeconds)
        ripplesEnabled = v(.ripplesEnabled, d.ripplesEnabled)
        rippleLeft = v(.rippleLeft, d.rippleLeft)
        rippleRight = v(.rippleRight, d.rippleRight)
        rippleMiddle = v(.rippleMiddle, d.rippleMiddle)
        rippleDuration = v(.rippleDuration, d.rippleDuration)
        rippleDiameter = v(.rippleDiameter, d.rippleDiameter)
        keycapMode = v(.keycapMode, d.keycapMode)
        keycapPosition = v(.keycapPosition, d.keycapPosition)
        keycapShowRepeatCount = v(.keycapShowRepeatCount, d.keycapShowRepeatCount)
        keycapHideActivationKeys = v(.keycapHideActivationKeys, d.keycapHideActivationKeys)
        keycapLingerSeconds = v(.keycapLingerSeconds, d.keycapLingerSeconds)
        laserColor = v(.laserColor, d.laserColor)
        laserTrailSeconds = v(.laserTrailSeconds, d.laserTrailSeconds)
        laserWidth = v(.laserWidth, d.laserWidth)
        inkTool = v(.inkTool, d.inkTool)
        inkInput = v(.inkInput, d.inkInput)
        inkColor = v(.inkColor, d.inkColor)
        inkHoldSeconds = v(.inkHoldSeconds, d.inkHoldSeconds)
        inkFadeSeconds = v(.inkFadeSeconds, d.inkFadeSeconds)
        inkAutoReleaseSeconds = v(.inkAutoReleaseSeconds, d.inkAutoReleaseSeconds)
        hideWhileSystemSettingsFrontmost = v(.hideWhileSystemSettingsFrontmost, d.hideWhileSystemSettingsFrontmost)
    }

    public static let ringDiameterRange = 16.0...160.0
    public static let ringLineWidthRange = 1.0...12.0
    public static let idleHideRange = 0.0...30.0
    public static let rippleDurationRange = 0.15...1.5
    public static let rippleDiameterRange = 24.0...200.0
    public static let keycapLingerRange = 0.5...6.0
    public static let laserTrailRange = 0.1...2.0
    public static let laserWidthRange = 2.0...30.0
    public static let inkHoldRange = 0.0...30.0
    public static let inkFadeRange = 0.1...5.0
    public static let inkAutoReleaseRange = 0.5...30.0

    /// A copy with every number pulled into its allowed range.
    public var normalized: AppSettings {
        var s = self
        s.ringDiameter = ringDiameter.clamped(to: Self.ringDiameterRange)
        s.ringLineWidth = ringLineWidth.clamped(to: Self.ringLineWidthRange)
        s.ringColor = ringColor.clamped
        s.ringOpacity = ringOpacity.clamped(0.1, 1)
        s.idleHideSeconds = idleHideSeconds.clamped(to: Self.idleHideRange)
        s.rippleLeft = rippleLeft.clamped
        s.rippleRight = rippleRight.clamped
        s.rippleMiddle = rippleMiddle.clamped
        s.rippleDuration = rippleDuration.clamped(to: Self.rippleDurationRange)
        s.rippleDiameter = rippleDiameter.clamped(to: Self.rippleDiameterRange)
        s.keycapPosition = UnitPoint(x: keycapPosition.x.clamped(0, 1), y: keycapPosition.y.clamped(0, 1))
        s.keycapLingerSeconds = keycapLingerSeconds.clamped(to: Self.keycapLingerRange)
        s.laserColor = laserColor.clamped
        s.laserTrailSeconds = laserTrailSeconds.clamped(to: Self.laserTrailRange)
        s.laserWidth = laserWidth.clamped(to: Self.laserWidthRange)
        s.inkColor = inkColor.clamped
        s.inkHoldSeconds = inkHoldSeconds.clamped(to: Self.inkHoldRange)
        s.inkFadeSeconds = inkFadeSeconds.clamped(to: Self.inkFadeRange)
        s.inkAutoReleaseSeconds = inkAutoReleaseSeconds.clamped(to: Self.inkAutoReleaseRange)
        return s
    }

    public func rippleColor(for button: MouseButton) -> RGBA {
        switch button {
        case .left: rippleLeft
        case .right: rippleRight
        case .middle: rippleMiddle
        }
    }

    /// JSON round trip used for persistence.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Defaults when the data is missing or unreadable.
    public static func decoded(from data: Data?) -> AppSettings {
        guard let data, let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return .default }
        return s.normalized
    }
}

public struct UnitPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { isNaN ? lo : Swift.min(Swift.max(self, lo), hi) }
    func clamped(to range: ClosedRange<Double>) -> Double { clamped(range.lowerBound, range.upperBound) }
}
