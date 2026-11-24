import AppKit
import KeyrayCore

/// The on-screen keycaps: a row of rounded caps at a user-chosen spot on the display with the cursor.
/// Click-through, except while "Move keycaps" is on, when it can be dragged to a new position.
@MainActor
final class KeycapHUD: NSObject, NSWindowDelegate {
    private let window: NSPanel
    private let stack = NSStackView()
    /// The caps row above, the Shortcut Subtitle below.
    private let column = NSStackView()
    /// The app whose dictionary the preview uses, instead of the frontmost app.
    private var previewApp: String?
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
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 2
        column.addArrangedSubview(stack)
        let container = NSView()
        container.wantsLayer = true
        container.addSubview(column)
        column.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            column.topAnchor.constraint(equalTo: container.topAnchor),
            column.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
        ])
        window.contentView = container
        apply(settings)
    }

    func apply(_ s: AppSettings) {
        let relayout = s.keycapScale != settings.keycapScale || s.keycapSubtitleScale != settings.keycapSubtitleScale
            || s.theme != settings.theme
            || (s.keycapPosition != settings.keycapPosition && !isPositioning) // a drag already moved the window
        settings = s
        let k = s.keycapScale
        stack.spacing = 8 * k
        stack.edgeInsets = NSEdgeInsets(top: 10 * k, left: 12 * k, bottom: 10 * k, right: 12 * k)
        feed.mode = s.keycapMode
        feed.linger = s.keycapLingerSeconds
        feed.hiddenStrokes = s.keycapHideActivationKeys ? AppShortcut.activationStrokes : []
        if s.keycapMode == .off && !isPositioning { clear() } else if relayout { render() }
    }

    func setSuppressed(_ value: Bool) {
        suppressed = value
        if value { window.orderOut(nil) } else { render() }
    }

    func record(_ stroke: KeyStroke, isRepeat: Bool) {
        // Shortcut Subtitles: the name comes from the dictionary of the app the key went to.
        let app = previewApp ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let subtitle = settings.keycapSubtitles ? ShortcutSubtitles.subtitle(for: stroke, bundleID: app, imported: settings.vscodeKeybindings) : nil
        guard !suppressed, feed.record(stroke, time: CACurrentMediaTime(), isRepeat: isRepeat, subtitle: subtitle) else { return }
        render()
        scheduleClear()
    }

    /// An agent's keys or caption (CLI, URL or MCP), shown with a 🤖 badge in any keycap mode.
    func announce(_ a: Announcement) {
        guard !suppressed else { return }
        feed.announce(a, time: CACurrentMediaTime())
        render()
        scheduleClear()
    }

    private func scheduleClear() {
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

    /// Plays a sample through the real feed, subtitles and HUD, so the look, position and
    /// Shortcut Subtitles can be checked without Input Monitoring. `bundleID` picks the app
    /// dictionary (default: the frontmost app). Uses "shortcuts only" when keycaps are off.
    func preview(bundleID: String? = nil) {
        let saved = feed.mode
        if feed.mode == .off { feed.mode = .shortcutsOnly }
        let app = bundleID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        previewApp = app
        var steps: [(Double, KeyStroke)] = []
        var t = 0.0
        for stroke in ShortcutSubtitles.previewStrokes(bundleID: app, imported: settings.vscodeKeybindings) {
            if let last = steps.last?.1, last.matches(stroke) { t += 0.35 } else if !steps.isEmpty { t += 1.1 }
            steps.append((t, stroke))
        }
        steps.append((t + 0.5, AppShortcut.toggleLaser.stroke)) // hidden when "hide activation keys" is on
        for (delay, stroke) in steps {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.record(stroke, isRepeat: false) }
            }
        }
        Timer.scheduledTimer(withTimeInterval: t + 0.6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.feed.mode = saved
                self?.previewApp = nil
            }
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
        let signpost = Log.signposter.beginInterval("Keycaps render")
        defer { Log.signposter.endInterval("Keycaps render", signpost) }
        let texts: [(String, badge: String?)]
        if isPositioning {
            texts = [("Drag to move", nil), ("⌃⌥⌘K", nil)]
        } else {
            texts = feed.entries.map { e in
                guard case .announced(let source) = e.kind else { return (e.display(showCount: settings.keycapShowRepeatCount), nil) }
                return (e.display(showCount: false), "🤖 \(source)")
            }
        }
        for v in stack.arrangedSubviews { v.removeFromSuperview() }
        for v in column.arrangedSubviews where v !== stack { v.removeFromSuperview() }
        guard !texts.isEmpty, !suppressed else {
            window.orderOut(nil)
            return
        }
        for t in texts { stack.addArrangedSubview(cap(t.0, dashed: isPositioning, badge: t.badge)) }
        let agentCaption: Bool
        if case .announced = feed.entries.last?.kind { agentCaption = true } else { agentCaption = false }
        if !isPositioning, settings.keycapSubtitles || agentCaption, let subtitle = feed.currentSubtitle {
            column.addArrangedSubview(subtitleView(subtitle))
        }
        window.setContentSize(column.fittingSize)
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

    /// The Shortcut Subtitle under the caps, in the theme's voice: a lantern-lit caption for Hotaru
    /// (a caption under the keys, not a speech bubble: the character sheet keeps Hotaru wordless),
    /// a terminal comment for Cyberpunk, a plain caption otherwise.
    private func subtitleView(_ text: String) -> NSView {
        let k = settings.keycapSubtitleScale
        let label = NSTextField(labelWithString: text)
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        var leading: CGFloat = 12
        switch settings.theme {
        case .cyberpunk:
            label.stringValue = "// " + text.lowercased()
            label.font = .monospacedSystemFont(ofSize: 18 * k, weight: .medium)
            label.textColor = RGBA(hex: CyberPalette.acid).nsColor
            box.layer?.backgroundColor = RGBA(hex: CyberPalette.night, alpha: 0.9).cg()
            box.layer?.cornerRadius = 3
        case .hotaru:
            label.font = .systemFont(ofSize: 19 * k, weight: .semibold)
            label.textColor = RGBA(hex: HotaruPalette.lanternCore).nsColor
            box.layer?.backgroundColor = RGBA(hex: HotaruPalette.nightInk, alpha: 0.88).cg()
            box.layer?.cornerRadius = 12
            // A small lit lantern dot marks it as Hotaru's caption.
            let dot = CALayer()
            dot.backgroundColor = RGBA(hex: HotaruPalette.lanternCore).cg()
            dot.frame = CGRect(x: 11 * k, y: 11 * k, width: 8 * k, height: 8 * k)
            dot.cornerRadius = 4 * k
            dot.shadowColor = RGBA(hex: HotaruPalette.lanternGlow).cg()
            dot.shadowOpacity = 1
            dot.shadowRadius = 4
            dot.shadowOffset = .zero
            box.layer?.addSublayer(dot)
            leading = 26
        default:
            label.font = .systemFont(ofSize: 18 * k, weight: .medium)
            label.textColor = .white
            box.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.75).cgColor
        }
        box.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: leading * k),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12 * k),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 5 * k),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -5 * k),
        ])
        return box
    }

    /// One cap in the theme's style: dark glass (Minimal), night-ink plaque with a lit lantern dot (Hotaru),
    /// hanji tag with a seal mark (Brush & Ink) or frosted glass (Keynote Glow).
    /// `badge` is the leading part of `text` that marks agent input; it is drawn smaller and dimmer.
    private func cap(_ text: String, dashed: Bool, badge: String? = nil) -> NSView {
        let style = settings.style
        let k = settings.keycapScale
        let label = NSTextField(labelWithString: text)
        label.textColor = style.keycapText.nsColor
        switch settings.theme {
        case .hotaru:
            label.font = .systemFont(ofSize: 30 * k, weight: .bold)
        case .cyberpunk:
            label.font = .monospacedSystemFont(ofSize: 28 * k, weight: .semibold)
        case .brushInk:
            label.font = NSFont(name: "AppleMyungjo", size: 30 * k) ?? .systemFont(ofSize: 30 * k)
        case .minimal, .keynoteGlow:
            label.font = .systemFont(ofSize: 30 * k, weight: .semibold)
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
        box.layer?.cornerRadius = style.keycapCornerRadius * k
        box.layer?.masksToBounds = settings.theme == .keynoteGlow
        box.layer?.borderWidth = dashed ? 2 : 1
        box.layer?.borderColor = dashed ? NSColor(white: 1, alpha: 0.8).cgColor : style.keycapBorder.nsColor.cgColor
        if settings.theme == .cyberpunk {
            // Terminal accents: a magenta prompt mark and faint scanlines.
            let prompt = CALayer()
            prompt.backgroundColor = RGBA(hex: CyberPalette.magenta).cg()
            prompt.frame = CGRect(x: 5 * k, y: 7 * k, width: 3 * k, height: 12 * k)
            box.layer?.addSublayer(prompt)
            let lines = CAReplicatorLayer()
            lines.frame = CGRect(x: 0, y: 0, width: 400 * k, height: 60 * k)
            lines.instanceCount = Int((20 * k).rounded(.up))
            lines.instanceTransform = CATransform3DMakeTranslation(0, 3, 0)
            let line = CALayer()
            line.backgroundColor = RGBA(hex: CyberPalette.cyan, alpha: 0.07).cg()
            line.frame = CGRect(x: 0, y: 0, width: 400 * k, height: 1)
            lines.addSublayer(line)
            box.layer?.addSublayer(lines)
            box.layer?.masksToBounds = true
        }
        if settings.theme == .hotaru {
            let light = CALayer()
            light.backgroundColor = RGBA(hex: HotaruPalette.lanternCore).cg()
            light.frame = CGRect(x: 6 * k, y: 6 * k, width: 6 * k, height: 6 * k)
            light.cornerRadius = 3 * k
            light.shadowColor = RGBA(hex: HotaruPalette.lanternGlow).cg()
            light.shadowOpacity = 1
            light.shadowRadius = 3
            light.shadowOffset = .zero
            box.layer?.addSublayer(light)
        }
        if settings.theme == .brushInk {
            let seal = CALayer()
            seal.backgroundColor = RGBA(hex: 0xB8312F, alpha: 0.9).cg()
            seal.frame = CGRect(x: 4 * k, y: 4 * k, width: 7 * k, height: 7 * k)
            seal.cornerRadius = 1
            box.layer?.addSublayer(seal)
        }
        if let badge, let font = label.font, text.hasPrefix(badge) {
            let s = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: label.textColor ?? .white])
            s.addAttributes([.font: NSFont.systemFont(ofSize: font.pointSize * 0.55, weight: .semibold),
                             .foregroundColor: (label.textColor ?? .white).withAlphaComponent(0.75),
                             .baselineOffset: font.pointSize * 0.12], range: NSRange(location: 0, length: (badge as NSString).length))
            label.attributedStringValue = s
        }
        box.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16 * k),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16 * k),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 8 * k),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8 * k),
        ])
        return box
    }
}
