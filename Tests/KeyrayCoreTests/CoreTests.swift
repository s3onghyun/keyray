import Foundation
import Testing
@testable import KeyrayCore

/// `#expect` cannot call a mutating method directly; this runs one and returns its result.
func mutate<T, R>(_ value: inout T, _ body: (inout T) -> R) -> R { body(&value) }

// MARK: - Fade timing

@Test func rippleGrowsAndFadesOverItsDuration() {
    let r = RippleTiming(duration: 0.5)
    #expect(r.scale(age: 0) == r.startScale)
    #expect(r.alpha(age: 0) == r.startAlpha)
    #expect(r.scale(age: 0.25) > r.startScale && r.scale(age: 0.25) < 1)
    #expect(abs(r.alpha(age: 0.25) - r.startAlpha / 2) < 1e-9)
    #expect(r.scale(age: 0.5) == 1)
    #expect(r.alpha(age: 0.5) == 0)
    #expect(r.alpha(age: 9) == 0)
    #expect(!r.isFinished(age: 0.49) && r.isFinished(age: 0.5))
}

@Test func rippleScaleNeverShrinks() {
    let r = RippleTiming(duration: 0.45)
    let samples = stride(from: 0.0, through: 0.5, by: 0.01).map { r.scale(age: $0) }
    #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
}

@Test func inkHoldsThenFadesLinearly() {
    let f = InkFade(hold: 3, fade: 1)
    #expect(f.alpha(age: -1) == 1) // still being drawn
    #expect(f.alpha(age: 0) == 1)
    #expect(f.alpha(age: 3) == 1)
    #expect(abs(f.alpha(age: 3.5) - 0.5) < 1e-9)
    #expect(f.alpha(age: 4) == 0)
    #expect(f.lifetime == 4)
    #expect(!f.isFinished(age: 3.99) && f.isFinished(age: 4))
}

@Test func inkWithZeroHoldStartsFadingAtOnce() {
    let f = InkFade(hold: 0, fade: 2)
    #expect(abs(f.alpha(age: 1) - 0.5) < 1e-9)
}

@Test func idleRingHidesAfterIdleSeconds() {
    let v = IdleVisibility(idleSeconds: 2)
    #expect(v.alpha(sinceLastMove: 1.9) == 1)
    #expect(v.alpha(sinceLastMove: 2 + v.fadeSeconds + 0.01) == 0)
    #expect(v.secondsUntilHide(sinceLastMove: 0.5) == 1.5)
    #expect(v.secondsUntilHide(sinceLastMove: 5) == 0)
    let never = IdleVisibility(idleSeconds: 0)
    #expect(never.alpha(sinceLastMove: 1000) == 1)
    #expect(never.secondsUntilHide(sinceLastMove: 1000) == nil)
}

@Test func laserTrailTapersAndVanishes() {
    var t = LaserTrail(duration: 0.5, maxWidth: 10)
    t.add(Point(0, 0), time: 0)
    t.add(Point(10, 0), time: 0.1)
    t.add(Point(20, 0), time: 0.2)
    #expect(t.width(age: 0) == 10)
    #expect(t.width(age: 0.25) == 5)
    #expect(t.width(age: 0.5) == 0)

    let ribbon = t.ribbon(now: 0.2)
    #expect(ribbon.count == 6)
    // Newest sample is widest: its two ribbon points are farthest apart.
    let newest = ribbon[2].distance(to: ribbon[3])
    let oldest = ribbon[0].distance(to: ribbon[5])
    #expect(newest > oldest)

    #expect(mutate(&t) { $0.prune(now: 0.6) })
    #expect(t.points.count == 1)
    #expect(!mutate(&t) { $0.prune(now: 0.71) })
    #expect(t.ribbon(now: 0.71).isEmpty)
}

@Test func laserTrailSkipsJitter() {
    var t = LaserTrail(duration: 1, maxWidth: 4)
    t.add(Point(5, 5), time: 0)
    t.add(Point(5.2, 5.1), time: 0.3)
    #expect(t.points.count == 1)
    #expect(t.points[0].time == 0.3)
}

@Test func arrowHeadPointsBackFromTheTip() throws {
    let (a, b) = try #require(arrowHead(from: Point(0, 0), to: Point(100, 0), length: 20))
    #expect(a.x < 100 && b.x < 100)
    #expect(abs(a.y + b.y) < 1e-9) // symmetric about the shaft
    #expect(abs(a.distance(to: Point(100, 0)) - 20) < 1e-9)
    #expect(arrowHead(from: Point(0, 0), to: Point(1, 1), length: 20) == nil)
}

// MARK: - Keycaps

let cmd: KeyModifiers = [.command]

