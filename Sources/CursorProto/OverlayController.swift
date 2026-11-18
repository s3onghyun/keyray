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

    private let ring = CAShapeLayer()
    private let laserDot = CAShapeLayer()
    private let laserRibbon = CAShapeLayer()
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
        for layer in [ring, laserDot, laserRibbon] {
            layer.actions = ["position": NSNull(), "path": NSNull(), "bounds": NSNull()]
            layer.opacity = 0
        }
        laserRibbon.opacity = 1
        laserRibbon.zPosition = 1
        laserDot.zPosition = 2
        ring.zPosition = 3
        laserDot.shadowRadius = 8
        laserDot.shadowOpacity = 1
        laserDot.shadowOffset = .zero
        apply(settings)
        rebuildWindows()
    }

    // MARK: AppSettings and windows

    func apply(_ s: AppSettings) {
        settings = s
        trail.duration = s.laserTrailSeconds
        trail.maxWidth = s.laserWidth

        let d = s.ringDiameter
        ring.path = CGPath(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d), transform: nil)
        ring.fillColor = s.ringColor.cg(alpha: 0.12)
        ring.strokeColor = s.ringColor.cg()
        ring.lineWidth = s.ringLineWidth

        let dot = max(s.laserWidth * 1.3, 8)
        laserDot.path = CGPath(ellipseIn: CGRect(x: -dot / 2, y: -dot / 2, width: dot, height: dot), transform: nil)
        laserDot.fillColor = s.laserColor.cg()
        laserDot.shadowColor = s.laserColor.cg()
        laserRibbon.fillColor = s.laserColor.cg(alpha: 0.8)

        for border in inkBorders { border.borderColor = s.inkColor.cg(alpha: 0.45) }
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
            border.borderColor = settings.inkColor.cg(alpha: 0.45)
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
            w.root.addSublayer(ring)
            w.root.addSublayer(laserDot)
        }
        let p = w.local(global)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.position = p
        laserDot.position = p
        CATransaction.commit()
    }

    private func pressed(_ button: MouseButton, at global: NSPoint) {
        buttonsDown.insert(button)
        clickOnlyHideTimer?.invalidate()
        if inkArmed && button == .left {
            autoReleaseTimer?.invalidate()
            beginStroke(at: global)
        } else if settings.ripplesEnabled {
            ripple(at: global, button: button)
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
        fade(ring, to: ringWanted ? Float(settings.ringOpacity) : 0, animated: animated)
        fade(laserDot, to: visible && laserOn && !idleHidden ? 1 : 0, animated: animated)
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

    // MARK: Ripples

    private func ripple(at global: NSPoint, button: MouseButton) {
        guard let w = window(containing: global) else { return }
        let timing = RippleTiming(duration: settings.rippleDuration)
        let d = settings.rippleDiameter
        let layer = CAShapeLayer()
        layer.path = CGPath(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d), transform: nil)
        let color = settings.rippleColor(for: button)
        layer.fillColor = color.cg(alpha: 0.18)
        layer.strokeColor = color.cg()
        layer.lineWidth = 3
        layer.position = w.local(global)
        layer.opacity = 0

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = timing.startScale
        scale.toValue = 1
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1) // ease-out cubic
        let alpha = CABasicAnimation(keyPath: "opacity")
        alpha.fromValue = timing.startAlpha
        alpha.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, alpha]
        group.duration = timing.duration

        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        w.root.addSublayer(layer)
        layer.add(group, forKey: "ripple")
        CATransaction.commit()
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
        let s = InkStroke(tool: settings.inkTool, color: settings.inkColor, start: w.local(global))
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

    init(tool: InkTool, color: RGBA, start: CGPoint) {
        self.tool = tool
        points = [start]
        layer.actions = ["path": NSNull()]
        layer.fillColor = nil
        layer.lineCap = .round
        layer.lineJoin = .round
        switch tool {
        case .pen:
            layer.strokeColor = color.cg()
            layer.lineWidth = 4
        case .arrow:
            layer.strokeColor = color.cg()
            layer.lineWidth = 5
        case .highlighter:
            layer.strokeColor = RGBA.highlighterYellow.cg(alpha: 0.4)
            layer.lineWidth = 22
            layer.lineCap = .butt
        }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = tool == .highlighter ? 0 : 0.25
        layer.shadowRadius = 1.5
        layer.shadowOffset = CGSize(width: 0, height: -1)
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

extension RGBA {
    func cg(alpha: Double? = nil) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha ?? self.alpha)
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .white
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}
