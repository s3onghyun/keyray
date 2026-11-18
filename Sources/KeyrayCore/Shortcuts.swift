/// The app's global shortcuts. They are registered with Carbon's RegisterEventHotKey,
/// which needs no permission, and hidden from the keycap HUD when `keycapHideActivationKeys` is on.
public enum AppShortcut: String, CaseIterable, Sendable {
    case toggleOverlays
    case toggleLaser
    case toggleInk
    case toggleKeycaps
    case pen
    case arrow
    case highlighter
    case clearInk
    /// Registered only while ink mode is armed, so Esc works normally otherwise.
    case exitInk

    public static let hyper: KeyModifiers = [.control, .option, .command]

    public var stroke: KeyStroke {
        switch self {
        case .toggleOverlays: KeyStroke(keyCode: 31, modifiers: Self.hyper) // O
        case .toggleLaser: KeyStroke(keyCode: 37, modifiers: Self.hyper) // L
        case .toggleInk: KeyStroke(keyCode: 2, modifiers: Self.hyper) // D
        case .toggleKeycaps: KeyStroke(keyCode: 40, modifiers: Self.hyper) // K
        case .pen: KeyStroke(keyCode: 18, modifiers: Self.hyper) // 1
        case .arrow: KeyStroke(keyCode: 19, modifiers: Self.hyper) // 2
        case .highlighter: KeyStroke(keyCode: 20, modifiers: Self.hyper) // 3
        case .clearInk: KeyStroke(keyCode: 7, modifiers: Self.hyper) // X
        case .exitInk: KeyStroke(keyCode: 53, modifiers: []) // esc
        }
    }

    public var title: String {
        switch self {
        case .toggleOverlays: "All overlays on/off"
        case .toggleLaser: "Laser pointer"
        case .toggleInk: "Draw (ink)"
        case .toggleKeycaps: "Keycaps on/off"
        case .pen: "Pen"
        case .arrow: "Arrow"
        case .highlighter: "Highlighter"
        case .clearInk: "Clear ink"
        case .exitInk: "Leave ink mode"
        }
    }

    /// Shortcuts that are always registered.
    public static let permanent: [AppShortcut] = allCases.filter { $0 != .exitInk }

    /// Strokes the keycap HUD hides when "hide activation keys" is on. Plain Esc stays visible.
    public static var activationStrokes: [KeyStroke] { permanent.map(\.stroke) }
}