@Test func keycapLabelsUseAppleModifierOrder() {
    #expect(KeyStroke(keyCode: 40, modifiers: [.command, .shift, .control, .option]).label == "⌃⌥⇧⌘K")
    #expect(KeyStroke(keyCode: 49, modifiers: cmd).label == "⌘␣")
    #expect(KeyStroke(keyCode: 124, modifiers: [.control, .function]).label == "⌃→")
    #expect(KeyStroke(keyCode: 122, modifiers: [.function]).label == "F1")
    #expect(KeyStroke(keyCode: 53, modifiers: []).label == "esc")
    #expect(KeyStroke(keyCode: 36, modifiers: []).label == "↩")
    #expect(KeyStroke(keyCode: 999, modifiers: []).label == "key 999")
}

@Test func typedTextFollowsShiftAndCapsLock() {
    #expect(KeyStroke(keyCode: 0, modifiers: []).typedText == "a")
    #expect(KeyStroke(keyCode: 0, modifiers: .shift).typedText == "A")
    #expect(KeyStroke(keyCode: 0, modifiers: .capsLock).typedText == "A")
    #expect(KeyStroke(keyCode: 0, modifiers: [.capsLock, .shift]).typedText == "a")
    #expect(KeyStroke(keyCode: 18, modifiers: .shift).typedText == "!")
    #expect(KeyStroke(keyCode: 0, modifiers: cmd).typedText == nil)
    #expect(KeyStroke(keyCode: 36, modifiers: []).typedText == nil)
}

@Test func shortcutsOnlyModeSkipsPlainTyping() {
    var feed = KeycapFeed(mode: .shortcutsOnly)
    #expect(!mutate(&feed) { $0.record(KeyStroke(keyCode: 0, modifiers: []), time: 0) })
    #expect(!mutate(&feed) { $0.record(KeyStroke(keyCode: 0, modifiers: .shift), time: 0.1) })
    #expect(mutate(&feed) { $0.record(KeyStroke(keyCode: 8, modifiers: cmd), time: 0.2) })
    #expect(mutate(&feed) { $0.record(KeyStroke(keyCode: 96, modifiers: [.function]), time: 0.3) }) // F5
    #expect(feed.entries.map { $0.display(showCount: true) } == ["⌘C", "F5"])
}

@Test func repeatedShortcutCountsUp() {
    var feed = KeycapFeed(mode: .shortcutsOnly)
    for i in 0..<3 { feed.record(KeyStroke(keyCode: 6, modifiers: cmd), time: Double(i) * 0.3) }
    #expect(feed.entries.count == 1)
    #expect(feed.entries[0].display(showCount: true) == "⌘Z ×3")
    #expect(feed.entries[0].display(showCount: false) == "⌘Z")
    // Outside the repeat window it is a new cap.
    feed.record(KeyStroke(keyCode: 6, modifiers: cmd), time: 0.6 + feed.repeatWindow + 0.01)
    #expect(feed.entries.count == 2)
}

@Test func keyRepeatEventsAlwaysCount() {
    var feed = KeycapFeed(mode: .allKeys)
    feed.record(KeyStroke(keyCode: 125, modifiers: [.function]), time: 0)
    feed.record(KeyStroke(keyCode: 125, modifiers: [.function]), time: 1.2, isRepeat: true)
    #expect(feed.entries.map { $0.display(showCount: true) } == ["↓ ×2"])
}

@Test func allKeysModeJoinsTypingIntoOneCap() {
    var feed = KeycapFeed(mode: .allKeys)
    for (i, code) in [4, 14, 37, 37, 31].enumerated() { // h e l l o
        feed.record(KeyStroke(keyCode: code, modifiers: []), time: Double(i) * 0.1)
    }
    feed.record(KeyStroke(keyCode: 36, modifiers: []), time: 0.6)
    feed.record(KeyStroke(keyCode: 1, modifiers: cmd), time: 0.7)
    #expect(feed.entries.map { $0.display(showCount: true) } == ["hello", "↩", "⌘S"])
}

@Test func longTypingKeepsTheTail() {
    var feed = KeycapFeed(mode: .allKeys)
    feed.maxTypingLength = 5
    for (i, code) in [0, 11, 8, 2, 14, 3, 5].enumerated() { // a b c d e f g
        feed.record(KeyStroke(keyCode: code, modifiers: []), time: Double(i) * 0.1)
    }
    #expect(feed.entries.last?.text == "…defg")
}

@Test func activationKeysAreHidden() {
    var feed = KeycapFeed(mode: .shortcutsOnly, hiddenStrokes: AppShortcut.activationStrokes)
    #expect(!mutate(&feed) { $0.record(AppShortcut.toggleLaser.stroke, time: 0) })
    // Caps Lock or Fn does not let a hidden shortcut through.
    var withCaps = AppShortcut.toggleInk.stroke
    withCaps.modifiers.insert(.capsLock)
    #expect(!mutate(&feed) { $0.record(withCaps, time: 0.1) })
    #expect(feed.entries.isEmpty)
    // Plain Esc (which leaves ink mode) still shows in all-keys mode.
    feed.mode = .allKeys
    #expect(mutate(&feed) { $0.record(AppShortcut.exitInk.stroke, time: 0.2) })
}

