import AppKit
import CursorProtoCore

/// The on-screen keycaps: a row of rounded caps at a user-chosen spot on the display with the cursor.
/// Click-through, except while "Move keycaps" is on, when it can be dragged to a new position.
@MainActor
final class KeycapHUD: NSObject, NSWindowDelegate {
    private let window: NSPanel
    private let stack = NSStackView()
    private var feed: KeycapFeed
    private var settings: AppSettings
    private var clearTimer: Timer?
    private(set) var isPositioning = false
    private var suppressed = false
    /// Saves a new position (fraction of the screen's visible frame) after a drag.
    var onMoved: ((UnitPoint) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        feed = KeycapFeed(mode: settings.keycapMode, linger: settings.keycapLingerSeconds)
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 64),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        configureAsOverlay(window)
        window.delegate = self
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        let container = NSView()
        container.wantsLayer = true
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
        apply(settings)
    }

    func apply(_ s: AppSettings) {
        settings = s
        feed.mode = s.keycapMode
        feed.linger = s.keycapLingerSeconds
        feed.hiddenStrokes = s.keycapHideActivationKeys ? AppShortcut.activationStrokes : []
        if s.keycapMode == .off && !isPositioning { clear() }
    }

    func setSuppressed(_ value: Bool) {
        suppressed = value
        if value { window.orderOut(nil) } else { render() }
    }

    func record(_ stroke: KeyStroke, isRepeat: Bool) {
        guard !suppressed, feed.record(stroke, time: CACurrentMediaTime(), isRepeat: isRepeat) else { return }
        render()
        clearTimer?.invalidate()
        clearTimer = Timer.scheduledTimer(withTimeInterval: feed.linger + 0.02, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.feed.prune(now: CACurrentMediaTime())
                self.render()
            }
        }
    }

    func clear() {
        feed.clear()
        render()
    }

    /// Plays a sample sequence through the real feed and HUD, so the look and position can be
    /// checked without Input Monitoring. Uses "shortcuts only" when keycaps are off.
    func preview() {
        let saved = feed.mode
        if feed.mode == .off { feed.mode = .shortcutsOnly }
        let cmd: KeyModifiers = [.command]
        let steps: [(Double, KeyStroke, Bool)] = [
            (0.0, KeyStroke(keyCode: 8, modifiers: cmd), false), // ⌘C
            (0.6, KeyStroke(keyCode: 9, modifiers: cmd), false), // ⌘V
            (1.3, KeyStroke(keyCode: 6, modifiers: cmd), false), // ⌘Z
            (1.6, KeyStroke(keyCode: 6, modifiers: cmd), false),
            (1.9, KeyStroke(keyCode: 6, modifiers: cmd), false),
            (2.3, AppShortcut.toggleLaser.stroke, false), // hidden when "hide activation keys" is on
            (2.7, KeyStroke(keyCode: 40, modifiers: [.shift, .command]), false), // ⇧⌘K
        ]
        for (delay, stroke, isRepeat) in steps {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.record(stroke, isRepeat: isRepeat) }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.feed.mode = saved }
        }
    }

    /// Drag-to-position mode: shows a sample cap that can be dragged; ends with `endPositioning`.
    func beginPositioning() {
        isPositioning = true
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        render()
    }

    func endPositioning() {
        isPositioning = false
        window.ignoresMouseEvents = true
        window.isMovableByWindowBackground = false
        render()
    }

    private func render() {
        let texts: [String]
        if isPositioning {
            texts = ["Drag to move", "⌃⌥⌘K"]
        } else {
            texts = feed.entries.map { $0.display(showCount: settings.keycapShowRepeatCount) }
        }
        for v in stack.arrangedSubviews { v.removeFromSuperview() }
        guard !texts.isEmpty, !suppressed else {
            window.orderOut(nil)
            return
        }
        for t in texts { stack.addArrangedSubview(cap(t, dashed: isPositioning)) }
        window.setContentSize(stack.fittingSize)
        place()
        window.orderFrontRegardless()
    }

    private func place() {
        guard let screen = screenWithMouse else { return }
        let vf = screen.visibleFrame
        let size = window.frame.size
        let p = settings.keycapPosition
        var origin = NSPoint(x: vf.minX + vf.width * p.x - size.width / 2, y: vf.minY + vf.height * p.y - size.height / 2)
        origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
        origin.y = min(max(origin.y, vf.minY), vf.maxY - size.height)
        placing = true
        window.setFrameOrigin(origin)
        placing = false
    }

    private var placing = false

    private var screenWithMouse: NSScreen? {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main
    }

    func windowDidMove(_ notification: Notification) {
        guard isPositioning, !placing, let screen = window.screen else { return }
        let vf = screen.visibleFrame
        let f = window.frame
        onMoved?(UnitPoint(x: (f.midX - vf.minX) / vf.width, y: (f.midY - vf.minY) / vf.height))
    }

    /// One cap in the theme's style: dark glass (Minimal), night-teal plaque with a light (Firefly),
    /// hanji tag with a seal mark (Brush & Ink) or frosted glass (Keynote Glow).
    private func cap(_ text: String, dashed: Bool) -> NSView {
        let style = settings.style
        let label = NSTextField(labelWithString: text)
        label.textColor = style.keycapText.nsColor
        switch settings.theme {
        case .firefly:
            label.font = .systemFont(ofSize: 30, weight: .bold)
        case .cyberpunk:
            label.font = .monospacedSystemFont(ofSize: 28, weight: .semibold)
        case .brushInk:
            label.font = NSFont(name: "AppleMyungjo", size: 30) ?? .systemFont(ofSize: 30)
        case .minimal, .keynoteGlow:
            label.font = .systemFont(ofSize: 30, weight: .semibold)
        }
        let box: NSView
        if settings.theme == .keynoteGlow {
            let glass = NSVisualEffectView()
            glass.material = .hudWindow
            glass.blendingMode = .behindWindow
            glass.state = .active
            box = glass
        } else {
            box = NSView()
        }
        box.wantsLayer = true
        box.layer?.backgroundColor = settings.theme == .keynoteGlow ? nil : style.keycapBackground.nsColor.cgColor
        box.layer?.cornerRadius = style.keycapCornerRadius
        box.layer?.masksToBounds = settings.theme == .keynoteGlow
        box.layer?.borderWidth = dashed ? 2 : 1
        box.layer?.borderColor = dashed ? NSColor(white: 1, alpha: 0.8).cgColor : style.keycapBorder.nsColor.cgColor
        if settings.theme == .cyberpunk {
            // Terminal accents: a magenta prompt mark and faint scanlines.
            let prompt = CALayer()
            prompt.backgroundColor = RGBA(hex: CyberPalette.magenta).cg()
            prompt.frame = CGRect(x: 5, y: 7, width: 3, height: 12)
            box.layer?.addSublayer(prompt)
            let lines = CAReplicatorLayer()
            lines.frame = CGRect(x: 0, y: 0, width: 400, height: 60)
            lines.instanceCount = 20
            lines.instanceTransform = CATransform3DMakeTranslation(0, 3, 0)
            let line = CALayer()
            line.backgroundColor = RGBA(hex: CyberPalette.cyan, alpha: 0.07).cg()
            line.frame = CGRect(x: 0, y: 0, width: 400, height: 1)
            lines.addSublayer(line)
            box.layer?.addSublayer(lines)
            box.layer?.masksToBounds = true
        }
        if settings.theme == .firefly {
            let light = CALayer()
            light.backgroundColor = RGBA(hex: FireflyPalette.light).cg()
            light.frame = CGRect(x: 6, y: 6, width: 6, height: 6)
            light.cornerRadius = 3
            light.shadowColor = RGBA(hex: FireflyPalette.lightGlow).cg()
            light.shadowOpacity = 1
            light.shadowRadius = 3
            light.shadowOffset = .zero
            box.layer?.addSublayer(light)
        }
        if settings.theme == .brushInk {
            let seal = CALayer()
            seal.backgroundColor = RGBA(hex: 0xB8312F, alpha: 0.9).cg()
            seal.frame = CGRect(x: 4, y: 4, width: 7, height: 7)
            seal.cornerRadius = 1
            box.layer?.addSublayer(seal)
        }
        box.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
        ])
        return box
    }
}
