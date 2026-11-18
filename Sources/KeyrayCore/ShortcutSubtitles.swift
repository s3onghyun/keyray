/// Shortcut Subtitles: what a shortcut does in the frontmost app, from bundled dictionaries of each
/// app's documented default key bindings. A shortcut that is not in the dictionary gets no
/// subtitle (a wrong name is worse than none). Keys are keycap labels (`KeyStroke.label`), so
/// modifiers are written in Apple's order: ⌃⌥⇧⌘.
public enum ShortcutSubtitles {
    public struct AppDictionary: Sendable {
        public let name: String
        public let bindings: [String: String]
        /// Keycap labels the preview plays, in order (repeats show the ×N count).
        public let sample: [String]
        /// The vendor pages the bindings come from.
        public let sources: [String]
    }

    /// The subtitle for `stroke` in the app with this bundle id, falling back to the handful of
    /// shortcuts that mean the same thing everywhere on macOS. In VS Code, the user's `imported`
    /// keybindings come first.
    public static func subtitle(for stroke: KeyStroke, bundleID: String?, imported: ImportedKeybindings? = nil) -> String? {
        let label = stroke.label
        if let imported, let id = bundleID, VSCodeKeybindings.bundleIDs.contains(id) {
            if let name = imported.bindings[label] { return name }
            if imported.silenced.contains(label) { return nil }
        }
        if let app = dictionary(for: bundleID), let name = app.bindings[label] { return name }
        return systemWide[label]
    }

    /// The bundled dictionary for an app, including builds that share another app's defaults.
    public static func dictionary(for bundleID: String?) -> AppDictionary? {
        guard let id = bundleID else { return nil }
        return apps[id] ?? aliases[id].flatMap { apps[$0] }
    }

    /// Bundle ids that use another app's default key bindings.
    public static let aliases: [String: String] = [
        "com.microsoft.VSCodeInsiders": "com.microsoft.VSCode", "com.vscodium": "com.microsoft.VSCode",
        // JetBrains IDEs share the default macOS keymap; Android Studio is based on IntelliJ IDEA.
        "com.jetbrains.intellij.ce": "com.jetbrains.intellij", "com.jetbrains.pycharm": "com.jetbrains.intellij",
        "com.jetbrains.pycharm.ce": "com.jetbrains.intellij", "com.jetbrains.WebStorm": "com.jetbrains.intellij",
        "com.jetbrains.goland": "com.jetbrains.intellij", "com.jetbrains.CLion": "com.jetbrains.intellij",
        "com.google.android.studio": "com.jetbrains.intellij",
    ]

    /// The display name of a supported app.
    public static func appName(bundleID: String?) -> String? { dictionary(for: bundleID)?.name }

    /// Shortcuts that mean the same everywhere (https://support.apple.com/en-us/102650,
    /// screenshots: https://support.apple.com/en-us/102646).
    public static let systemWide: [String: String] = [
        "⌘C": "Copy", "⌘V": "Paste", "⌘X": "Cut", "⌘Z": "Undo", "⇧⌘Z": "Redo", "⌘A": "Select All",
        "⌘⇥": "Switch Apps", "⌘␣": "Spotlight", "⇧⌘3": "Screenshot", "⇧⌘4": "Screenshot Area", "⇧⌘5": "Screenshot Tools",
    ]

    /// Shell keys shared by Terminal and iTerm2: zsh's default (emacs) line editor and the terminal's
    /// signal keys.
    static let shell: [String: String] = [
        "⌃C": "Interrupt", "⌃D": "End of Input", "⌃Z": "Suspend Job", "⌃R": "Search History",
        "⌃A": "Start of Line", "⌃E": "End of Line", "⌃L": "Clear Screen", "⌃K": "Delete to Line End",
        "⌃W": "Delete Previous Word",
    ]
    static let shellSources = [
        "https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html",
        "termios(4): ⌃C intr, ⌃Z susp, ⌃D eof",
    ]