@Test func modifierOnlyPressesAndOffModeShowNothing() {
    var feed = KeycapFeed(mode: .allKeys)
    #expect(!mutate(&feed) { $0.record(KeyStroke(keyCode: 55, modifiers: cmd), time: 0) })
    feed.mode = .off
    #expect(!mutate(&feed) { $0.record(KeyStroke(keyCode: 8, modifiers: cmd), time: 0) })
}

@Test func feedClearsAfterLingerAndCapsEntries() {
    var feed = KeycapFeed(mode: .shortcutsOnly, linger: 1)
    for (i, code) in [0, 1, 2, 3, 4, 5].enumerated() {
        feed.record(KeyStroke(keyCode: code, modifiers: cmd), time: Double(i) * 0.1)
    }
    #expect(feed.entries.count == feed.maxEntries)
    #expect(feed.entries.first?.text == "⌘D")
    #expect(mutate(&feed) { $0.prune(now: 1.4) })
    #expect(!mutate(&feed) { $0.prune(now: 1.5) })
    #expect(feed.entries.isEmpty)
}

// MARK: - AppSettings

@Test func settingsRoundTrip() throws {
    var s = AppSettings()
    s.ringDiameter = 60
    s.ringMode = .clickOnly
    s.keycapMode = .allKeys
    s.inkTool = .highlighter
    s.rippleRight = RGBA(0.1, 0.2, 0.3, 0.4)
    let back = AppSettings.decoded(from: try s.encoded())
    #expect(back == s)
}

