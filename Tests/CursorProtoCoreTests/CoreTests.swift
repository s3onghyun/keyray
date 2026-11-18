import Foundation
import Testing
@testable import CursorProtoCore

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
    #expect(AppSettings.decoded(from: Data(#"{"theme": "neon"}"#.utf8)).theme == .minimal)
}

@Test func minimalStyleUsesTheUsersColors() {
    var s = AppSettings()
    s.ringColor = RGBA(0.1, 0.2, 0.3)
    s.rippleRight = RGBA(0.4, 0.5, 0.6)
    #expect(s.style.ring == s.ringColor)
    #expect(s.style.ripple(for: .right) == s.rippleRight)
    s.theme = .firefly
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
    #expect(Theme.offered == [.minimal, .firefly, .cyberpunk])
    // A saved Brush & Ink choice still decodes and draws.
    #expect(AppSettings.decoded(from: Data(#"{"theme": "brushInk"}"#.utf8)).theme == .brushInk)
}

@Test func hexColors() {
    #expect(RGBA(hex: 0xFF8000) == RGBA(1, 128.0 / 255, 0))
    #expect(RGBA(hex: 0x000000, alpha: 0.5).alpha == 0.5)
}

// MARK: - Firefly companion

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
    #expect(!c.facingLeft)
    c.moved(dx: -3, dy: 0, time: 1.1)
    #expect(c.facingLeft)
    #expect(c.nextChange(after: 1.1) == 1.1 + c.settleDelay)
    #expect(c.pose(at: 1.1 + c.settleDelay) == .rest)

    c.clicked(.left, time: 2)
    #expect(c.pose(at: 2.1) == .happy)
    #expect(c.nextChange(after: 2.1) == 2 + c.glowAt)
    #expect(c.pose(at: 2 + c.glowAt + 0.01) == .glow)
    #expect(c.pose(at: 2 + c.reactionDuration) == .rest)
    #expect(c.nextChange(after: 2 + c.reactionDuration) == nil)

    c.clicked(.right, time: 3)
    #expect(c.pose(at: 3.5) == .curious)
    #expect(c.nextChange(after: 3.1) == 3 + c.reactionDuration)
}

@Test func everyPoseHasADistinctFace() {
    let faces = CompanionPose.allCases.map { CompanionFace.of($0) }
    #expect(Set(faces.map { "\($0)" }).count == faces.count)
    #expect(faces.allSatisfy { (0...1).contains($0.glow) })
    // The laser pose keeps the tail at full light; dozing nearly turns it off.
    #expect(CompanionFace.of(.focus).glow == 1)
    #expect(CompanionFace.of(.doze).glow < CompanionFace.of(.rest).glow)
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
