import AppKit
import CursorProtoCore

/// Draws the cursor ring, click ripples, laser trail and ink on one overlay window per display.
/// Everything is Core Animation layers, so moving the cursor only moves a layer and ripples
/// and fades run in the render server; timers run only while something is animating by hand.
@MainActor
final class OverlayController {
    private(set) var windows: [OverlayWindow] = []
    private var settings: AppSettings
    private var visible = false

    /// Containers positioned at the cursor; the theme fills them (see `Skin`).
    private let ring = CALayer()
    private let laserDot = CALayer()
    private let laserRibbon = CAShapeLayer()
    private let companion = CALayer()
    private var companionAnim = CompanionAnimator()
    private var companionTimer: Timer?
    private var companionKey = ""
    private var lastCursor: CGPoint?
    private var trail: LaserTrail
    private var trailWindow: OverlayWindow?
    private var laserTimer: Timer?
    private var cursorWindow: OverlayWindow?

    private var lastMove = CACurrentMediaTime()
    private var idleHidden = false
    private var idleTimer: Timer?
    private var buttonsDown: Set<MouseButton> = []
    private var clickOnlyHideTimer: Timer?

    private var stroke: InkStroke?
    private var strokes: [InkStroke] = []
    private var autoReleaseTimer: Timer?
    private var inkBorders: [CALayer] = []

    /// Laser pointer on: the ring gives way to a glowing dot with a vanishing trail.
    var laserOn = false {
        didSet {
            guard laserOn != oldValue else { return }
            trail.clear()
            laserRibbon.path = nil
            updateCursorLayers(animated: true)
        }
    }

    /// Ink mode: left-drags draw. In capture mode the overlay takes the mouse until disarmed.
    var inkArmed = false {
        didSet {
            guard inkArmed != oldValue else { return }
            autoReleaseTimer?.invalidate()
            if !inkArmed { finishStroke() }
            applyMouseCapture()
        }
    }