    public static let apps: [String: AppDictionary] = [
        "com.microsoft.VSCode": AppDictionary(name: "VS Code", bindings: [
            "⇧⌘P": "Command Palette", "⌘P": "Quick Open", "⌘B": "Toggle Sidebar", "⌘J": "Toggle Panel",
            "⌃`": "Toggle Terminal", "⌘/": "Toggle Line Comment", "⌘D": "Add Selection to Next Match",
            "⌥⇧F": "Format Document", "⇧⌘F": "Show Search", "⇧⌘E": "Show Explorer", "⇧⌘X": "Show Extensions",
            "⌃⇧G": "Show Source Control", "F12": "Go to Definition", "⌥F12": "Peek Definition", "⇧F12": "Show References",
            "F2": "Rename Symbol", "⌘\\": "Split Editor", "⌥↑": "Move Line Up", "⌥↓": "Move Line Down",
            "⌥⇧↓": "Copy Line Down", "⌥⇧↑": "Copy Line Up", "⌘L": "Select Current Line", "⇧⌘K": "Delete Line",
            "⌘↩": "Insert Line Below", "⌘,": "User Settings", "⌃G": "Go to Line", "⇧⌘O": "Go to Symbol",
            "⌘W": "Close Editor", "⇧⌘T": "Reopen Closed Editor", "⌘F": "Find", "⌥⌘F": "Replace", "⌘S": "Save",
        ], sample: ["⇧⌘P", "⌘P", "⌘D", "⌘D", "⌘/"], sources: [
            "https://code.visualstudio.com/shortcuts/keyboard-shortcuts-macos.pdf",
            "https://code.visualstudio.com/docs/reference/default-keybindings",
            "https://code.visualstudio.com/docs/editing/getting-started/tips-and-tricks",
        ]),
        "com.apple.dt.Xcode": AppDictionary(name: "Xcode", bindings: [
            "⌘R": "Run", "⌘B": "Build", "⌘U": "Test", "⌘.": "Stop", "⇧⌘K": "Clean", "⌥⇧⌘K": "Clean Build Folder",
            "⇧⌘O": "Open Quickly", "⌘/": "Comment Selection", "⇧⌘Y": "Debug Area", "⌃⌘E": "Edit All in Scope",
            "⌘\\": "Add Breakpoint", "⇧⌘F": "Find in Workspace", "⌥⌘[": "Move Line Up", "⌥⌘]": "Move Line Down",
        ], sample: ["⌘B", "⌘U", "⌘R"], sources: [
            "https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_help-command_shortcuts/MenuCommands/MenuCommands014.html",
            "https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/chapters/05-running_tests.html",
        ]),
        "com.apple.Terminal": AppDictionary(name: "Terminal", bindings: shell.merging([
            "⌘K": "Clear to Start", "⌘T": "New Tab", "⌘N": "New Window", "⌘D": "Split Pane", "⇧⌘D": "Close Split Pane",
        ]) { a, _ in a }, sample: ["⌃R", "⌃C", "⌘K"], sources: [
            "https://support.apple.com/guide/terminal/keyboard-shortcuts-trmlshtcts/mac",
        ] + shellSources),
        "com.googlecode.iterm2": AppDictionary(name: "iTerm2", bindings: shell.merging([
            "⌘D": "Split Vertically", "⇧⌘D": "Split Horizontally", "⇧⌘H": "Paste History", "⌘;": "Autocomplete",
            "⌘↩": "Toggle Full Screen",
        ]) { a, _ in a }, sample: ["⌃R", "⌃C", "⌘D"], sources: [
            "https://iterm2.com/documentation-one-page.html",
        ] + shellSources),
        "com.google.Chrome": AppDictionary(name: "Chrome", bindings: [
            "⌘T": "New Tab", "⇧⌘T": "Reopen Closed Tab", "⌘W": "Close Tab", "⌘L": "Address Bar", "⌘F": "Find",
            "⌘D": "Bookmark Page", "⌘[": "Back", "⌘]": "Forward", "⌥⌘→": "Next Tab", "⌥⌘←": "Previous Tab",
            "⌘0": "Default Size", "⇧⌘R": "Hard Reload", "⌥⌘I": "Developer Tools", "⌥⌘J": "JavaScript Console",
            "⇧⌘N": "New Incognito Window", "⇧⌘B": "Bookmarks Bar", "⌘Y": "History", "⇧⌘J": "Downloads",
        ], sample: ["⌘L", "⇧⌘T", "⌥⌘I"], sources: [
            "https://support.google.com/chrome/answer/157179?hl=en&co=GENIE.Platform%3DDesktop",
        ]),
        "com.apple.Safari": AppDictionary(name: "Safari", bindings: [
            "⇧⌘\\": "Tab Overview", "⇧⌘T": "Reopen Closed Tab", "⌃⇥": "Next Tab", "⌃⇧⇥": "Previous Tab",
            "⇧⌘R": "Reader", "⇧⌘D": "Add to Reading List", "⌃⌘1": "Bookmarks Sidebar", "⌘L": "Smart Search Field",
        ], sample: ["⌘L", "⇧⌘T", "⇧⌘\\"], sources: [
            "https://support.apple.com/guide/safari/keyboard-and-other-shortcuts-cpsh003/mac",
        ]),
        "org.mozilla.firefox": AppDictionary(name: "Firefox", bindings: [
            "⌘T": "New Tab", "⌘N": "New Window", "⇧⌘P": "New Private Window", "⌘W": "Close Tab",
            "⇧⌘T": "Reopen Closed Tab", "⌘L": "Focus Address Bar", "⌘R": "Reload", "⇧⌘R": "Reload Override Cache",
            "⌘F": "Find in Page", "⌘D": "Bookmark Page", "⇧⌘B": "Bookmarks Toolbar", "⌘B": "Bookmarks Sidebar",
            "⇧⌘H": "History Sidebar", "⌘J": "Downloads", "⌥⌘I": "Developer Tools", "⌥⌘K": "Web Console",
            "⌥⌘C": "Inspector", "⌥⌘M": "Responsive Design View", "⌘U": "Page Source", "⌥⌘→": "Next Tab",
            "⌥⌘←": "Previous Tab", "⌘[": "Back", "⌘]": "Forward", "⌘0": "Zoom Reset", "⇧⌘F": "Toggle Full Screen",
        ], sample: ["⌘L", "⇧⌘T", "⌥⌘I"], sources: [
            "https://support.mozilla.org/en-US/kb/keyboard-shortcuts-perform-firefox-tasks-quickly",
        ]),
        "com.apple.finder": AppDictionary(name: "Finder", bindings: [
            "⇧⌘G": "Go to Folder", "⌘↑": "Enclosing Folder", "⌘↓": "Open", "⌘⌫": "Move to Trash",
            "⇧⌘N": "New Folder", "⌘I": "Get Info", "⌘1": "Icon View", "⌘2": "List View", "⌘3": "Column View",
            "⌘4": "Gallery View", "⌘D": "Duplicate", "⌘E": "Eject", "⇧⌘H": "Home", "⇧⌘D": "Desktop",
            "⌥⌘L": "Downloads", "⇧⌘⌫": "Empty Trash", "⌘Y": "Quick Look",
        ], sample: ["⇧⌘G", "⌘I", "⌘Y"], sources: [
            "https://support.apple.com/en-us/102650",
        ]),
        "com.apple.iWork.Keynote": AppDictionary(name: "Keynote", bindings: [
            "⌥⌘P": "Play Slideshow", "⌥⌘G": "Group", "⌥⇧⌘G": "Ungroup", "⌥⌘I": "Show/Hide Inspector", "⌘K": "Add Link",
        ], sample: ["⌥⌘P", "⌥⌘G", "⌘K"], sources: [
            "https://support.apple.com/guide/keynote/keyboard-shortcuts-tanfde4a3e6d/mac",
        ]),
        "com.microsoft.Powerpoint": AppDictionary(name: "PowerPoint", bindings: [
            "⇧⌘↩": "Play from Start", "⌘↩": "Play from Current Slide", "⇧⌘N": "New Slide",
            "⌥⌘G": "Group", "⌥⇧⌘G": "Ungroup", "⌘K": "Insert Link",
        ], sample: ["⇧⌘N", "⌘K", "⌘↩"], sources: [
            "https://support.microsoft.com/en-us/office/keyboard-shortcuts-in-powerpoint-for-mac-f25f92b3-b0a8-4c60-aec8-954b72aa81ad",
            "https://support.microsoft.com/en-us/accessibility/powerpoint/use-keyboard-shortcuts-to-deliver-powerpoint-presentations",
        ]),
        "com.figma.Desktop": AppDictionary(name: "Figma", bindings: [
            "⌘G": "Group Selection", "⇧⌘G": "Ungroup", "⌥⌘G": "Frame Selection", "⌘K": "Actions Menu",
            "⌘\\": "Show/Hide UI", "⇧⌘\\": "Minimize UI", "⇧⌘H": "Show/Hide Selection", "⇧⌘L": "Lock/Unlock",
            "⌥⌘K": "Create Component", "⇧⌘K": "Place Image",
        ], sample: ["⌘K", "⌥⌘G", "⇧⌘H"], sources: [
            "https://help.figma.com/hc/en-us/articles/360039832054",
            "https://help.figma.com/hc/en-us/articles/23570416033943-Use-the-actions-menu-in-Figma-Design",
            "https://help.figma.com/hc/en-us/articles/41414918021271-Hide-or-minimize-the-UI",
            "https://help.figma.com/hc/en-us/articles/360041112614-Toggle-visibility-to-hide-layers",
            "https://help.figma.com/hc/en-us/articles/360041596573-Lock-and-unlock-layers",
            "https://help.figma.com/hc/en-us/articles/360038663154-Create-components-to-reuse-in-designs",
            "https://help.figma.com/hc/en-us/articles/360040028034-Add-images-and-videos-to-designs",
        ]),
        "com.tinyspeck.slackmacgap": AppDictionary(name: "Slack", bindings: [
            "⌘N": "Compose New Message", "⇧⌘K": "Browse DMs", "⇧⌘Y": "Set Status", "⌘,": "Preferences",
            "⌘.": "Hide Right Sidebar", "⇧⌘N": "New Canvas", "⌘O": "Upload File", "⌘G": "Start Search",
            "⌘F": "Search Conversation", "⇧⌘H": "Huddle", "⇧⌘␣": "Toggle Huddle Mute", "⌃⌘F": "Toggle Full Screen",
            "⌘J": "Jump to Unread", "⌥⇧↑": "Previous Unread", "⌥⇧↓": "Next Unread", "⌥↑": "Previous Channel",
            "⌥↓": "Next Channel", "⌘[": "Back", "⌘]": "Forward", "⇧⌘M": "Activity", "⇧⌘T": "Threads",
            "⇧⌘L": "Browse Channels", "⇧⌘A": "All Unreads", "esc": "Mark Read", "⇧esc": "Mark All Read",
        ], sample: ["⌘N", "⇧⌘H", "⌘J"], sources: [
            "https://slack.com/help/articles/201374536-Slack-keyboard-shortcuts",
        ]),
        "notion.id": AppDictionary(name: "Notion", bindings: [
            "⌘P": "Search", "⌘L": "Copy Page Link", "⌘[": "Back", "⌘]": "Forward", "⇧⌘L": "Toggle Dark Mode",
            "⌘N": "New Page", "⇧⌘N": "New Window", "⌘T": "New Tab", "⇧⌘T": "Reopen Closed Tab",
            "⇧⌘M": "Comment", "⌘B": "Bold", "⌘I": "Italic", "⌘U": "Underline", "⇧⌘S": "Strikethrough",
            "⌘E": "Inline Code", "⌥⌘0": "Text", "⌥⌘1": "Heading 1", "⌥⌘2": "Heading 2", "⌥⌘3": "Heading 3",
            "⌥⌘4": "To-do", "⌥⌘8": "Code Block", "⌘D": "Duplicate", "⌘/": "Edit Block", "⇧⌘U": "Up One Level",
        ], sample: ["⌘P", "⌥⌘1", "⇧⌘M"], sources: [
            "https://www.notion.com/help/keyboard-shortcuts",
        ]),
        "com.jetbrains.intellij": AppDictionary(name: "JetBrains IDEs", bindings: [
            "⇧⌘A": "Find Action", "⌥↩": "Show Intention Actions", "⌘E": "Recent Files", "⌥F7": "Find Usages",
            "⌘,": "Settings", "⌘N": "Generate", "⌃R": "Run", "⌃D": "Debug", "⌥⌘L": "Reformat Code",
            "⌘/": "Line Comment", "⌘B": "Go to Declaration", "⇧⌘O": "Go to File", "⌥⌘O": "Go to Symbol",
            "⇧⌘F": "Find in Files", "⌘L": "Go to Line", "⇧F6": "Rename", "⌃T": "Refactor This",
            "⌘D": "Duplicate Line", "⌥⇧↑": "Move Line Up", "⌥⇧↓": "Move Line Down", "⌥↑": "Extend Selection",
            "⌘F8": "Toggle Breakpoint", "⌘F9": "Build Project", "⌥F12": "Terminal",
        ], sample: ["⇧⌘A", "⌥⌘L", "⌃R"], sources: [
            "https://www.jetbrains.com/help/idea/reference-keymap-mac-default.html",
            "https://developer.android.com/studio/intro/keyboard-shortcuts",
        ]),
        "us.zoom.xos": AppDictionary(name: "Zoom", bindings: [
            "⇧⌘A": "Mute/Unmute Audio", "⇧⌘V": "Start/Stop Video", "⇧⌘S": "Start/Stop Share",
            "⇧⌘T": "Pause/Resume Share", "⇧⌘R": "Local Recording", "⇧⌘P": "Pause/Resume Recording",
            "⇧⌘W": "Switch View", "⌘U": "Participants", "⇧⌘H": "Meeting Chat", "⌘I": "Invite",
            "⇧⌘I": "Copy Invite Link", "⌥Y": "Raise/Lower Hand", "⇧⌘F": "Full Screen", "⇧⌘M": "Minimal Window",
            "⌃⌥⌘H": "Floating Controls", "⌃⌘M": "Mute All", "⌃⌘U": "Unmute All", "⌘J": "Join Meeting",
            "⌃⌘V": "Start Meeting", "⇧⌘Y": "Reactions", "⌘W": "Close Window",
        ], sample: ["⇧⌘A", "⇧⌘V", "⇧⌘S"], sources: [
            "https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067050",
        ]),
        "com.microsoft.teams2": AppDictionary(name: "Microsoft Teams", bindings: [
            "⌘.": "Keyboard Shortcuts", "⌘E": "Search", "⌘N": "New Chat", "⌘,": "Settings", "⌘G": "Go to Chat",
            "⌘J": "Jump to Newest", "⌘F": "Search Chat", "⌘D": "Toggle Details", "⌘[": "Go Back", "⌘]": "Go Forward",
            "⇧⌘X": "Expand Compose Box", "⌘K": "Insert Link", "⇧⌘M": "Toggle Mute", "⌥␣": "Temporarily Unmute",
            "⇧⌘O": "Toggle Video", "⇧⌘K": "Raise/Lower Hand", "⇧⌘E": "Share Content", "⇧⌘H": "End Call",
            "⌃⌘N": "Schedule Meeting", "⌘=": "Zoom In", "⌘-": "Zoom Out", "⌃0": "Reset Zoom",
        ], sample: ["⇧⌘M", "⇧⌘O", "⇧⌘E"], sources: [
            "https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2",
        ]),
    ]

