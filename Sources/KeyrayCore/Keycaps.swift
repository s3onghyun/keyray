import Foundation

public struct KeyModifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
    public static let capsLock = KeyModifiers(rawValue: 1 << 4)
    public static let function = KeyModifiers(rawValue: 1 << 5)

    /// Modifiers that turn a key into a shortcut (Shift alone only changes the character).
    public static let shortcutMask: KeyModifiers = [.control, .option, .command]

    /// Apple's menu order: ⌃⌥⇧⌘.
    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// One key press as seen by the event tap: a virtual key code (ANSI layout) plus modifiers.
public struct KeyStroke: Hashable, Codable, Sendable {
    public var keyCode: Int
    public var modifiers: KeyModifiers

    public init(keyCode: Int, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var isShortcut: Bool { !modifiers.intersection(.shortcutMask).isEmpty }
    public var isFunctionKey: Bool { KeyNames.functionKeyCodes.contains(keyCode) }
    public var isModifierKey: Bool { KeyNames.modifierKeyCodes.contains(keyCode) }

    /// Printable text when typed without ⌘⌃⌥, e.g. "a", "A", "!" or " ". Nil for special keys.
    public var typedText: String? {
        guard !isShortcut, let base = KeyNames.ansiCharacters[keyCode] else { return nil }
        let shifted = modifiers.contains(.shift)
        if base.count == 1, base.first!.isLetter {
            return shifted != modifiers.contains(.capsLock) ? base.uppercased() : base
        }
        return shifted ? (KeyNames.ansiShifted[keyCode] ?? base) : base
    }

    /// The keycap label: modifier symbols followed by the key name, e.g. "⇧⌘K", "⌃→", "⌘␣".
    public var label: String { modifiers.symbols + KeyNames.name(for: keyCode) }

    /// Same physical shortcut, ignoring Caps Lock and Fn (which macOS adds to arrow and F keys).
    public func matches(_ other: KeyStroke) -> Bool {
        let relevant: KeyModifiers = [.control, .option, .shift, .command]
        return keyCode == other.keyCode && modifiers.intersection(relevant) == other.modifiers.intersection(relevant)
    }
}

public enum KeyNames {
    public static let ansiCharacters: [Int: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "n",
        46: "m", 47: ".", 49: " ", 50: "`",
    ]

    static let ansiShifted: [Int: String] = [
        18: "!", 19: "@", 20: "#", 21: "$", 22: "^", 23: "%", 24: "+", 25: "(", 26: "&",
        27: "_", 28: "*", 29: ")", 30: "}", 33: "{", 39: "\"", 41: ":", 42: "|", 43: "<",
        44: "?", 47: ">", 50: "~",
    ]

    static let special: [Int: String] = [
        36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "esc", 76: "⌤", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 114: "help",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        102: "英数", 104: "かな",
        65: "num .", 67: "num *", 69: "num +", 71: "clear", 75: "num /", 78: "num -", 81: "num =",
        82: "num 0", 83: "num 1", 84: "num 2", 85: "num 3", 86: "num 4", 87: "num 5",
        88: "num 6", 89: "num 7", 91: "num 8", 92: "num 9",
        54: "⌘", 55: "⌘", 56: "⇧", 60: "⇧", 58: "⌥", 61: "⌥", 59: "⌃", 62: "⌃", 57: "⇪", 63: "fn",
    ]

    static let functionKeys: [Int: Int] = [
        122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10,
        103: 11, 111: 12, 105: 13, 107: 14, 113: 15, 106: 16, 64: 17, 79: 18, 80: 19, 90: 20,
    ]

    public static let functionKeyCodes = Set(functionKeys.keys)
    public static let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    public static func name(for keyCode: Int) -> String {
        if let s = special[keyCode] { return s }
        if let n = functionKeys[keyCode] { return "F\(n)" }
        if let c = ansiCharacters[keyCode] { return c.uppercased() }
        return "key \(keyCode)"
    }
}

/// One row in the keycap HUD.
public struct KeycapEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A shortcut or special key; repeats bump `count`.
        case stroke(KeyStroke)
        /// A run of plain typing, joined into one cap.
        case typing
    }

    public var kind: Kind
    public var text: String
    public var count = 1
    public var lastTime: Double
    /// What the shortcut does in the app it was pressed in (Shortcut Subtitles), if known.
    public var subtitle: String?

    public func display(showCount: Bool) -> String {
        if case .typing = kind { return text }
        return showCount && count > 1 ? "\(text) ×\(count)" : text
    }
}

/// The keycap HUD's state: which presses are shown, repeat counting, typing runs and expiry.
public struct KeycapFeed: Sendable {
    public var mode: KeycapMode
    public var hiddenStrokes: [KeyStroke]
    /// Presses of the same shortcut within this many seconds count as repeats.
    public var repeatWindow = 1.0
    /// The HUD clears this many seconds after the last press.
    public var linger: Double
    public var maxEntries = 4
    public var maxTypingLength = 24
    public private(set) var entries: [KeycapEntry] = []

    public init(mode: KeycapMode, hiddenStrokes: [KeyStroke] = [], linger: Double = 1.6) {
        self.mode = mode
        self.hiddenStrokes = hiddenStrokes
        self.linger = linger
    }

    /// Whether this press belongs on screen in the current mode.
    public func accepts(_ stroke: KeyStroke) -> Bool {
        if stroke.isModifierKey { return false }
        if hiddenStrokes.contains(where: { $0.matches(stroke) }) { return false }
        switch mode {
        case .off: return false
        case .shortcutsOnly: return stroke.isShortcut || stroke.isFunctionKey
        case .allKeys: return true
        }
    }

    /// Records a key press. Returns true when the HUD changed.
    @discardableResult
    public mutating func record(_ stroke: KeyStroke, time: Double, isRepeat: Bool = false, subtitle: String? = nil) -> Bool {
        guard accepts(stroke) else { return false }
        prune(now: time)

        if mode == .allKeys, let typed = stroke.typedText {
            if let last = entries.last, case .typing = last.kind, time - last.lastTime < linger {
                var text = last.text + typed
                if text.count > maxTypingLength { text = "…" + text.suffix(maxTypingLength - 1) }
                entries[entries.count - 1].text = text
                entries[entries.count - 1].lastTime = time
            } else {
                append(KeycapEntry(kind: .typing, text: typed, lastTime: time))
            }
            return true
        }

        if let last = entries.last, case .stroke(let s) = last.kind, s.matches(stroke),
           isRepeat || time - last.lastTime < repeatWindow {
            entries[entries.count - 1].count += 1
            entries[entries.count - 1].lastTime = time
            return true
        }
        append(KeycapEntry(kind: .stroke(stroke), text: stroke.label, lastTime: time, subtitle: subtitle))
        return true
    }

    /// Clears everything once `linger` seconds pass with no press. Returns true while anything is shown.
    @discardableResult
    public mutating func prune(now: Double) -> Bool {
        if let newest = entries.map(\.lastTime).max(), now - newest >= linger {
            entries.removeAll()
        }
        return !entries.isEmpty
    }

    public mutating func clear() { entries.removeAll() }

    /// The subtitle to show: the newest entry's, with its repeat count ("Add Selection ×3").
    public var currentSubtitle: String? {
        guard let last = entries.last, let subtitle = last.subtitle else { return nil }
        return last.count > 1 ? "\(subtitle) ×\(last.count)" : subtitle
    }

    private mutating func append(_ e: KeycapEntry) {
        entries.append(e)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
    }
}