    /// Called when capture-mode ink gives the mouse back on its own after the last stroke.
    var onInkAutoRelease: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        trail = LaserTrail(duration: settings.laserTrailSeconds, maxWidth: settings.laserWidth)
        for layer in [ring, laserDot, laserRibbon, companion] {
            layer.actions = ["position": NSNull(), "path": NSNull(), "bounds": NSNull(), "contents": NSNull(), "transform": NSNull()]
            layer.opacity = 0
        }
        laserRibbon.opacity = 1
        laserRibbon.zPosition = 1
        laserDot.zPosition = 2
        ring.zPosition = 3
        companion.zPosition = 4
        companion.bounds = CGRect(x: 0, y: 0, width: Skin.companionSize, height: Skin.companionSize)
        apply(settings)
        rebuildWindows()
    }

    // MARK: AppSettings and windows

    func apply(_ s: AppSettings) {
        settings = s
        trail.duration = s.laserTrailSeconds * s.style.laserTrailScale
        trail.maxWidth = s.laserWidth * (s.theme == .keynoteGlow ? 1.8 : 1)
        Skin.buildRing(into: ring, settings: s)
        Skin.styleLaser(tip: laserDot, ribbon: laserRibbon, settings: s)
        companionKey = ""
        refreshCompanion()

        for border in inkBorders { border.borderColor = s.style.pen.cg(alpha: 0.45) }
        if !s.enabled { setVisible(false) }
        updateCursorLayers(animated: false)
    }

    /// One window per display; rebuilt whenever displays are added, removed or rearranged.
    func rebuildWindows() {
        let wasVisible = visible
        for w in windows { w.orderOut(nil) }
        for s in strokes { s.layer.removeFromSuperlayer() }
        strokes.removeAll()
        stroke = nil
        windows = NSScreen.screens.map(OverlayWindow.init(screen:))
        inkBorders = windows.map { w in
            let border = CALayer()
            border.frame = w.root.bounds
            border.borderWidth = 3
            border.borderColor = settings.style.pen.cg(alpha: 0.45)
            border.isHidden = true
            border.zPosition = 10
            w.root.addSublayer(border)
            return border
        }
        cursorWindow = nil
        trailWindow = nil
        trail.clear()
        Log.overlay.notice("overlay windows: \(self.windows.count) display(s)")
        if wasVisible {
            visible = false
            setVisible(true)
        }
        applyMouseCapture()
    }

    /// Shows or hides every overlay at once (the master switch, and hiding during permission prompts).
    func setVisible(_ show: Bool) {
        guard show != visible else { return }
        visible = show
        if show {
            for w in windows { w.orderFrontRegardless() }
            lastMove = CACurrentMediaTime()
            idleHidden = false
            moveCursorLayers(to: NSEvent.mouseLocation)
            updateCursorLayers(animated: false)
            scheduleIdleCheck()
        } else {
            for w in windows { w.orderOut(nil) }
            idleTimer?.invalidate()
            idleTimer = nil
            laserTimer?.invalidate()
            laserTimer = nil
            trail.clear()
            laserRibbon.path = nil
            finishStroke()
        }
        Log.overlay.notice("overlays \(show ? "shown" : "hidden", privacy: .public)")
    }

    var isVisible: Bool { visible }

    // MARK: Mouse input

    /// Handles one mouse event from the global monitor (other apps' windows) or the local
    /// monitor (our own overlay while ink mode holds the mouse).
    func handle(_ event: NSEvent) {
        guard visible else { return }
        // Global-monitor events carry screen coordinates already; reading the event avoids asking
        // the window server for the cursor position on every move.
        let global = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        switch event.type {
        case .mouseMoved, .rightMouseDragged, .otherMouseDragged:
            moved(to: global)
        case .leftMouseDragged:
            moved(to: global)
            extendStroke(to: global)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            moved(to: global)
            pressed(Self.button(of: event), at: global)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            released(Self.button(of: event))
        default:
            break
        }
    }

    private static func button(of event: NSEvent) -> MouseButton {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: .left
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: .right
        default: .middle
        }
    }

    private func window(containing global: NSPoint) -> OverlayWindow? {
        windows.first { NSMouseInRect(global, $0.frame, false) } ?? windows.first
    }

    private func moved(to global: NSPoint) {
        lastMove = CACurrentMediaTime()
        moveCursorLayers(to: global)
        if idleHidden {
            idleHidden = false
            updateCursorLayers(animated: true)
        }
        scheduleIdleCheck()
        if laserOn, let w = cursorWindow {
            if trailWindow !== w {
                trail.clear()
                trailWindow = w
                w.root.addSublayer(laserRibbon)
            }
            let p = w.local(global)
            // The trail is redrawn once per frame by the laser timer, not once per mouse event.
            trail.add(Point(p.x, p.y), time: lastMove)
            startLaserTimer()
        }
    }

    private func moveCursorLayers(to global: NSPoint) {
        guard let w = window(containing: global) else { return }
        if cursorWindow !== w {
            cursorWindow = w
            lastCursor = nil
            w.root.addSublayer(ring)
            w.root.addSublayer(laserDot)
            w.root.addSublayer(companion)
        }
        let p = w.local(global)
        if settings.theme == .firefly, let last = lastCursor {
            companionAnim.moved(dx: p.x - last.x, dy: p.y - last.y, time: CACurrentMediaTime())
        }
        lastCursor = p
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.position = p
        laserDot.position = p
        if settings.theme == .firefly {
            // Hovers just below and behind the cursor, on the side it came from, facing it.
            let side: CGFloat = companionAnim.facingLeft ? 28 : -28
            companion.position = CGPoint(x: p.x + side, y: p.y - 26)
        }
        CATransaction.commit()
        refreshCompanion()
    }

    private func pressed(_ button: MouseButton, at global: NSPoint) {
        buttonsDown.insert(button)
        clickOnlyHideTimer?.invalidate()
        if inkArmed && button == .left {
            autoReleaseTimer?.invalidate()
            beginStroke(at: global)
        } else if settings.ripplesEnabled, let w = window(containing: global) {
            Skin.addClickEffect(to: w.root, at: w.local(global), button: button, settings: settings)
        }
        if settings.theme == .firefly && !inkArmed {
            companionAnim.clicked(button, time: CACurrentMediaTime())
            refreshCompanion()
        }
        animateRingScale(0.82)
        updateCursorLayers(animated: true)
    }

    private func released(_ button: MouseButton) {
        buttonsDown.remove(button)
        animateRingScale(1)
        if button == .left { finishStroke() }
        if settings.ringMode == .clickOnly && buttonsDown.isEmpty {
            clickOnlyHideTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCursorLayers(animated: true) }
            }
        }
    }

    // MARK: Ring and laser dot

    private var ringWanted: Bool {
        guard visible, !laserOn else { return false }
        switch settings.ringMode {
        case .off: return false
        case .always: return !idleHidden
        case .clickOnly: return !buttonsDown.isEmpty || (clickOnlyHideTimer?.isValid ?? false)
        }
    }

    private func updateCursorLayers(animated: Bool) {
        let laserShown = visible && laserOn && !idleHidden
        fade(ring, to: ringWanted ? Float(settings.ringOpacity) : 0, animated: animated)
        fade(laserDot, to: laserShown ? 1 : 0, animated: animated)
        // The firefly stays, dimmed and dozing, when the ring hides for idle; it leaves with the ring otherwise.
        let companionShown = visible && settings.theme == .firefly && settings.ringMode != .off && (ringWanted || laserShown || idleHidden)
        fade(companion, to: companionShown ? (idleHidden ? 0.6 : 1) : 0, animated: animated)
        refreshCompanion()
    }

    private func fade(_ layer: CALayer, to opacity: Float, animated: Bool) {
        guard layer.opacity != opacity else { return }
        if animated {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = layer.presentation()?.opacity ?? layer.opacity
            a.toValue = opacity
            a.duration = opacity > 0 ? 0.12 : 0.3
            layer.add(a, forKey: "fade")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
    }

    private func animateRingScale(_ scale: CGFloat) {
        let a = CABasicAnimation(keyPath: "transform.scale")
        a.fromValue = ring.presentation()?.value(forKeyPath: "transform.scale") ?? 1
        a.toValue = scale
        a.duration = 0.08
        ring.add(a, forKey: "press")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
    }

    /// One-shot timer for idle auto-hide, re-armed lazily so continuous movement costs no timer churn.
    private func scheduleIdleCheck() {
        guard idleTimer == nil, visible else { return }
        let idle = IdleVisibility(idleSeconds: settings.idleHideSeconds)
        guard let wait = idle.secondsUntilHide(sinceLastMove: CACurrentMediaTime() - lastMove) else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: max(wait, 0.05), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.idleTimer = nil
                let since = CACurrentMediaTime() - self.lastMove
                if since + 0.01 >= self.settings.idleHideSeconds, self.buttonsDown.isEmpty {
                    self.idleHidden = true
                    self.updateCursorLayers(animated: true)
                } else {
                    self.scheduleIdleCheck()
                }
            }
        }
    }

    // MARK: Companion

    /// Shows the companion's current pose; a one-shot timer covers changes with no input
    /// (settling to stand, the salute's sparkle and end), so a still cursor costs nothing.
    private func refreshCompanion() {
        guard settings.theme == .firefly else { return }
        let now = CACurrentMediaTime()
        let pose = companionAnim.pose(at: now, laser: laserOn, idle: idleHidden)
        let key = "\(pose.rawValue)-\(companionAnim.facingLeft)"
        if key != companionKey {
            companionKey = key
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            companion.contents = Skin.companionImage(pose, mirrored: companionAnim.facingLeft)
            companion.contentsScale = 2
            CATransaction.commit()
        }
        guard companionTimer == nil, let next = companionAnim.nextChange(after: now) else { return }
        companionTimer = Timer.scheduledTimer(withTimeInterval: max(next - now, 0.02), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.companionTimer = nil
                self?.refreshCompanion()
            }
        }
    }

    // MARK: Laser trail

    private func redrawTrail() {
        let poly = trail.ribbon(now: CACurrentMediaTime())
        guard poly.count > 2 else {
            laserRibbon.path = nil
            return
        }
        let path = CGMutablePath()
        path.addLines(between: poly.map { CGPoint(x: $0.x, y: $0.y) })
        path.closeSubpath()
        laserRibbon.path = path
    }

    private func startLaserTimer() {
        guard laserTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let alive = self.trail.prune(now: CACurrentMediaTime())
                self.redrawTrail()
                if !alive {
                    self.laserTimer?.invalidate()
                    self.laserTimer = nil
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        laserTimer = t
    }

    // MARK: Ink

    /// Capture mode: the overlay takes mouse events while ink is armed. Otherwise always click-through.
    private func applyMouseCapture() {
        let capture = inkArmed && settings.inkInput == .captureWhileDrawing && visible
        for w in windows { w.ignoresMouseEvents = !capture }
        for b in inkBorders { b.isHidden = !(inkArmed && settings.inkInput == .captureWhileDrawing) }
        Log.overlay.notice("ink armed=\(self.inkArmed) capture=\(capture)")
    }

    private func beginStroke(at global: NSPoint) {
        finishStroke()
        guard let w = window(containing: global) else { return }
        let s = InkStroke(tool: settings.inkTool, style: settings.style, theme: settings.theme, start: w.local(global))
        w.root.addSublayer(s.layer)
        stroke = s
        strokeWindow = w
    }

    private var strokeWindow: OverlayWindow?

    private func extendStroke(to global: NSPoint) {
        guard let s = stroke, let w = strokeWindow else { return }
        s.add(w.local(global))
    }

    private func finishStroke() {
        guard let s = stroke else { return }
        stroke = nil
        strokeWindow = nil
        strokes.append(s)
        let fade = InkFade(hold: settings.inkHoldSeconds, fade: settings.inkFadeSeconds)
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1
        a.toValue = 0
        a.beginTime = s.layer.convertTime(CACurrentMediaTime(), from: nil) + fade.hold
        a.duration = fade.fade
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        s.layer.add(a, forKey: "fade")
        Timer.scheduledTimer(withTimeInterval: fade.lifetime + 0.05, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                s.layer.removeFromSuperlayer()
                self?.strokes.removeAll { $0 === s }
            }
        }
        if inkArmed && settings.inkInput == .captureWhileDrawing {
            autoReleaseTimer?.invalidate()
            autoReleaseTimer = Timer.scheduledTimer(withTimeInterval: settings.inkAutoReleaseSeconds, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.inkArmed, self.stroke == nil else { return }
                    Log.overlay.notice("ink auto-release: overlay is click-through again")
                    self.onInkAutoRelease?()
                }
            }
        }
    }

    func clearInk() {
        stroke?.layer.removeFromSuperlayer()
        stroke = nil
        for s in strokes { s.layer.removeFromSuperlayer() }
        strokes.removeAll()
    }

    var inkStrokeCount: Int { strokes.count + (stroke == nil ? 0 : 1) }
}

