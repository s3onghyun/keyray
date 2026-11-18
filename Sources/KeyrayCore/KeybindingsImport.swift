import Foundation

/// A VS Code `keybindings.json` the user imported. Their own bindings name the shortcut in VS Code
/// (and its builds that share its key bindings) in place of the bundled default dictionary.
public struct ImportedKeybindings: Codable, Equatable, Sendable {
    /// Keycap label → subtitle.
    public var bindings: [String: String] = [:]
    /// Labels that get no subtitle at all: the file removes their default binding, or what they
    /// do depends on a `when` context the app can't see.
    public var silenced: Set<String> = []
    /// A few imported shortcuts in file order, for the preview.
    public var samples: [KeyStroke] = []
    public var fileName = "keybindings.json"

    public init() {}

    /// What the import did, for the summary shown to the user.
    public struct Summary: Equatable, Sendable {
        public var imported = 0
        public var removedDefaults = 0
        public var contextDependent = 0
        public var chords = 0
        public var unreadable = 0
    }
}

public enum VSCodeKeybindings {
    public enum ImportError: Error, Equatable {
        /// Not a JSON array, even after removing comments and trailing commas.
        case notAnArray
    }

    /// Editors that read the same `keybindings.json` format and defaults as VS Code.
    public static let bundleIDs: Set<String> = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium"]

