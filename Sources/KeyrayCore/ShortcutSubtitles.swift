/// Shortcut Subtitles: what a shortcut does in the frontmost app, from bundled dictionaries of each
/// app's documented default key bindings. A shortcut that is not in the dictionary gets no
/// subtitle (a wrong name is worse than none). Keys are keycap labels (`KeyStroke.label`), so
/// modifiers are written in Apple's order: ⌃⌥⇧⌘.
public enum ShortcutSubtitles {
    public struct AppDictionary: Sendable {
        public let name: String
        public let bindings: [String: String]
    }

    /// The subtitle for `stroke` in the app with this bundle id, falling back to the handful of
    /// shortcuts that mean the same thing everywhere on macOS.
    public static func subtitle(for stroke: KeyStroke, bundleID: String?) -> String? {
        let label = stroke.label
        if let id = bundleID, let app = apps[id], let name = app.bindings[label] { return name }
        return systemWide[label]
    }

    /// The display name of a supported app.
    public static func appName(bundleID: String?) -> String? { bundleID.flatMap { apps[$0]?.name } }

    public static let systemWide: [String: String] = [
        "⌘C": "Copy", "⌘V": "Paste", "⌘X": "Cut", "⌘Z": "Undo", "⇧⌘Z": "Redo", "⌘A": "Select All",
        "⌘⇥": "Switch Apps", "⌘␣": "Spotlight", "⇧⌘3": "Screenshot", "⇧⌘4": "Screenshot Area", "⇧⌘5": "Screenshot Tools",
    ]

    /// Readline keys shared by Terminal and iTerm2.
    static let shell: [String: String] = [
        "⌃C": "Interrupt", "⌃D": "End of Input", "⌃Z": "Suspend Job", "⌃R": "Search History",
        "⌃A": "Start of Line", "⌃E": "End of Line", "⌃L": "Clear Screen", "⌃U": "Delete to Line Start",
        "⌃K": "Delete to Line End", "⌃W": "Delete Previous Word",
    ]

    static let browser: [String: String] = [
        "⌘T": "New Tab", "⇧⌘T": "Reopen Closed Tab", "⌘W": "Close Tab", "⌘L": "Address Bar", "⌘R": "Reload",
        "⌘F": "Find", "⌘D": "Bookmark Page", "⌃⇥": "Next Tab", "⌃⇧⇥": "Previous Tab", "⌘[": "Back", "⌘]": "Forward",
        "⌥⌘→": "Next Tab", "⌥⌘←": "Previous Tab", "⌘0": "Actual Size",
    ]