    /// The stroke for a keycap label, e.g. "⇧⌘P" (the inverse of `KeyStroke.label`).
    public static func stroke(forLabel label: String) -> KeyStroke? { strokesByLabel[label] }

    private static let strokesByLabel: [String: KeyStroke] = {
        var map: [String: KeyStroke] = [:]
        for code in 0..<128 where !KeyNames.modifierKeyCodes.contains(code) {
            for raw in 0..<16 {
                let s = KeyStroke(keyCode: code, modifiers: KeyModifiers(rawValue: raw))
                if map[s.label] == nil { map[s.label] = s }
            }
        }
        return map
    }()

    /// A short sample per app for the preview (no Input Monitoring needed), in the order a demo
    /// would press them; other apps get system-wide keys. With `imported` keybindings, VS Code's
    /// sample starts with a few of the user's own.
    public static func previewStrokes(bundleID: String?, imported: ImportedKeybindings? = nil) -> [KeyStroke] {
        if let imported, let id = bundleID, VSCodeKeybindings.bundleIDs.contains(id), !imported.samples.isEmpty {
            return imported.samples + previewStrokes(bundleID: "com.microsoft.VSCode").prefix(1)
        }
        let labels = dictionary(for: bundleID)?.sample ?? ["⌘C", "⌘V", "⌘Z"]
        return labels.compactMap(stroke(forLabel:))
    }
}