    /// Parses a keybindings.json (JSONC: comments and trailing commas allowed).
    ///
    /// - Later entries win, as in VS Code.
    /// - `"-command"` entries remove a default, so that key gets no subtitle unless rebound.
    /// - An entry with a `when` clause only names its key if nothing else claims it; when the key
    ///   means different things in different contexts the app can't see, it stays silent.
    /// - Chords (`cmd+k cmd+s`) and unknown keys are skipped.
    public static func parse(_ text: String, defaults: [String: String] = ShortcutSubtitles.apps["com.microsoft.VSCode"]?.bindings ?? [:],
                             fileName: String = "keybindings.json") throws -> (ImportedKeybindings, ImportedKeybindings.Summary) {
        let cleaned = stripTrailingCommas(stripComments(text))
        guard let array = (try? JSONSerialization.jsonObject(with: Data(cleaned.utf8))) as? [Any] else { throw ImportError.notAnArray }

        var summary = ImportedKeybindings.Summary()
        var result = ImportedKeybindings()
        result.fileName = fileName
        // Per label, in file order: the title it would show and whether it is limited by `when`.
        var claims: [String: [(title: String, scoped: Bool)]] = [:]
        var removed: Set<String> = []
        var order: [String] = []
        var strokes: [String: KeyStroke] = [:]

        for case let entry as [String: Any] in array {
            guard let key = entry["key"] as? String, let command = entry["command"] as? String, !command.isEmpty else {
                summary.unreadable += 1
                continue
            }
            if key.trimmingCharacters(in: .whitespaces).contains(" ") {
                summary.chords += 1
                continue
            }
            guard let stroke = stroke(for: key) else {
                summary.unreadable += 1
                continue
            }
            let label = stroke.label
            if command.hasPrefix("-") {
                // Removes a default binding of this key; the user's own bindings of it stay.
                removed.insert(label)
                continue
            }
            let when = (entry["when"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            claims[label, default: []].append((title(forCommand: command), !when.isEmpty))
            if strokes[label] == nil { order.append(label); strokes[label] = stroke }
        }

        for label in removed where claims[label] == nil {
            result.silenced.insert(label)
            summary.removedDefaults += 1
        }
        for (label, list) in claims {
            let titles = Set(list.map(\.title))
            let scoped = list.contains { $0.scoped }
            let defaultTitle = removed.contains(label) ? nil : defaults[label]
            if !scoped {
                result.bindings[label] = list.last!.title
            } else if titles.count == 1 && (defaultTitle == nil || defaultTitle == list[0].title) {
                result.bindings[label] = list[0].title
            } else {
                result.silenced.insert(label)
                summary.contextDependent += 1
                continue
            }
            summary.imported += 1
        }
        result.samples = order.filter { result.bindings[$0] != nil }.compactMap { strokes[$0] }
            .filter { $0.isShortcut || $0.isFunctionKey }.prefix(3).map { $0 }
        return (result, summary)
    }

    // MARK: Keys

    private static let modifierNames: [String: KeyModifiers] = [
        "cmd": .command, "meta": .command, "ctrl": .control, "alt": .option, "option": .option, "shift": .shift,
    ]

    private static let namedKeys: [String: Int] = [
        "enter": 36, "tab": 48, "space": 49, "backspace": 51, "escape": 53, "delete": 117,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    /// Physical key codes VS Code writes in brackets, e.g. `[KeyP]`, `[Digit1]`, `[Backquote]`.
    private static let codeNames: [String: String] = [
        "backquote": "`", "minus": "-", "equal": "=", "bracketleft": "[", "bracketright": "]",
        "backslash": "\\", "semicolon": ";", "quote": "'", "comma": ",", "period": ".", "slash": "/",
        "enter": "enter", "tab": "tab", "space": "space", "backspace": "backspace", "escape": "escape",
        "delete": "delete", "arrowleft": "left", "arrowright": "right", "arrowup": "up", "arrowdown": "down",
    ]

    private static let characterCodes: [String: Int] = Dictionary(
        KeyNames.ansiCharacters.filter { $0.value != " " }.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
    private static let functionCodes: [Int: Int] = Dictionary(uniqueKeysWithValues: KeyNames.functionKeys.map { ($0.value, $0.key) })

    /// One VS Code key, e.g. `cmd+shift+p`, `ctrl+\``, `alt+f12`, `cmd+[KeyK]`. Nil if unknown.
    public static func stroke(for key: String) -> KeyStroke? {
        var parts = key.lowercased().trimmingCharacters(in: .whitespaces).components(separatedBy: "+")
        // `cmd++` would split into a trailing empty pair; `+` is not a key VS Code writes this way.
        guard let last = parts.popLast(), !last.isEmpty else { return nil }
        var modifiers: KeyModifiers = []
        for part in parts {
            guard let m = modifierNames[part] else { return nil }
            modifiers.insert(m)
        }
        guard let code = keyCode(for: last) else { return nil }
        return KeyStroke(keyCode: code, modifiers: modifiers)
    }

    private static func keyCode(for name: String) -> Int? {
        var name = name
        if name.hasPrefix("[") && name.hasSuffix("]") {
            let code = String(name.dropFirst().dropLast())
            if code.hasPrefix("key"), code.count == 4 { name = String(code.suffix(1)) }
            else if code.hasPrefix("digit"), code.count == 6 { name = String(code.suffix(1)) }
            else if let mapped = codeNames[code] { name = mapped }
            else if code.hasPrefix("f") { name = code }
            else { return nil }
        }
        if let code = namedKeys[name] { return code }
        if name.count > 1, name.hasPrefix("f"), let n = Int(name.dropFirst()) { return functionCodes[n] }
        return characterCodes[name]
    }

    // MARK: Command names

    /// Names for common commands whose id doesn't read well on its own.
    static let knownCommands: [String: String] = [
        "workbench.action.showCommands": "Command Palette",
        "workbench.action.quickOpen": "Quick Open",
        "workbench.action.toggleSidebarVisibility": "Toggle Sidebar",
        "workbench.action.togglePanel": "Toggle Panel",
        "workbench.action.terminal.toggleTerminal": "Toggle Terminal",
        "workbench.action.terminal.new": "New Terminal",
        "workbench.action.files.save": "Save",
        "workbench.action.files.newUntitledFile": "New File",
        "workbench.action.closeActiveEditor": "Close Editor",
        "workbench.action.splitEditor": "Split Editor",
        "workbench.action.findInFiles": "Search in Files",
        "workbench.action.gotoLine": "Go to Line",
        "workbench.action.openSettings": "Settings",
        "workbench.action.zenMode": "Zen Mode",
        "workbench.action.toggleZenMode": "Zen Mode",
        "workbench.view.explorer": "Explorer",
        "workbench.view.scm": "Source Control",
        "workbench.view.extensions": "Extensions",
        "workbench.view.debug": "Run and Debug",
        "editor.action.commentLine": "Toggle Line Comment",
        "editor.action.formatDocument": "Format Document",
        "editor.action.revealDefinition": "Go to Definition",
        "editor.action.addSelectionToNextFindMatch": "Add Selection to Next Match",
        "editor.action.rename": "Rename Symbol",
        "editor.action.quickFix": "Quick Fix",
        "editor.action.triggerSuggest": "Trigger Suggest",
        "editor.action.copyLinesDownAction": "Copy Line Down",
        "editor.action.copyLinesUpAction": "Copy Line Up",
        "editor.action.moveLinesDownAction": "Move Line Down",
        "editor.action.moveLinesUpAction": "Move Line Up",
        "editor.action.deleteLines": "Delete Line",
        "editor.action.insertCursorAbove": "Add Cursor Above",
        "editor.action.insertCursorBelow": "Add Cursor Below",
        "editor.action.selectHighlights": "Select All Occurrences",
        "editor.action.marker.next": "Next Problem",
        "workbench.action.debug.start": "Start Debugging",
        "workbench.action.debug.run": "Run Without Debugging",
        "workbench.action.tasks.build": "Run Build Task",
        "workbench.action.tasks.runTask": "Run Task",
    ]

    /// Words that only say where a command lives, not what it does.
    private static let namespaceWords: Set<String> = ["workbench", "action", "actions", "editor", "view", "files", "extension"]

    /// A short title for a command id: a known name, or the id's last part in words
    /// (`editor.action.joinLines` → "Join Lines", `workbench.action.terminal.kill` → "Terminal Kill").
    public static func title(forCommand command: String) -> String {
        if let known = knownCommands[command] { return known }
        let segments = command.split(separator: ".").map(String.init)
        var words = splitWords(segments.last ?? command)
        if words.count == 1, segments.count > 1 {
            let parent = segments[segments.count - 2]
            if !namespaceWords.contains(parent.lowercased()) { words = splitWords(parent) + words }
        }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static func splitWords(_ s: String) -> [String] {
        var words: [String] = []
        var current = ""
        for ch in s {
            if ch == "_" || ch == "-" || ch == " " {
                if !current.isEmpty { words.append(current); current = "" }
            } else if ch.isUppercase, let prev = current.last, !prev.isUppercase {
                words.append(current)
                current = String(ch)
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    // MARK: JSONC

    /// Removes `//` and `/* */` comments outside strings.
    static func stripComments(_ text: String) -> String {
        var out = ""
        var chars = Array(text)[...]
        var inString = false
        while let ch = chars.first {
            chars = chars.dropFirst()
            if inString {
                out.append(ch)
                if ch == "\\", let next = chars.first { out.append(next); chars = chars.dropFirst() }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
                out.append(ch)
            } else if ch == "/", chars.first == "/" {
                while let c = chars.first, c != "\n" { chars = chars.dropFirst() }
            } else if ch == "/", chars.first == "*" {
                chars = chars.dropFirst()
                while let c = chars.first, !(c == "*" && chars.dropFirst().first == "/") { chars = chars.dropFirst() }
                chars = chars.dropFirst(2)
                out.append(" ")
            } else {
                out.append(ch)
            }
        }
        return out
    }

    /// Removes a comma that is followed (after whitespace) by `]` or `}`, outside strings.
    static func stripTrailingCommas(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var inString = false
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inString {
                out.append(ch)
                if ch == "\\", i + 1 < chars.count { out.append(chars[i + 1]); i += 1 }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
                out.append(ch)
            } else if ch == "," {
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j >= chars.count || (chars[j] != "]" && chars[j] != "}") { out.append(ch) }
            } else {
                out.append(ch)
            }
            i += 1
        }
        return out
    }
}