    public static let apps: [String: AppDictionary] = [
        "com.microsoft.VSCode": AppDictionary(name: "VS Code", bindings: [
            "⇧⌘P": "Command Palette", "⌘P": "Quick Open", "⌘B": "Toggle Sidebar", "⌘J": "Toggle Panel",
            "⌃`": "Toggle Terminal", "⌘/": "Toggle Line Comment", "⌘D": "Add Selection to Next Match",
            "⌥⇧F": "Format Document", "⇧⌘F": "Search in Files", "⇧⌘E": "Explorer", "⇧⌘X": "Extensions",
            "⌃⇧G": "Source Control", "F12": "Go to Definition", "⌥F12": "Peek Definition", "⇧F12": "Show References",
            "F2": "Rename Symbol", "⌘\\": "Split Editor", "⌥↑": "Move Line Up", "⌥↓": "Move Line Down",
            "⌥⇧↓": "Copy Line Down", "⌥⇧↑": "Copy Line Up", "⌘L": "Expand Line Selection", "⇧⌘K": "Delete Line",
            "⌘↩": "Insert Line Below", "⌘,": "Settings", "⌃G": "Go to Line", "⇧⌘O": "Go to Symbol",
            "⌘W": "Close Editor", "⇧⌘T": "Reopen Closed Editor", "⌘F": "Find", "⌥⌘F": "Replace", "⌘S": "Save",
        ]),
        "com.apple.dt.Xcode": AppDictionary(name: "Xcode", bindings: [
            "⌘R": "Run", "⌘B": "Build", "⌘U": "Test", "⌘.": "Stop", "⇧⌘K": "Clean Build Folder",
            "⇧⌘O": "Open Quickly", "⌘/": "Comment Selection", "⌃I": "Re-Indent", "⌘0": "Navigator",
            "⌥⌘0": "Inspectors", "⇧⌘Y": "Debug Area", "⇧⌘L": "Library", "⌃⌘E": "Edit All in Scope",
            "⌘\\": "Toggle Breakpoint", "⌃⌘J": "Jump to Definition", "⇧⌘F": "Find in Workspace",
            "⌥⌘[": "Move Line Up", "⌥⌘]": "Move Line Down", "⌥⌘↩": "Canvas", "⌘S": "Save", "⌘F": "Find",
        ]),
        "com.apple.Terminal": AppDictionary(name: "Terminal", bindings: shell.merging([
            "⌘K": "Clear Scrollback", "⌘T": "New Tab", "⌘N": "New Window", "⌘D": "Split Pane", "⇧⌘D": "Close Split Pane",
            "⌘F": "Find",
        ]) { a, _ in a }),
        "com.googlecode.iterm2": AppDictionary(name: "iTerm2", bindings: shell.merging([
            "⌘K": "Clear Buffer", "⌘T": "New Tab", "⌘N": "New Window", "⌘D": "Split Vertically",
            "⇧⌘D": "Split Horizontally", "⇧⌘H": "Paste History", "⌘;": "Autocomplete", "⌘↩": "Toggle Full Screen",
            "⌘F": "Find",
        ]) { a, _ in a }),
        "com.google.Chrome": AppDictionary(name: "Chrome", bindings: browser.merging([
            "⇧⌘R": "Hard Reload", "⌥⌘I": "Developer Tools", "⌥⌘J": "JavaScript Console",
            "⇧⌘N": "New Incognito Window", "⇧⌘B": "Bookmarks Bar", "⌘Y": "History", "⇧⌘J": "Downloads",
        ]) { a, _ in a }),
        "com.apple.Safari": AppDictionary(name: "Safari", bindings: browser.merging([
            "⌥⌘I": "Web Inspector", "⇧⌘\\": "Tab Overview", "⇧⌘N": "New Private Window", "⌥⌘L": "Downloads",
            "⌘Y": "History", "⌥⌘E": "Empty Caches",
        ]) { a, _ in a }),
        "com.apple.finder": AppDictionary(name: "Finder", bindings: [
            "⇧⌘G": "Go to Folder", "⌘↑": "Enclosing Folder", "⌘↓": "Open", "⌘⌫": "Move to Trash",
            "⇧⌘N": "New Folder", "⌘I": "Get Info", "⇧⌘.": "Show Hidden Files", "⌘1": "Icon View",
            "⌘2": "List View", "⌘3": "Column View", "⌘4": "Gallery View", "⌘D": "Duplicate", "⌘E": "Eject",
            "⌘F": "Find", "⇧⌘A": "Applications", "⇧⌘H": "Home", "⇧⌘D": "Desktop", "⌥⌘L": "Downloads",
            "⌘N": "New Window", "⌘T": "New Tab", "⇧⌘⌫": "Empty Trash", "⌘Y": "Quick Look",
        ]),
        "com.apple.iWork.Keynote": AppDictionary(name: "Keynote", bindings: [
            "⌥⌘P": "Play Slideshow", "⇧⌘N": "New Slide", "⌘D": "Duplicate", "⌥⌘G": "Group",
            "⌥⇧⌘G": "Ungroup", "⌥⌘I": "Show Inspector", "⌘K": "Add Link", "⌘S": "Save",
        ]),
        "com.microsoft.Powerpoint": AppDictionary(name: "PowerPoint", bindings: [
            "⇧⌘↩": "Play from Start", "⌘↩": "Play from Current Slide", "⇧⌘N": "New Slide", "⌘D": "Duplicate",
            "⌥⌘G": "Group", "⌥⇧⌘G": "Ungroup", "⌘K": "Insert Link", "⌘S": "Save",
        ]),
        "com.figma.Desktop": AppDictionary(name: "Figma", bindings: [
            "⌘D": "Duplicate", "⌘G": "Group Selection", "⇧⌘G": "Ungroup", "⌥⌘G": "Frame Selection",
            "⌘/": "Quick Actions", "⌘\\": "Show/Hide UI", "⇧⌘H": "Show/Hide Selection", "⇧⌘L": "Lock/Unlock",
            "⌥⌘K": "Create Component", "⇧⌘K": "Place Image",
        ]),
    ]

    /// A short sample per app for the preview (no Input Monitoring needed), in the order a demo
    /// would press them. Every entry has a subtitle in that app's dictionary.
    public static func previewStrokes(bundleID: String?) -> [KeyStroke] {
        let cmd: KeyModifiers = [.command], shiftCmd: KeyModifiers = [.shift, .command], ctrl: KeyModifiers = [.control]
        switch bundleID {
        case "com.microsoft.VSCode":
            return [KeyStroke(keyCode: 35, modifiers: shiftCmd), KeyStroke(keyCode: 35, modifiers: cmd),
                    KeyStroke(keyCode: 2, modifiers: cmd), KeyStroke(keyCode: 2, modifiers: cmd), KeyStroke(keyCode: 44, modifiers: cmd)]
        case "com.apple.Terminal", "com.googlecode.iterm2":
            return [KeyStroke(keyCode: 15, modifiers: ctrl), KeyStroke(keyCode: 8, modifiers: ctrl), KeyStroke(keyCode: 40, modifiers: cmd)]
        case "com.apple.dt.Xcode":
            return [KeyStroke(keyCode: 11, modifiers: cmd), KeyStroke(keyCode: 32, modifiers: cmd), KeyStroke(keyCode: 15, modifiers: cmd)]
        case "com.apple.iWork.Keynote":
            return [KeyStroke(keyCode: 45, modifiers: shiftCmd), KeyStroke(keyCode: 2, modifiers: cmd), KeyStroke(keyCode: 35, modifiers: [.option, .command])]
        default: // Chrome and anything else: browser keys
            return [KeyStroke(keyCode: 37, modifiers: cmd), KeyStroke(keyCode: 17, modifiers: shiftCmd),
                    KeyStroke(keyCode: 15, modifiers: cmd), KeyStroke(keyCode: 34, modifiers: [.option, .command])]
        }
    }
}