/// One ink stroke: pen and highlighter follow the drag with smoothed curves; the arrow runs
/// straight from where the drag started to where the cursor is now.
@MainActor
final class InkStroke {
    let layer = CAShapeLayer()
    let tool: InkTool
    private var points: [CGPoint]

    init(tool: InkTool, style: ThemeStyle, theme: Theme, start: CGPoint) {
        self.tool = tool
        points = [start]
        layer.actions = ["path": NSNull()]
        layer.fillColor = nil
        layer.lineCap = .round
        layer.lineJoin = .round
        switch tool {
        case .pen:
            layer.strokeColor = style.pen.cg()
            layer.lineWidth = theme == .brushInk ? 5 : 4
        case .arrow:
            layer.strokeColor = style.pen.cg()
            layer.lineWidth = 5
        case .highlighter:
            layer.strokeColor = style.highlighter.cg()
            layer.lineWidth = 22
            layer.lineCap = .butt
        }
        switch theme {
        case .brushInk: // ink bleeding into paper
            layer.shadowColor = style.pen.cg()
            layer.shadowOpacity = tool == .highlighter ? 0 : 0.5
            layer.shadowRadius = 2
            layer.shadowOffset = .zero
        case .keynoteGlow:
            layer.shadowColor = style.pen.cg()
            layer.shadowOpacity = tool == .highlighter ? 0 : 0.6
            layer.shadowRadius = 4
            layer.shadowOffset = .zero
        case .firefly: // a faint warm glow along the stroke
            layer.shadowColor = RGBA(hex: FireflyPalette.lightGlow).cg()
            layer.shadowOpacity = tool == .highlighter ? 0 : 0.7
            layer.shadowRadius = 2.5
            layer.shadowOffset = .zero
        case .minimal:
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = tool == .highlighter ? 0 : 0.25
            layer.shadowRadius = 1.5
            layer.shadowOffset = CGSize(width: 0, height: -1)
        }
        redraw()
    }

    func add(_ p: CGPoint) {
        if let last = points.last, hypot(p.x - last.x, p.y - last.y) < 1 { return }
        points.append(p)
        redraw()
    }

    private func redraw() {
        let path = CGMutablePath()
        guard let first = points.first else { return }
        switch tool {
        case .arrow:
            let end = points.last!
            path.move(to: first)
            path.addLine(to: end)
            if let (a, b) = arrowHead(from: Point(first.x, first.y), to: Point(end.x, end.y), length: 22) {
                path.move(to: CGPoint(x: a.x, y: a.y))
                path.addLine(to: end)
                path.addLine(to: CGPoint(x: b.x, y: b.y))
            }
        case .pen, .highlighter:
            path.move(to: first)
            if points.count == 1 {
                path.addLine(to: first) // a dot
            } else {
                for i in 1..<points.count {
                    let a = points[i - 1], b = points[i]
                    path.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
                }
                path.addLine(to: points.last!)
            }
        }
        layer.path = path
    }
}