@Test func settingsFallBackToDefaults() {
    #expect(AppSettings.decoded(from: nil) == .default)
    #expect(AppSettings.decoded(from: Data("not json".utf8)) == .default)
    // Missing keys and unknown enum values keep their defaults; known keys survive.
    let partial = Data(#"{"ringDiameter": 90, "ringMode": "sparkles", "futureKey": 1}"#.utf8)
    let s = AppSettings.decoded(from: partial)
    #expect(s.ringDiameter == 90)
    #expect(s.ringMode == AppSettings.default.ringMode)
    #expect(s.keycapMode == AppSettings.default.keycapMode)
}

@Test func settingsClampOutOfRangeValues() {
    let data = Data(#"{"ringDiameter": 5000, "ringOpacity": -3, "idleHideSeconds": -1, "rippleDuration": 0, "keycapPosition": {"x": 2, "y": -1}, "inkColor": {"red": 2, "green": -1, "blue": 0.5, "alpha": 7}}"#.utf8)
    let s = AppSettings.decoded(from: data)
    #expect(s.ringDiameter == AppSettings.ringDiameterRange.upperBound)
    #expect(s.ringOpacity == 0.1)
    #expect(s.idleHideSeconds == 0)
    #expect(s.rippleDuration == AppSettings.rippleDurationRange.lowerBound)
    #expect(s.keycapPosition == UnitPoint(x: 1, y: 0))
    #expect(s.inkColor == RGBA(1, 0, 0.5, 1))
}

@Test func rippleColorsFollowTheButton() {
    let s = AppSettings()
    #expect(s.rippleColor(for: .left) == s.rippleLeft)
    #expect(s.rippleColor(for: .right) == s.rippleRight)
    #expect(s.rippleColor(for: .middle) == s.rippleMiddle)
    #expect(Set([s.rippleLeft, s.rippleRight, s.rippleMiddle].map { "\($0)" }).count == 3)
}

@Test func shortcutsAreDistinct() {
    let strokes = AppShortcut.allCases.map(\.stroke)
    #expect(Set(strokes).count == strokes.count)
    #expect(!AppShortcut.permanent.contains(.exitInk))
}

// MARK: - Themes

@Test func themeRoundTripsAndUnknownFallsBack() throws {
    var s = AppSettings()
    s.theme = .brushInk
    #expect(AppSettings.decoded(from: try s.encoded()).theme == .brushInk)
    #expect(AppSettings.decoded(from: Data(#"{"theme": "neon"}"#.utf8)).theme == .hotaru)
}

@Test func minimalStyleUsesTheUsersColors() {
    var s = AppSettings()
    s.theme = .minimal
    s.ringColor = RGBA(0.1, 0.2, 0.3)
    s.rippleRight = RGBA(0.4, 0.5, 0.6)
    #expect(s.style.ring == s.ringColor)
    #expect(s.style.ripple(for: .right) == s.rippleRight)
    s.theme = .hotaru
    #expect(s.style.ring != s.ringColor)
}

@Test func everyThemeKeepsTheThreeButtonsApart() {
    for theme in Theme.allCases {
        var s = AppSettings()
        s.theme = theme
        let colors = MouseButton.allCases.map { "\(s.style.ripple(for: $0))" }
        #expect(Set(colors).count == 3, "\(theme)")
    }
}

@Test func parkedThemesAreNotOffered() {
    #expect(!Theme.offered.contains(.brushInk))
    #expect(!Theme.offered.contains(.keynoteGlow))
    #expect(Theme.offered == [.hotaru, .cyberpunk, .minimal])
    // A saved Brush & Ink choice still decodes and draws.
    #expect(AppSettings.decoded(from: Data(#"{"theme": "brushInk"}"#.utf8)).theme == .brushInk)
}

@Test func hexColors() {
    #expect(RGBA(hex: 0xFF8000) == RGBA(1, 128.0 / 255, 0))
    #expect(RGBA(hex: 0x000000, alpha: 0.5).alpha == 0.5)
}

// MARK: - Hotaru companion

@Test func hotaruIsTheFirstLaunchTheme() {
    #expect(AppSettings().theme == .hotaru)
    #expect(!AppSettings().greeted)
    // A saved "firefly" from an earlier build falls back to the default.
    #expect(AppSettings.decoded(from: Data(#"{"theme": "firefly"}"#.utf8)).theme == .hotaru)
}

@Test func companionFliesReactsAndSettles() {
    var c = CompanionAnimator()
    #expect(c.pose(at: 0) == .rest)
    #expect(c.pose(at: 0, idle: true) == .doze)
    #expect(c.pose(at: 0, laser: true) == .focus)
    #expect(c.nextChange(after: 0) == nil)

    c.moved(dx: 5, dy: 0, time: 1)
    #expect(c.pose(at: 1) == .flyA)
    c.moved(dx: c.strokeLength, dy: 0, time: 1.05)
    #expect(c.pose(at: 1.05) == .flyB)
    c.moved(dx: -3, dy: 0, time: 1.1)
    #expect(c.facingLeft)
    #expect(c.nextChange(after: 1.1) == 1.1 + c.settleDelay)
    #expect(c.pose(at: 1.1 + c.settleDelay) == .rest)

    c.clicked(.left, time: 2)
    #expect(c.pose(at: 2.1) == .flash)
    #expect(c.nextChange(after: 2.1) == 2 + c.flashDuration)
    #expect(c.pose(at: 2 + c.flashDuration) == .rest)

    c.clicked(.right, time: 3)
    #expect(c.pose(at: 3.5) == .curious)
    #expect(c.nextChange(after: 3.1) == 3 + c.curiousDuration)
}

@Test func greetingWavesThenSettles() {
    var c = CompanionAnimator()
    c.greet(time: 10)
    #expect(c.pose(at: 10.1) == .waveA)
    #expect(c.pose(at: 10.1 + c.waveStroke) == .waveB)
    #expect(abs((c.nextChange(after: 10.1) ?? 0) - (10 + c.waveStroke)) < 1e-9)
    #expect(c.pose(at: 10 + c.waveDuration + 0.01) == .rest)
    #expect(c.nextChange(after: 10 + c.waveDuration + 0.01) == nil)
    // A click during the wave takes over, then the wave resumes.
    c.clicked(.left, time: 11)
    #expect(c.pose(at: 11.1) == .flash)
}

@Test func faceFollowsTheSheet() {
    #expect(CompanionFace.of(.focus).glow == 1)
    #expect(CompanionFace.of(.flash).glow == 1)
    #expect(abs(CompanionFace.of(.doze).glow - 0.15) < 1e-9) // dims, not hidden
    // Blush only for happy and waving.
    let blushing = CompanionPose.allCases.filter { CompanionFace.of($0).blush }
    #expect(Set(blushing) == [.flash, .waveA, .waveB])
    #expect(CompanionFace.of(.waveA).wave > CompanionFace.of(.waveB).wave)
}

// MARK: - Shortcut Subtitles

@Test func subtitlesComeFromTheFrontmostApp() {
    let shiftCmdP = KeyStroke(keyCode: 35, modifiers: [.shift, .command])
    #expect(ShortcutSubtitles.subtitle(for: shiftCmdP, bundleID: "com.microsoft.VSCode") == "Command Palette")
    let ctrlR = KeyStroke(keyCode: 15, modifiers: [.control])
    #expect(ShortcutSubtitles.subtitle(for: ctrlR, bundleID: "com.apple.Terminal") == "Search History")
    #expect(ShortcutSubtitles.subtitle(for: ctrlR, bundleID: "com.googlecode.iterm2") == "Search History")
    // The same keys mean different things per app.
    let cmdD = KeyStroke(keyCode: 2, modifiers: [.command])
    #expect(ShortcutSubtitles.subtitle(for: cmdD, bundleID: "com.apple.finder") == "Duplicate")
    #expect(ShortcutSubtitles.subtitle(for: cmdD, bundleID: "com.google.Chrome") == "Bookmark Page")
    // Universal shortcuts work anywhere; unknown ones stay silent.
    #expect(ShortcutSubtitles.subtitle(for: KeyStroke(keyCode: 8, modifiers: [.command]), bundleID: "com.example.unknown") == "Copy")
    #expect(ShortcutSubtitles.subtitle(for: KeyStroke(keyCode: 3, modifiers: [.control, .option]), bundleID: "com.microsoft.VSCode") == nil)
    #expect(ShortcutSubtitles.subtitle(for: shiftCmdP, bundleID: nil) == nil)
    // Fn added by macOS to F-keys and arrows does not change the label.
    #expect(ShortcutSubtitles.subtitle(for: KeyStroke(keyCode: 111, modifiers: [.function]), bundleID: "com.microsoft.VSCode") == "Go to Definition")
}

@Test func dictionaryKeysUseAppleModifierOrder() {
    let order: [Character] = ["⌃", "⌥", "⇧", "⌘"]
    for (id, app) in ShortcutSubtitles.apps {
        for key in app.bindings.keys {
            let mods = key.prefix { order.contains($0) }
            let ranks = mods.map { order.firstIndex(of: $0)! }
            #expect(ranks == ranks.sorted() && Set(ranks).count == ranks.count, "\(id): \(key)")
            #expect(key.count > mods.count, "\(id): \(key) has no key")
        }
    }
}

@Test func everyPreviewKeyHasASubtitle() {
    for (id, app) in ShortcutSubtitles.apps {
        #expect(!app.sources.isEmpty, "\(id) lists no source")
        #expect(ShortcutSubtitles.previewStrokes(bundleID: id).count == app.sample.count, "\(id): a sample label has no key")
        for stroke in ShortcutSubtitles.previewStrokes(bundleID: id) {
            #expect(ShortcutSubtitles.subtitle(for: stroke, bundleID: id) != nil, "\(id): \(stroke.label)")
        }
    }
    // Apps without a dictionary preview the system-wide keys.
    let other = ShortcutSubtitles.previewStrokes(bundleID: "com.example.unknown")
    #expect(!other.isEmpty && other.allSatisfy { ShortcutSubtitles.subtitle(for: $0, bundleID: "com.example.unknown") != nil })
}

/// Every bundled subtitle has a translation, and every language translates the same UI strings.
@Test func everySubtitleAndUIStringIsTranslated() throws {
    let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources")
    func table(_ lang: String, _ name: String) throws -> [String: String] {
        let url = resources.appendingPathComponent("\(lang).lproj/\(name).strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String], "\(url.path)")
    }
    var names = Set(ShortcutSubtitles.systemWide.values).union(VSCodeKeybindings.knownCommands.values)
    for app in ShortcutSubtitles.apps.values { names.formUnion(app.bindings.values) }
    let ui = try Set(table("ja", "Localizable").keys)
    for lang in ["ja", "ko", "zh-Hans"] {
        let subtitles = try table(lang, "Subtitles")
        for name in names { #expect(subtitles[name] != nil, "\(lang): \(name)") }
        #expect(try Set(table(lang, "Localizable").keys) == ui, "\(lang)")
    }
}

@Test func labelsRoundTripToStrokes() {
    for label in ["⇧⌘P", "⌃`", "⌥F12", "esc", "⇧esc", "⌘↩", "⌃⇧⇥", "⇧⌘␣", "⌥⌘[", "F5"] {
        #expect(ShortcutSubtitles.stroke(forLabel: label)?.label == label)
    }
    #expect(ShortcutSubtitles.stroke(forLabel: "⌘") == nil)
}

@Test func sharedKeymapsUseOneDictionary() {
    let findAction = KeyStroke(keyCode: 0, modifiers: [.shift, .command])
    for id in ["com.jetbrains.intellij", "com.jetbrains.pycharm", "com.jetbrains.WebStorm", "com.google.android.studio"] {
        #expect(ShortcutSubtitles.subtitle(for: findAction, bundleID: id) == "Find Action", "\(id)")
    }
    #expect(ShortcutSubtitles.appName(bundleID: "com.vscodium") == "VS Code")
    // Same keys, different apps.
    #expect(ShortcutSubtitles.subtitle(for: findAction, bundleID: "us.zoom.xos") == "Mute/Unmute Audio")
    #expect(ShortcutSubtitles.subtitle(for: findAction, bundleID: "com.tinyspeck.slackmacgap") == "All Unreads")
}

@Test func feedCarriesSubtitlesWithRepeatCount() {
    var feed = KeycapFeed(mode: .shortcutsOnly)
    let cmdD = KeyStroke(keyCode: 2, modifiers: [.command])
    feed.record(cmdD, time: 0, subtitle: "Add Selection to Next Match")
    feed.record(cmdD, time: 0.3, subtitle: "Add Selection to Next Match")
    feed.record(cmdD, time: 0.6, subtitle: "Add Selection to Next Match")
    #expect(feed.currentSubtitle == "Add Selection to Next Match ×3")
    feed.record(KeyStroke(keyCode: 3, modifiers: [.control, .option]), time: 0.9)
    #expect(feed.currentSubtitle == nil)
}

@Test func stampDropsHoldsAndFades() {
    let t = StampTiming()
    #expect(t.scale(age: 0) == t.startScale)
    #expect(t.scale(age: t.land) == 1)
    #expect(t.alpha(age: -0.1) == 0)
    #expect(t.alpha(age: t.land + t.hold / 2) == 1)
    #expect(t.alpha(age: t.duration) == 0)
    #expect(abs(t.alpha(age: t.land + t.hold + t.fade / 2) - 0.5) < 1e-9)
}

// MARK: - VS Code keybindings import

private let sampleKeybindings = """
// Place your key bindings in this file to override the defaults
[
    { "key": "cmd+p", "command": "workbench.action.files.openRecent" }, // a comment
    /* block
       comment */
    { "key": "cmd+d", "command": "-editor.action.addSelectionToNextFindMatch", "when": "editorFocus" },
    { "key": "cmd+b", "command": "-workbench.action.toggleSidebarVisibility" },
    { "key": "cmd+b", "command": "editor.action.joinLines", },
    { "key": "cmd+j", "command": "workbench.action.terminal.focusNext", "when": "terminalFocus" },
    { "key": "ctrl+alt+t", "command": "workbench.action.terminal.new", "when": "editorTextFocus" },
    { "key": "cmd+k cmd+s", "command": "workbench.action.openGlobalKeybindings" },
    { "key": "hyper+x", "command": "editor.action.commentLine" },
    { "key": "shift+alt+[ArrowDown]", "command": "editor.action.copyLinesDownAction", "args": { "text": "// not a comment" } },
    { "key": "f5", "command": "workbench.action.debug.start" },
]
"""

private func vscode(_ label: String, _ imported: ImportedKeybindings?) -> String? {
    for code in 0..<128 {
        for mods in 0..<16 {
            let s = KeyStroke(keyCode: code, modifiers: KeyModifiers(rawValue: mods))
            if s.label == label { return ShortcutSubtitles.subtitle(for: s, bundleID: "com.microsoft.VSCode", imported: imported) }
        }
    }
    Issue.record("no stroke for \(label)")
    return nil
}

@Test func vscodeKeysParseToKeycapLabels() {
    #expect(VSCodeKeybindings.stroke(for: "cmd+shift+p")?.label == "⇧⌘P")
    #expect(VSCodeKeybindings.stroke(for: "ctrl+`")?.label == "⌃`")
    #expect(VSCodeKeybindings.stroke(for: "alt+f12")?.label == "⌥F12")
    #expect(VSCodeKeybindings.stroke(for: "shift+alt+down")?.label == "⌥⇧↓")
    #expect(VSCodeKeybindings.stroke(for: "cmd+[KeyK]")?.label == "⌘K")
    #expect(VSCodeKeybindings.stroke(for: "cmd+[Digit1]")?.label == "⌘1")
    #expect(VSCodeKeybindings.stroke(for: "cmd+-")?.label == "⌘-")
    #expect(VSCodeKeybindings.stroke(for: "meta+enter")?.label == "⌘↩")
    #expect(VSCodeKeybindings.stroke(for: "escape")?.label == "esc")
    #expect(VSCodeKeybindings.stroke(for: "hyper+x") == nil)
    #expect(VSCodeKeybindings.stroke(for: "cmd+") == nil)
    #expect(VSCodeKeybindings.stroke(for: "cmd+numpad_add") == nil)
}

@Test func vscodeCommandsGetReadableTitles() {
    #expect(VSCodeKeybindings.title(forCommand: "workbench.action.showCommands") == "Command Palette")
    #expect(VSCodeKeybindings.title(forCommand: "editor.action.joinLines") == "Join Lines")
    #expect(VSCodeKeybindings.title(forCommand: "workbench.action.files.openRecent") == "Open Recent")
    #expect(VSCodeKeybindings.title(forCommand: "workbench.action.terminal.kill") == "Terminal Kill")
    #expect(VSCodeKeybindings.title(forCommand: "myExtension.do_thing") == "Do Thing")
}

@Test func jsoncCommentsAndTrailingCommasAreAccepted() throws {
    let (_, summary) = try VSCodeKeybindings.parse(sampleKeybindings)
    #expect(summary.chords == 1)
    #expect(summary.unreadable == 1) // hyper+x
    #expect(throws: VSCodeKeybindings.ImportError.notAnArray) { try VSCodeKeybindings.parse("{ \"key\": \"cmd+p\" }") }
    // "//" inside a string is not a comment.
    #expect(VSCodeKeybindings.stripComments("[\"a // b\"] // c") == "[\"a // b\"] ")
    #expect(VSCodeKeybindings.stripTrailingCommas("[1, 2, ] , {\"a\": \",]\",}") == "[1, 2 ] , {\"a\": \",]\"}")
}

@Test func importedBindingsOverrideVSCodeDefaults() throws {
    let (imported, summary) = try VSCodeKeybindings.parse(sampleKeybindings)
    // Before the import, the bundled defaults.
    #expect(vscode("⌘P", nil) == "Quick Open")
    #expect(vscode("⌘D", nil) == "Add Selection to Next Match")
    // The user's own binding wins.
    #expect(vscode("⌘P", imported) == "Open Recent")
    // A removed default is silent, unless the key is rebound.
    #expect(vscode("⌘D", imported) == nil)
    #expect(vscode("⌘B", imported) == "Join Lines")
    // A key that means one thing in the terminal and another elsewhere stays silent...
    #expect(vscode("⌘J", imported) == nil)
    // ...but a `when` binding on a key nothing else uses is named.
    #expect(vscode("⌃⌥T", imported) == "New Terminal")
    #expect(vscode("⌥⇧↓", imported) == "Copy Line Down")
    #expect(vscode("F5", imported) == "Start Debugging")
    // Untouched defaults and system-wide keys still work.
    #expect(vscode("⇧⌘P", imported) == "Command Palette")
    #expect(vscode("⌘C", imported) == "Copy")
    #expect(summary.imported == 5 && summary.removedDefaults == 1 && summary.contextDependent == 1)
    // Other apps are unaffected.
    let cmdP = KeyStroke(keyCode: 35, modifiers: [.command])
    #expect(ShortcutSubtitles.subtitle(for: cmdP, bundleID: "com.apple.Safari", imported: imported) == nil)
    #expect(ShortcutSubtitles.subtitle(for: cmdP, bundleID: "com.microsoft.VSCodeInsiders", imported: imported) == "Open Recent")
}

@Test func importedBindingsPreviewAndPersist() throws {
    let (imported, _) = try VSCodeKeybindings.parse(sampleKeybindings)
    let preview = ShortcutSubtitles.previewStrokes(bundleID: "com.microsoft.VSCode", imported: imported)
    #expect(preview.prefix(3).map(\.label) == ["⌘P", "⌘B", "⌃⌥T"])
    for stroke in preview.prefix(3) {
        #expect(ShortcutSubtitles.subtitle(for: stroke, bundleID: "com.microsoft.VSCode", imported: imported) != nil)
    }
    var s = AppSettings()
    s.vscodeKeybindings = imported
    #expect(AppSettings.decoded(from: try s.encoded()) == s)
    #expect(AppSettings.decoded(from: try AppSettings().encoded()).vscodeKeybindings == nil)
}

@Test func keycapSizesDefaultAndClamp() {
    #expect(AppSettings().keycapScale == 1 && AppSettings().keycapSubtitleScale == 1)
    let s = AppSettings.decoded(from: Data(#"{"keycapScale": 9, "keycapSubtitleScale": 0.1}"#.utf8))
    #expect(s.keycapScale == AppSettings.keycapScaleRange.upperBound)
    #expect(s.keycapSubtitleScale == AppSettings.keycapScaleRange.lowerBound)
    #expect(AppSettings.decoded(from: try! s.encoded()) == s)
}

@Test func keycapPlacementPresetsRoundTrip() {
    #expect(KeycapPlacement(position: AppSettings().keycapPosition) == .bottom)
    for p in KeycapPlacement.allCases { #expect(KeycapPlacement(position: p.position) == p) }
    #expect(KeycapPlacement.topLeft.position == UnitPoint(x: 0.15, y: 0.88))
    #expect(KeycapPlacement(position: UnitPoint(x: 0.3, y: 0.4)) == nil)
}

// MARK: - Agent announcements

@Test func announcementSanitizesAndLimits() {
    let a = Announcement(keys: "cmd+shift+p", caption: "  run\n\ttests\u{202E}evil\u{0007}  ", source: nil)!
    #expect(a.keys == "⇧⌘P")
    #expect(a.caption == "run testsevil")
    #expect(a.source == "agent")
    let long = Announcement(keys: nil, caption: String(repeating: "x", count: 500), source: String(repeating: "s", count: 50))!
    #expect(long.caption!.count == Announcement.maxCaption && long.caption!.hasSuffix("…"))
    #expect(long.source.count == Announcement.maxSource)
    #expect(Announcement(keys: " \n", caption: "\u{0000}", source: "x") == nil)
    #expect(Announcement(keys: "⌘K", caption: nil)?.keys == "⌘K")
    #expect(Announcement(keys: "ctrl+c", caption: nil)?.keys == "⌃C")
    #expect(Announcement(keys: "a+", caption: nil)?.keys == "a+")
}

@Test func announcementParsesArgumentsURLsAndJSON() throws {
    #expect(try Announcement.parse(arguments: ["show", "⌘K", "--caption", "npm test", "--source", "claude"]).get()
        == Announcement(keys: "⌘K", caption: "npm test", source: "claude"))
    #expect(try Announcement.parse(arguments: ["caption", "Deploying", "now"]).get().caption == "Deploying now")
    #expect(Announcement.parse(arguments: ["show", "--caption"]) == .failure(.missingValue("--caption")))
    #expect(Announcement.parse(arguments: ["show"]) == .failure(.empty))
    #expect(Announcement.parse(arguments: ["rm"]) == .failure(.usage))
    let a = Announcement(url: URL(string: "keyray://show?keys=cmd%2Bk&caption=npm%20test&source=codex")!)
    #expect(a == Announcement(keys: "⌘K", caption: "npm test", source: "codex"))
    #expect(Announcement(url: URL(string: "keyray://caption?text=hi")!)?.caption == "hi")
    #expect(Announcement(url: URL(string: "https://show?keys=x")!) == nil)
    #expect(Announcement(url: a!.url) == a)
    #expect(Announcement(json: a!.json) == a)
    #expect(Announcement(json: #"{"keys":"x\u0007y","source":"‮abc"}"#)?.keys == "xy")
    #expect(Announcement(json: "{" + String(repeating: " ", count: 5000) + "}") == nil)
}

@Test func rateLimiterAllowsBurstThenRefills() {
    var r = RateLimiter(capacity: 3, perSecond: 2)
    #expect((0..<5).map { _ in r.allow(now: 10) } == [true, true, true, false, false])
    #expect(r.allow(now: 10.5) == true)
    #expect(r.allow(now: 10.5) == false)
}

@Test func feedShowsAnnouncementsInAnyModeWithBadge() {
    var feed = KeycapFeed(mode: .off)
    feed.announce(Announcement(keys: "⌘K", caption: "npm test", source: "claude")!, time: 1)
    #expect(feed.entries.map { $0.display(showCount: true) } == ["🤖 claude  ⌘K"])
    #expect(feed.currentSubtitle == "npm test")
    feed.announce(Announcement(keys: nil, caption: "Deploying", source: nil)!, time: 1.1)
    #expect(feed.entries.last?.display(showCount: true) == "🤖 agent")
    #expect(mutate(&feed) { $0.prune(now: 10) } == false)
}

@Test func mcpServerListsAndCallsTools() throws {
    var shown: [Announcement] = []
    let server = MCPServer(version: "9") { shown.append($0) }
    func obj(_ s: String?) throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(s!.utf8)) as! [String: Any] }
    let ini = try obj(server.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#))
    #expect((ini["result"] as! [String: Any])["protocolVersion"] as? String == "2025-03-26")
    #expect(server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    let list = try obj(server.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
    #expect(((list["result"] as! [String: Any])["tools"] as! [[String: Any]]).map { $0["name"] as! String } == ["show_keys", "show_caption"])
    let call = try obj(server.handle(#"{"jsonrpc":"2.0","id":"c","method":"tools/call","params":{"name":"show_keys","arguments":{"keys":"cmd+k","caption":"npm test","source":"claude"}}}"#))
    #expect(call["id"] as? String == "c" && (call["result"] as! [String: Any])["isError"] as? Bool == false)
    #expect(shown == [Announcement(keys: "⌘K", caption: "npm test", source: "claude")!])
    let empty = try obj(server.handle(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"show_caption","arguments":{}}}"#))
    #expect((empty["result"] as! [String: Any])["isError"] as? Bool == true && shown.count == 1)
    #expect((try obj(server.handle("nope"))["error"] as! [String: Any])["code"] as? Int == -32700)
    #expect((try obj(server.handle(#"{"jsonrpc":"2.0","id":5,"method":"x"}"#))["error"] as! [String: Any])["code"] as? Int == -32601)
}

@Test func globalMovesAreOnlyABackupForTheOverlay() {
    var s = PointerSources()
    #expect(s.acceptsGlobalMove(at: 5))
    s.overlayMoved(at: 10)
    #expect(!s.acceptsGlobalMove(at: 10.05))
    #expect(s.acceptsGlobalMove(at: 10.2))
}
