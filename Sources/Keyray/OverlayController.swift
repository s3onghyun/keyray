import AppKit
import KeyrayCore

/// Draws the cursor ring, click ripples, laser trail and ink on one overlay window per display.
/// Everything is Core Animation layers, so moving the cursor only moves a layer and ripples
/// and fades run in the render server. The laser trail is redrawn once per display frame by a
/// display link, which runs only while the trail is visible.
@MainActor
final class OverlayController {
    private(set) var windows: [OverlayWindow] = []
    private var settings: AppSettings
    private var visible = false

    /// Containers positioned at the cursor; the theme fills them (see `Skin`).
    private let ring = CALayer()
    private let laserDot = CALayer()
    private let laserRibbon = CAShapeLayer()
    /// Hotaru: a container holding the lantern halo behind the drawn character.
    private let companion = CALayer()
    private let companionSprite = CALayer()
    private let halo = Skin.makeLanternHalo()
    private var companionAnim = CompanionAnimator()
    private var companionTimer: Timer?
    private var sources = PointerSources()
    /// The pose and facing on screen, so a move that changes neither touches no layer.
    private var companionShown: (pose: CompanionPose, facingLeft: Bool)?
    private var lastCursor: CGPoint?
    private var trail: LaserTrail
    private var trailWindow: OverlayWindow?
    private lazy var frameClock = FrameClock { [weak self] link in self?.frame(link) }
    private var cursorWindow: OverlayWindow?
    /// The pointer position last drawn, in global coordinates.
    private var lastPointer: NSPoint?

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
            laserRibbon.shadowPath = nil
            if settings.theme == .hotaru, let p = lastCursor {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                placeCompanion(cursor: p)
                CATransaction.commit()
            }
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
            layer.actions = ["position": NSNull(), "path": NSNull(), "shadowPath": NSNull(), "bounds": NSNull(),
                             "contents": NSNull(), "transform": NSNull()]
            layer.opacity = 0
        }
        laserRibbon.opacity = 1
        laserRibbon.zPosition = 1
        laserDot.zPosition = 2
        ring.zPosition = 3
        companion.zPosition = 4
        companion.bounds = CGRect(x: 0, y: 0, width: Skin.companionSize, height: Skin.companionSize)
        companionSprite.frame = companion.bounds
        companionSprite.actions = ["contents": NSNull(), "position": NSNull(), "bounds": NSNull()]
        companion.addSublayer(halo)
        companion.addSublayer(companionSprite)
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
        companionShown = nil
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
        lastPointer = nil
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
            lastPointer = NSEvent.mouseLocation
            moveCursorLayers(to: NSEvent.mouseLocation)
            updateCursorLayers(animated: false)
            scheduleIdleCheck()
        } else {
            for w in windows { w.orderOut(nil) }
            idleTimer?.invalidate()
            idleTimer = nil
            frameClock.stop()
            trail.clear()
            laserRibbon.path = nil
            laserRibbon.shadowPath = nil
            finishStroke()
        }
        Log.overlay.notice("overlays \(show ? "shown" : "hidden", privacy: .public)")
    }

    var isVisible: Bool { visible }

    // MARK: Mouse input

    /// Handles one mouse event from the global monitor (other apps' windows) or the local
    /// monitor (our own overlay while ink mode holds the mouse).
    func handle(_ event: NSEvent, fromGlobalMonitor: Bool = false) {
        guard visible else { return }
        if event.type == .mouseMoved {
            let now = CACurrentMediaTime()
            if fromGlobalMonitor {
                guard sources.acceptsGlobalMove(at: now) else { return }
            } else {
                sources.overlayMoved(at: now)
            }
        }
        let signpost = Log.signposter.beginInterval("Pointer", id: Log.signposter.makeSignpostID(),
                                                    "type=\(event.type.rawValue) age=\((CACurrentMediaTime() - event.timestamp) * 1000, format: .fixed(precision: 2))ms")
        defer {
            Log.signposter.endInterval("Pointer", signpost,
                                       "age=\((CACurrentMediaTime() - event.timestamp) * 1000, format: .fixed(precision: 2))ms")
        }
        // Global-monitor events carry screen coordinates already; reading the event avoids asking
        // the window server for the cursor position on every move.
        let global = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        switch event.type {
        case .mouseMoved:
            // A move over the click-through overlay has no window to convert from; global-monitor
            // moves carry screen coordinates.
            moved(to: event.window == nil && !fromGlobalMonitor ? NSEvent.mouseLocation : global)
        case .rightMouseDragged, .otherMouseDragged:
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
        // The same move can arrive twice (from the global monitor and as an event on the overlay
        // itself); a position already drawn needs no work.
        guard global != lastPointer else { return }
        lastPointer = global
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
            // The trail is redrawn once per display frame, not once per mouse event.
            trail.add(Point(p.x, p.y), time: lastMove)
            startFrameClock()
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
        if settings.theme == .hotaru, let last = lastCursor {
            companionAnim.moved(dx: p.x - last.x, dy: p.y - last.y, time: CACurrentMediaTime())
        }
        lastCursor = p
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.position = p
        laserDot.position = p
        if settings.theme == .hotaru { placeCompanion(cursor: p) }
        CATransaction.commit()
        refreshCompanion()
    }

    /// Hotaru sits beside the pointer with its lantern on the ring's rim (upper right while moving
    /// right, upper left while moving left), so the ring reads as the lantern's light and the body
    /// never covers the click point; with the laser on, the lantern is the laser point itself.
    /// Call inside a transaction with actions disabled.
    private func placeCompanion(cursor p: CGPoint) {
        let left = companionAnim.facingLeft
        var target = p
        if !laserOn {
            let a = Skin.lanternAngle(facingLeft: left), r = settings.ringDiameter / 2
            target = CGPoint(x: p.x + cos(a) * r, y: p.y + sin(a) * r)
        }
        let off = Skin.lanternOffset(facingLeft: left, pose: currentPose)
        companion.position = CGPoint(x: target.x - off.x, y: target.y - off.y)
    }

    private var currentPose = CompanionPose.rest

    /// The lantern's position in the cursor window's coordinates.
    private var lanternPoint: CGPoint {
        let off = Skin.lanternOffset(facingLeft: companionAnim.facingLeft, pose: currentPose)
        return CGPoint(x: companion.position.x + off.x, y: companion.position.y + off.y)
    }

    /// First launch: Hotaru waves hello beside the cursor.
    func greet() {
        guard settings.theme == .hotaru else { return }
        companionAnim.greet(time: CACurrentMediaTime())
        if let p = lastCursor ?? cursorWindow.map({ $0.local(NSEvent.mouseLocation) }) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            placeCompanion(cursor: p)
            CATransaction.commit()
        }
        refreshCompanion()
        updateCursorLayers(animated: true)
    }

    /// The click flash on the lantern: about 120 ms up, 400 ms back (character sheet).
    private func flashLantern() {
        let base = halo.opacity
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 1.7, 1]
        let alpha = CAKeyframeAnimation(keyPath: "opacity")
        alpha.values = [base, 1, base]
        for a in [scale, alpha] {
            a.keyTimes = [0, 0.23, 1]
            a.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        }
        let group = CAAnimationGroup()
        group.animations = [scale, alpha]
        group.duration = 0.52
        halo.add(group, forKey: "flash")
    }

    private func pressed(_ button: MouseButton, at global: NSPoint) {
        buttonsDown.insert(button)
        clickOnlyHideTimer?.invalidate()
        if inkArmed && button == .left {
            autoReleaseTimer?.invalidate()
            beginStroke(at: global)
        } else if settings.ripplesEnabled, let w = window(containing: global) {
            let lantern = settings.theme == .hotaru && w === cursorWindow ? lanternPoint : nil
            Skin.addClickEffect(to: w.root, at: w.local(global), button: button, settings: settings, lantern: lantern)
        }
        if settings.theme == .hotaru && !inkArmed {
            companionAnim.clicked(button, time: CACurrentMediaTime())
            if button == .left { flashLantern() }
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
            clickOnlyHideTimer = Timer.common(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
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
        // Hotaru stays when the ring hides for idle, dozing with its lantern dimmed (not hidden),
        // and while it waves hello.
        let waving = companionAnim.isWaving(at: CACurrentMediaTime())
        let companionShown = visible && settings.theme == .hotaru && settings.ringMode != .off
            && (ringWanted || laserShown || idleHidden || waving)
        fade(companion, to: companionShown ? 1 : 0, animated: animated)
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
        idleTimer = Timer.common(withTimeInterval: max(wait, 0.05), repeats: false) { [weak self] _ in
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
        guard settings.theme == .hotaru else { return }
        let now = CACurrentMediaTime()
        let pose = companionAnim.pose(at: now, laser: laserOn, idle: idleHidden)
        let facingLeft = companionAnim.facingLeft
        if companionShown?.pose != pose || companionShown?.facingLeft != facingLeft {
            companionShown = (pose, facingLeft)
            currentPose = pose
            let l = Skin.lanternInBox(pose)
            halo.position = CGPoint(x: companionAnim.facingLeft ? Skin.companionSize - l.x : l.x, y: l.y)
            halo.opacity = Float(CompanionFace.of(pose).glow)
            if let p = lastCursor { placeCompanion(cursor: p) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            companionSprite.contents = Skin.companionImage(pose, mirrored: companionAnim.facingLeft)
            companionSprite.contentsScale = 2
            CATransaction.commit()
        }
        guard companionTimer == nil, let next = companionAnim.nextChange(after: now) else { return }
        companionTimer = Timer.common(withTimeInterval: max(next - now, 0.02), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.companionTimer = nil
                // Also re-evaluates visibility, e.g. when the hello wave ends.
                self?.updateCursorLayers(animated: true)
            }
        }
    }

    // MARK: Laser trail

    private func startFrameClock() {
        if let view = (trailWindow ?? cursorWindow)?.contentView { frameClock.start(on: view) }
    }

    /// One display frame of the laser: the trail as it should look when the frame reaches the
    /// screen (`targetTimestamp`). The clock stops once the trail has faded.
    private func frame(_ link: CADisplayLink) {
        let signpost = Log.signposter.beginInterval("Laser frame")
        defer { Log.signposter.endInterval("Laser frame", signpost) }
        let now = link.targetTimestamp
        let alive = trail.prune(now: now)
        redrawTrail(now: now)
        if !alive { frameClock.stop() }
    }

    private func redrawTrail(now: Double) {
        let poly = trail.ribbon(now: now)
        guard poly.count > 2 else {
            if laserRibbon.path != nil {
                laserRibbon.path = nil
                laserRibbon.shadowPath = nil
            }
            return
        }
        let path = CGMutablePath()
        path.addLines(between: poly.map { CGPoint(x: $0.x, y: $0.y) })
        path.closeSubpath()
        laserRibbon.path = path
        // The ribbon is one filled shape, so its outline is exactly the glow's shape; with it the
        // render server draws the glow directly instead of an offscreen pass over the layer.
        if laserRibbon.shadowOpacity > 0 { laserRibbon.shadowPath = path }
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
        s.freeze()
        let fade = InkFade(hold: settings.inkHoldSeconds, fade: settings.inkFadeSeconds)
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1
        a.toValue = 0
        a.beginTime = s.layer.convertTime(CACurrentMediaTime(), from: nil) + fade.hold
        a.duration = fade.fade
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        s.layer.add(a, forKey: "fade")
        Timer.common(withTimeInterval: fade.lifetime + 0.05, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                s.layer.removeFromSuperlayer()
                self?.strokes.removeAll { $0 === s }
            }
        }
        if inkArmed && settings.inkInput == .captureWhileDrawing {
            autoReleaseTimer?.invalidate()
            autoReleaseTimer = Timer.common(withTimeInterval: settings.inkAutoReleaseSeconds, repeats: false) { [weak self] _ in
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
        case .cyberpunk: // a thin dark edge keeps neon readable on white slides
            layer.shadowColor = RGBA(hex: CyberPalette.night).cg()
            layer.shadowOpacity = tool == .highlighter ? 0 : 0.85
            layer.shadowRadius = 1.2
            layer.shadowOffset = .zero
        case .hotaru: // a faint lantern glow along the stroke
            layer.shadowColor = RGBA(hex: HotaruPalette.lanternGlow).cg()
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

    /// A finished stroke no longer changes: cache it as a bitmap for its hold and fade, so its glow
    /// is not re-rendered every frame.
    func freeze() {
        guard let path = layer.path else { return }
        let margin = layer.lineWidth + layer.shadowRadius + 4
        let box = path.boundingBoxOfPath.insetBy(dx: -margin, dy: -margin)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Bounds in the same coordinates as the path, centered on the position: nothing moves.
        layer.bounds = box
        layer.position = CGPoint(x: box.midX, y: box.midY)
        layer.shouldRasterize = true
        layer.rasterizationScale = Skin.backingScale
        CATransaction.commit()
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
