import AppKit
import CursorProtoCore

/// How each theme draws the ring, click effect, laser tip and companion. All of it is built once
/// per settings change; per-move work stays a layer position update.
@MainActor
enum Skin {
    /// Hotaru's drawing box, in points.
    static let companionSize: CGFloat = 48
    /// Hotaru's body axis: the drawing is rotated about this point by `bodyAngle + pitch`.
    static let bodyCenter = CGPoint(x: 23, y: 20)
    static let bodyAngle: CGFloat = 28
    /// The lantern's center along the body axis, relative to `bodyCenter`.
    static let lanternOnAxis: CGFloat = -12

    /// Center of the tail lantern in the box (y up, facing right) for a pose.
    static func lanternInBox(_ pose: CompanionPose = .rest) -> CGPoint {
        let a = (bodyAngle + CGFloat(CompanionFace.of(pose).pitch)) * .pi / 180
        return CGPoint(x: bodyCenter.x + cos(a) * lanternOnAxis, y: bodyCenter.y + sin(a) * lanternOnAxis)
    }

    /// The lantern's offset from the companion layer's center.
    static func lanternOffset(facingLeft: Bool, pose: CompanionPose = .rest) -> CGPoint {
        let l = lanternInBox(pose)
        let x = l.x - companionSize / 2
        return CGPoint(x: facingLeft ? -x : x, y: l.y - companionSize / 2)
    }

    /// Where the lantern touches the ring: upper right while moving right, upper left while
    /// moving left, so the body sits beside the pointer and never over the click point.
    static func lanternAngle(facingLeft: Bool) -> CGFloat { (facingLeft ? 135 : 45) * .pi / 180 }

    // MARK: Ring

    /// Fills `container` (positioned at the cursor) with the theme's ring.
    static func buildRing(into container: CALayer, settings s: AppSettings) {
        container.sublayers?.forEach { $0.removeFromSuperlayer() }
        let style = s.style
        let d = s.ringDiameter
        let circle = CGPath(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d), transform: nil)
        switch s.theme {
        case .minimal:
            let ring = shape(circle)
            ring.fillColor = style.ring.cg(alpha: 0.12)
            ring.strokeColor = style.ring.cg()
            ring.lineWidth = s.ringLineWidth
            container.addSublayer(ring)

        case .hotaru:
            // A pool of lantern light: a soft warm fill that brightens toward the rim, a lantern-rim
            // edge with a glow, and a faint ink line outside it so it holds on light slides.
            let r = d / 2
            let outline = shape(CGPath(ellipseIn: CGRect(x: -r - 2, y: -r - 2, width: d + 4, height: d + 4), transform: nil))
            outline.fillColor = nil
            outline.strokeColor = style.ringOutline?.cg()
            outline.lineWidth = 1
            let pool = CAGradientLayer()
            pool.type = .radial
            pool.colors = [RGBA(hex: HotaruPalette.lanternGlow, alpha: 0.06).cg(), RGBA(hex: HotaruPalette.lanternGlow, alpha: 0.26).cg()]
            pool.locations = [0.2, 1]
            pool.startPoint = CGPoint(x: 0.5, y: 0.5)
            pool.endPoint = CGPoint(x: 1, y: 1)
            pool.frame = CGRect(x: -r, y: -r, width: d, height: d)
            pool.cornerRadius = r
            pool.masksToBounds = true
            let rim = shape(circle)
            rim.fillColor = nil
            rim.strokeColor = style.ring.cg()
            rim.lineWidth = s.ringLineWidth
            glow(rim, RGBA(hex: HotaruPalette.lanternGlow), radius: 4)
            container.addSublayer(outline)
            container.addSublayer(pool)
            container.addSublayer(rim)

        case .cyberpunk:
            // A HUD reticle: four arcs with gaps at the compass points, short ticks in the gaps,
            // each drawn twice (dark underlay for light slides, neon on top).
            let r = d / 2
            let quarter = Double.pi * d / 4, gapLen = quarter * 0.22
            let ticks = CGMutablePath()
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 2
                ticks.move(to: CGPoint(x: cos(a) * (r - 3), y: sin(a) * (r - 3)))
                ticks.addLine(to: CGPoint(x: cos(a) * (r + 5), y: sin(a) * (r + 5)))
            }
            for (color, width, isGlow) in [(style.ringOutline ?? RGBA(0, 0, 0), s.ringLineWidth + 3, false), (style.ring, s.ringLineWidth, true)] {
                let arcs = shape(circle)
                arcs.fillColor = nil
                arcs.strokeColor = color.cg()
                arcs.lineWidth = width
                arcs.lineDashPattern = [NSNumber(value: quarter - gapLen), NSNumber(value: gapLen)]
                arcs.lineDashPhase = -gapLen / 2
                let tick = shape(ticks)
                tick.strokeColor = color.cg()
                tick.lineWidth = isGlow ? 1.5 : 3.5
                if isGlow {
                    glow(arcs, color, radius: 3)
                    glow(tick, color, radius: 2)
                }
                container.addSublayer(arcs)
                container.addSublayer(tick)
            }

        case .brushInk:
            // An ensō: one brush turn that thickens, then thins out before closing.
            let halo = shape(ensoPath(radius: d / 2, maxWidth: s.ringLineWidth + 3.5))
            halo.fillColor = nil
            halo.strokeColor = style.ringOutline?.cg()
            halo.lineWidth = 2.5
            halo.lineJoin = .round
            let ink = shape(ensoPath(radius: d / 2, maxWidth: s.ringLineWidth + 3.5))
            ink.fillColor = style.ring.cg()
            ink.shadowColor = style.ring.cg()
            ink.shadowOpacity = 0.35
            ink.shadowRadius = 1.2
            ink.shadowOffset = .zero
            container.addSublayer(halo)
            container.addSublayer(ink)

        case .keynoteGlow:
            // Simulated frosted glass: a soft white body, a bright rim with glow, a faint dark edge.
            let edge = shape(circle)
            edge.fillColor = nil
            edge.strokeColor = style.ringOutline?.cg()
            edge.lineWidth = s.ringLineWidth + 4
            let body = shape(circle)
            body.fillColor = RGBA(1, 1, 1, 0.16).cg()
            body.strokeColor = style.ring.cg()
            body.lineWidth = s.ringLineWidth + 1
            body.shadowColor = RGBA(1, 1, 1).cg()
            body.shadowOpacity = 0.9
            body.shadowRadius = 6
            body.shadowOffset = .zero
            container.addSublayer(edge)
            container.addSublayer(body)
        }
    }

    /// Closed outline of a tapered brush circle (about 330°), as a fillable path.
    static func ensoPath(radius: CGFloat, maxWidth: CGFloat) -> CGPath {
        let start = 1.75 * CGFloat.pi, sweep = 1.83 * CGFloat.pi
        let steps = 72
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let a = start - sweep * t // clockwise, like a brush pulled from the top right
            // Heavy at the start, thin tail.
            let w = maxWidth * (0.35 + 0.65 * sin(.pi * min(t * 1.6, 1)) * (1 - t * 0.55))
            let r = radius + sin(t * 9) * 0.6 // a little hand wobble
            outer.append(CGPoint(x: cos(a) * (r + w / 2), y: sin(a) * (r + w / 2)))
            inner.append(CGPoint(x: cos(a) * (r - w / 2), y: sin(a) * (r - w / 2)))
        }
        let path = CGMutablePath()
        path.addLines(between: outer + inner.reversed())
        path.closeSubpath()
        return path
    }

    // MARK: Click effects

    /// A one-shot click effect at `point`, already animating; it removes itself when done.
    /// `lantern` is where Hotaru's tail lantern is, for the Hotaru theme.
    static func addClickEffect(to root: CALayer, at point: CGPoint, button: MouseButton, settings s: AppSettings,
                               lantern: CGPoint? = nil) {
        let color = s.style.ripple(for: button)
        switch s.theme {
        case .minimal:
            ripple(root: root, at: point, color: color, diameter: s.rippleDiameter, duration: s.rippleDuration, width: 3, glow: false, delay: 0)
        case .keynoteGlow:
            // A droplet: three rings, each a beat behind the last.
            for (i, scale) in [1.0, 0.8, 0.6].enumerated() {
                ripple(root: root, at: point, color: color, diameter: s.rippleDiameter * scale,
                       duration: s.rippleDuration * 1.3, width: 2.5 - Double(i) * 0.5, glow: true, delay: Double(i) * 0.09)
            }
        case .hotaru:
            // From the character sheet: the lantern flashes (the overlay animates Hotaru's halo),
            // short rays leave it, a beam reaches the click, and a small ring marks the click in
            // the button's color.
            if let lantern {
                if button == .left { rays(root: root, around: lantern) } // the flash is a left-click reaction
                beam(root: root, from: lantern, to: point, color: RGBA(hex: HotaruPalette.lanternGlow))
            }
            ripple(root: root, at: point, color: color, diameter: s.rippleDiameter * 0.55, duration: s.rippleDuration,
                   width: 2, glow: true, delay: lantern == nil ? 0 : 0.06)
        case .cyberpunk:
            targetLock(root: root, at: point, color: color, outline: s.style.ringOutline ?? RGBA(0, 0, 0), button: button)
        case .brushInk:
            sealStamp(root: root, at: point, color: color, button: button)
        }
    }

    private static func ripple(root: CALayer, at point: CGPoint, color: RGBA, diameter d: Double, duration: Double,
                               width: Double, glow: Bool, delay: Double) {
        let timing = RippleTiming(duration: duration)
        let layer = shape(CGPath(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d), transform: nil))
        layer.fillColor = color.cg(alpha: glow ? 0.08 : 0.18)
        layer.strokeColor = color.cg()
        layer.lineWidth = width
        if glow {
            layer.shadowColor = color.cg()
            layer.shadowOpacity = 1
            layer.shadowRadius = 5
            layer.shadowOffset = .zero
        }
        layer.position = point
        layer.opacity = 0

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = timing.startScale
        scale.toValue = 1
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1) // ease-out cubic
        let alpha = CABasicAnimation(keyPath: "opacity")
        alpha.fromValue = timing.startAlpha
        alpha.toValue = 0
        run(layer, in: root, animations: [scale, alpha], duration: timing.duration, delay: delay)
    }

    /// Short rays thrown off the lantern for one flash: out in about 120 ms, gone by 520 ms.
    private static func rays(root: CALayer, around point: CGPoint) {
        let path = CGMutablePath()
        for i in 0..<7 {
            let a = CGFloat(i) * 2 * .pi / 7 + 0.3
            path.move(to: CGPoint(x: cos(a) * 11, y: sin(a) * 11))
            path.addLine(to: CGPoint(x: cos(a) * 16, y: sin(a) * 16))
        }
        let layer = shape(path)
        layer.strokeColor = RGBA(hex: HotaruPalette.lanternGlow).cg()
        layer.lineWidth = 2
        layer.lineCap = .round
        layer.position = point
        layer.opacity = 0
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.6, 1.15, 1.3]
        scale.keyTimes = [0, 0.23, 1]
        let alpha = CAKeyframeAnimation(keyPath: "opacity")
        alpha.values = [0, 1, 0]
        alpha.keyTimes = [0, 0.23, 1]
        run(layer, in: root, animations: [scale, alpha], duration: 0.52, delay: 0)
    }

    /// A short-lived line of light from the lantern to the click.
    private static func beam(root: CALayer, from a: CGPoint, to b: CGPoint, color: RGBA) {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        let line = shape(path)
        line.strokeColor = color.cg(alpha: 0.9)
        line.lineWidth = 2
        line.lineCap = .round
        glow(line, color, radius: 4)
        line.opacity = 0
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.08
        let alpha = CAKeyframeAnimation(keyPath: "opacity")
        alpha.values = [1, 1, 0]
        alpha.keyTimes = [0, 0.4, 1]
        run(line, in: root, animations: [draw, alpha], duration: 0.3, delay: 0)
    }

    /// Target-lock: four corner brackets snap onto the click, hold, then flicker out.
    /// A small label names the button (LMB, RMB, MMB).
    private static func targetLock(root: CALayer, at point: CGPoint, color: RGBA, outline: RGBA, button: MouseButton) {
        let h: CGFloat = 17, arm: CGFloat = 7
        let path = CGMutablePath()
        for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] as [(CGFloat, CGFloat)] {
            path.move(to: CGPoint(x: sx * h, y: sy * (h - arm)))
            path.addLine(to: CGPoint(x: sx * h, y: sy * h))
            path.addLine(to: CGPoint(x: sx * (h - arm), y: sy * h))
        }
        let group = CALayer()
        group.position = point
        group.opacity = 0
        let under = shape(path)
        under.fillColor = nil
        under.strokeColor = outline.cg()
        under.lineWidth = 4.5
        under.lineCap = .square
        let neon = shape(path)
        neon.fillColor = nil
        neon.strokeColor = color.cg()
        neon.lineWidth = 2
        neon.lineCap = .square
        glow(neon, color, radius: 3)
        let label = CATextLayer()
        label.string = button == .left ? "LMB" : button == .right ? "RMB" : "MMB"
        label.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        label.fontSize = 9
        label.foregroundColor = color.cg()
        label.backgroundColor = outline.cg()
        label.alignmentMode = .center
        label.contentsScale = 2
        label.frame = CGRect(x: h + 3, y: h - 6, width: 24, height: 12)
        group.addSublayer(under)
        group.addSublayer(neon)
        group.addSublayer(label)

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.9, 1, 1]
        scale.keyTimes = [0, 0.18, 1]
        scale.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .linear)]
        // A hard flicker on the way out, like a HUD dropping the lock.
        let alpha = CAKeyframeAnimation(keyPath: "opacity")
        alpha.values = [0.4, 1, 1, 0, 1, 0.3, 0]
        alpha.keyTimes = [0, 0.18, 0.62, 0.7, 0.78, 0.9, 1]
        alpha.calculationMode = .discrete
        let jitter = CAKeyframeAnimation(keyPath: "position.x")
        jitter.values = [point.x, point.x, point.x + 2, point.x - 1, point.x]
        jitter.keyTimes = [0, 0.62, 0.7, 0.78, 1]
        jitter.calculationMode = .discrete
        run(group, in: root, animations: [scale, alpha, jitter], duration: 0.65, delay: 0)
    }

    /// A seal (낙관) pressed where you click: square for left, round for right, oval for middle.
    /// The glyph is a placeholder until a real seal is designed.
    private static func sealStamp(root: CALayer, at point: CGPoint, color: RGBA, button: MouseButton) {
        let t = StampTiming()
        let size: CGSize = button == .middle ? CGSize(width: 24, height: 34) : CGSize(width: 30, height: 30)
        let seal = CALayer()
        seal.bounds = CGRect(origin: .zero, size: size)
        seal.position = point
        seal.backgroundColor = color.cg(alpha: 0.92)
        seal.cornerRadius = button == .left ? 3 : min(size.width, size.height) / 2
        seal.opacity = 0
        seal.transform = CATransform3DMakeRotation(CGFloat.random(in: -0.12...0.12), 0, 0, 1)

        let inset = CALayer()
        inset.frame = seal.bounds.insetBy(dx: 3, dy: 3)
        inset.borderColor = RGBA(1, 0.97, 0.93, 0.9).cg()
        inset.borderWidth = 1.2
        inset.cornerRadius = max(seal.cornerRadius - 3, 1)
        seal.addSublayer(inset)

        let glyph = CATextLayer()
        glyph.string = "印"
        glyph.font = NSFont(name: "AppleMyungjo", size: 16) ?? NSFont.systemFont(ofSize: 16)
        glyph.fontSize = 16
        glyph.foregroundColor = RGBA(1, 0.97, 0.93).cg()
        glyph.alignmentMode = .center
        glyph.contentsScale = 2
        glyph.frame = CGRect(x: 0, y: (size.height - 20) / 2, width: size.width, height: 20)
        seal.addSublayer(glyph)

        let n = 12
        let times = (0...n).map { Double($0) / Double(n) * t.duration }
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = times.map { t.scale(age: $0) }
        let alpha = CAKeyframeAnimation(keyPath: "opacity")
        alpha.values = times.map { t.alpha(age: $0) }
        for a in [scale, alpha] { a.keyTimes = times.map { NSNumber(value: $0 / t.duration) } }
        run(seal, in: root, animations: [scale, alpha], duration: t.duration, delay: 0)
    }

    private static func run(_ layer: CALayer, in root: CALayer, animations: [CAAnimation], duration: Double, delay: Double) {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.beginTime = delay > 0 ? root.convertTime(CACurrentMediaTime(), from: nil) + delay : 0
        group.fillMode = .backwards
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        root.addSublayer(layer)
        layer.add(group, forKey: "effect")
        CATransaction.commit()
    }

    // MARK: Laser

    /// The laser tip (`container` is positioned at the cursor) and the trail's fill.
    static func styleLaser(tip container: CALayer, ribbon: CAShapeLayer, settings s: AppSettings) {
        container.sublayers?.forEach { $0.removeFromSuperlayer() }
        let style = s.style
        let dot = max(s.laserWidth * 1.3, 8)
        let circle = CGPath(ellipseIn: CGRect(x: -dot / 2, y: -dot / 2, width: dot, height: dot), transform: nil)
        ribbon.shadowOpacity = 0
        switch s.theme {
        case .minimal:
            let tip = shape(circle)
            tip.fillColor = style.laser.cg()
            glow(tip, style.laser, radius: 8)
            container.addSublayer(tip)
            ribbon.fillColor = style.laser.cg(alpha: 0.8)

        case .hotaru:
            // "Holding the light": the lantern itself is the pointer dot (the overlay puts Hotaru's
            // lantern on the point), with a white-hot center; the trail is amber lantern light.
            let core = shape(CGPath(ellipseIn: CGRect(x: -dot / 3, y: -dot / 3, width: dot / 1.5, height: dot / 1.5), transform: nil))
            core.fillColor = RGBA(hex: HotaruPalette.lanternCore).cg()
            glow(core, RGBA(hex: HotaruPalette.lanternGlow), radius: 8)
            container.addSublayer(core)
            ribbon.fillColor = style.laser.cg(alpha: 0.6)
            ribbon.shadowColor = RGBA(hex: HotaruPalette.lanternGlow).cg()
            ribbon.shadowOpacity = 0.8
            ribbon.shadowRadius = 4
            ribbon.shadowOffset = .zero

        case .cyberpunk:
            // A neon beam: white-hot core, magenta glow.
            let halo = shape(CGPath(ellipseIn: CGRect(x: -dot * 0.8, y: -dot * 0.8, width: dot * 1.6, height: dot * 1.6), transform: nil))
            halo.fillColor = nil
            halo.strokeColor = style.laser.cg()
            halo.lineWidth = 2
            glow(halo, style.laser, radius: 6)
            let core = shape(CGPath(ellipseIn: CGRect(x: -dot / 3, y: -dot / 3, width: dot / 1.5, height: dot / 1.5), transform: nil))
            core.fillColor = RGBA(1, 1, 1).cg()
            glow(core, style.laser, radius: 4)
            container.addSublayer(halo)
            container.addSublayer(core)
            ribbon.fillColor = style.laser.cg(alpha: 0.9)
            ribbon.shadowColor = style.laser.cg()
            ribbon.shadowOpacity = 1
            ribbon.shadowRadius = 5
            ribbon.shadowOffset = .zero

        case .brushInk:
            let tip = shape(circle)
            tip.fillColor = style.laser.cg(alpha: 0.95)
            container.addSublayer(tip)
            // The bleed: ink spreading into paper.
            ribbon.fillColor = style.laser.cg(alpha: 0.82)
            ribbon.shadowColor = style.laser.cg()
            ribbon.shadowOpacity = 0.55
            ribbon.shadowRadius = 2.5
            ribbon.shadowOffset = .zero

        case .keynoteGlow:
            let size = dot * 3.2
            let light = CAGradientLayer()
            light.type = .radial
            light.colors = [RGBA(1, 1, 1).cg(), style.laser.cg(alpha: 0.85), style.laser.cg(alpha: 0)]
            light.locations = [0, 0.28, 1]
            light.startPoint = CGPoint(x: 0.5, y: 0.5)
            light.endPoint = CGPoint(x: 1, y: 1)
            light.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            light.position = .zero
            container.addSublayer(light)
            ribbon.fillColor = style.laser.cg(alpha: 0.32)
        }
    }

    // MARK: Companion

    private static var companionCache: [String: CGImage] = [:]

    /// Hotaru in a pose, drawn with Core Graphics at 2× and cached. Facing right by default.
    static func companionImage(_ pose: CompanionPose, mirrored: Bool) -> CGImage? {
        let key = "\(pose.rawValue)-\(mirrored)"
        if let cached = companionCache[key] { return cached }
        let scale: CGFloat = 2
        let px = Int(companionSize * scale)
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        if mirrored {
            ctx.translateBy(x: companionSize, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        drawHotaru(in: ctx, face: CompanionFace.of(pose))
        let image = ctx.makeImage()
        companionCache[key] = image
        return image
    }

    /// The lantern's halo, a separate layer so the click flash and dozing can animate it.
    static func makeLanternHalo() -> CAGradientLayer {
        let halo = CAGradientLayer()
        halo.type = .radial
        halo.colors = [RGBA(hex: HotaruPalette.lanternCore, alpha: 0.9).cg(), RGBA(hex: HotaruPalette.lanternGlow, alpha: 0.55).cg(),
                       RGBA(hex: HotaruPalette.lanternGlow, alpha: 0).cg()]
        halo.locations = [0, 0.3, 1]
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        halo.bounds = CGRect(x: 0, y: 0, width: 34, height: 34)
        halo.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "transform": NSNull()]
        return halo
    }

    /// An ellipse outline with a slight hand-drawn wobble. The wobble is seeded, so a pose
    /// always draws the same way and the outline never shimmers between frames.
    static func wobblyEllipse(center c: CGPoint, rx: CGFloat, ry: CGFloat, seed: Double, amount: CGFloat = 0.06) -> CGPath {
        let path = CGMutablePath()
        let steps = 48
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let k = 1 + amount * (0.55 * sin(3 * t + seed) + 0.3 * sin(5 * t + seed * 1.7) + 0.15 * sin(11 * t + seed * 2.3))
            let p = CGPoint(x: c.x + cos(t) * rx * k, y: c.y + sin(t) * ry * k)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// Hotaru in a 48×48 pt box (y up), facing right: a dark umber abdomen ending in the lantern
    /// (the only light), the ember collar, an olive head with two big eyes, misty wings over the
    /// back, thin antennae and short legs. Ink outlines keep it readable on light slides, the
    /// lantern and collar on dark ones. Direction art from Claude Design, implemented in code.
    static func drawHotaru(in ctx: CGContext, face: CompanionFace) {
        func color(_ hex: UInt32, _ a: Double = 1) -> CGColor { RGBA(hex: hex, alpha: a).cg() }
        let ink = color(HotaruPalette.nightInk)
        /// Fill, then a fuzzy two-pass ink outline.
        func blob(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ fill: CGColor, seed: Double, line: CGFloat = 1.2) {
            ctx.addPath(wobblyEllipse(center: c, rx: rx, ry: ry, seed: seed))
            ctx.setFillColor(fill)
            ctx.fillPath()
            ctx.addPath(wobblyEllipse(center: c, rx: rx, ry: ry, seed: seed))
            ctx.setStrokeColor(ink)
            ctx.setLineWidth(line)
            ctx.strokePath()
            ctx.addPath(wobblyEllipse(center: c, rx: rx + 0.35, ry: ry + 0.35, seed: seed + 4, amount: 0.09))
            ctx.setStrokeColor(color(HotaruPalette.nightInk, 0.4))
            ctx.setLineWidth(0.6)
            ctx.strokePath()
        }
        func stroke(_ points: [CGPoint], width: CGFloat = 1.1, curve: Bool = true, color strokeColor: CGColor? = nil) {
            guard let first = points.first else { return }
            ctx.move(to: first)
            if curve, points.count == 3 {
                ctx.addQuadCurve(to: points[2], control: points[1])
            } else {
                for p in points.dropFirst() { ctx.addLine(to: p) }
            }
            ctx.setStrokeColor(strokeColor ?? ink)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.strokePath()
        }
        func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> CGColor {
            let ca = RGBA(hex: a), cb = RGBA(hex: b)
            return RGBA(ca.red + (cb.red - ca.red) * t, ca.green + (cb.green - ca.green) * t, ca.blue + (cb.blue - ca.blue) * t).cg()
        }

        ctx.saveGState()
        defer { ctx.restoreGState() }
        // Work along the body axis: x runs from the lantern (negative) to the head (positive).
        ctx.translateBy(x: bodyCenter.x, y: bodyCenter.y)
        ctx.rotate(by: (bodyAngle + CGFloat(face.pitch)) * .pi / 180)

        // Legs under the abdomen.
        for x in [-4.0, -0.5, 3.0] as [CGFloat] {
            stroke([CGPoint(x: x, y: -3.6), CGPoint(x: x - 1.2, y: -6.2), CGPoint(x: x - 2.4, y: -7.4)], width: 1)
        }
        // Abdomen.
        blob(CGPoint(x: -3, y: 0), 9.5, 4.6, color(HotaruPalette.body), seed: 1.1)

        // The lantern: lit from inside, a rim stripe, dimmed to the "lantern dim" color when dozing.
        let lantern = CGPoint(x: lanternOnAxis, y: 0)
        let lit = face.glow
        let coreColor = mix(HotaruPalette.lanternDim, HotaruPalette.lanternCore, min(1, lit / 0.6))
        blob(lantern, 5.6, 5.2, coreColor, seed: 2.7, line: 1.3)
        ctx.saveGState()
        ctx.addPath(wobblyEllipse(center: lantern, rx: 5.6, ry: 5.2, seed: 2.7))
        ctx.clip()
        ctx.move(to: CGPoint(x: lantern.x + 2.2, y: lantern.y + 5.4))
        ctx.addQuadCurve(to: CGPoint(x: lantern.x + 2.2, y: lantern.y - 5.4), control: CGPoint(x: lantern.x + 0.4, y: lantern.y))
        ctx.setStrokeColor(mix(HotaruPalette.lanternDim, HotaruPalette.lanternRim, min(1, lit / 0.6)))
        ctx.setLineWidth(1.4)
        ctx.strokePath()
        ctx.restoreGState()

        // Ember collar: the identity mark.
        blob(CGPoint(x: 6.6, y: 0.6), 2.6, 4.2, color(HotaruPalette.collar), seed: 3.9, line: 1.1)

        // Wings over the back, rear then front, angled back toward the lantern.
        func wing(_ base: CGPoint, _ angle: CGFloat, _ fill: UInt32, _ alpha: Double, seed: Double) {
            ctx.saveGState()
            ctx.translateBy(x: base.x, y: base.y)
            ctx.rotate(by: angle * .pi / 180)
            ctx.addPath(wobblyEllipse(center: CGPoint(x: 0, y: 6), rx: 3.4, ry: 6.6, seed: seed, amount: 0.05))
            ctx.setFillColor(color(fill, alpha))
            ctx.fillPath()
            ctx.addPath(wobblyEllipse(center: CGPoint(x: 0, y: 6), rx: 3.4, ry: 6.6, seed: seed, amount: 0.05))
            ctx.setStrokeColor(color(HotaruPalette.nightInk, 0.75))
            ctx.setLineWidth(0.9)
            ctx.strokePath()
            ctx.restoreGState()
        }
        let w = CGFloat(face.wing)
        wing(CGPoint(x: 2.5, y: 3), 32 - w, HotaruPalette.wingRear, 0.9, seed: 5.2)
        wing(CGPoint(x: 4, y: 3.2), 16 - w * 0.8, HotaruPalette.wingFront, 0.85, seed: 6.1)

        // Head, tilted about the neck.
        ctx.saveGState()
        let neck = CGPoint(x: 9, y: 1)
        ctx.translateBy(x: neck.x, y: neck.y)
        ctx.rotate(by: CGFloat(face.tilt) * .pi / 180)
        ctx.translateBy(x: -neck.x, y: -neck.y)
        let head = CGPoint(x: 13.2, y: 1.6)
        // Antennae: thin curves up and forward.
        stroke([CGPoint(x: 11.5, y: 6.6), CGPoint(x: 10.5, y: 11), CGPoint(x: 8.2, y: 14.5)], width: 1)
        stroke([CGPoint(x: 14, y: 7.2), CGPoint(x: 15.8, y: 11.4), CGPoint(x: 15.2, y: 15.6)], width: 1)
        blob(head, 5.6, 5.6, color(HotaruPalette.head), seed: 7.3)

        // Eyes: two big cream eyes looking forward; the face stays simple.
        let eyes = [CGPoint(x: 13.6, y: 2.6), CGPoint(x: 17.0, y: 1.4)]
        for (i, e) in eyes.enumerated() {
            switch face.eyes {
            case .open, .wide:
                let r: CGFloat = face.eyes == .wide ? 2.1 : 1.8
                blob(e, r, r * 1.05, color(HotaruPalette.eye), seed: 8.1 + Double(i), line: 0.7)
                let pupil = CGPoint(x: e.x + 0.5, y: e.y + (face.eyes == .wide ? 0.5 : 0.1))
                ctx.setFillColor(ink)
                ctx.fillEllipse(in: CGRect(x: pupil.x - 0.9, y: pupil.y - 0.9, width: 1.8, height: 1.8))
                ctx.setFillColor(color(0xFFFFFF))
                ctx.fillEllipse(in: CGRect(x: pupil.x - 0.1, y: pupil.y + 0.2, width: 0.6, height: 0.6))
            case .half:
                blob(e, 1.8, 1.2, color(HotaruPalette.eye), seed: 8.1 + Double(i), line: 0.7)
                ctx.setFillColor(ink)
                ctx.fillEllipse(in: CGRect(x: e.x - 0.4, y: e.y - 0.8, width: 1.6, height: 1.3))
                stroke([CGPoint(x: e.x - 1.9, y: e.y + 0.6), CGPoint(x: e.x + 1.9, y: e.y + 0.4)], width: 0.9, curve: false)
            // Closed eyes are light strokes so they read on the dark head.
            case .happy:
                stroke([CGPoint(x: e.x - 1.5, y: e.y - 0.5), CGPoint(x: e.x, y: e.y + 1.5), CGPoint(x: e.x + 1.5, y: e.y - 0.5)],
                       width: 1.1, color: color(HotaruPalette.eye))
            case .closed:
                stroke([CGPoint(x: e.x - 1.5, y: e.y + 0.3), CGPoint(x: e.x, y: e.y - 1.1), CGPoint(x: e.x + 1.5, y: e.y + 0.3)],
                       width: 1.1, color: color(HotaruPalette.eye, 0.85))
            }
        }
        if face.blush {
            ctx.setFillColor(color(HotaruPalette.blush, 0.85))
            ctx.fillEllipse(in: CGRect(x: 17.6, y: -1.6, width: 2.2, height: 1.3))
        }
        switch face.mouth {
        case .none: break
        case .smile: stroke([CGPoint(x: 14.4, y: -1.3), CGPoint(x: 15.6, y: -2.6), CGPoint(x: 16.8, y: -1.5)], width: 1, color: color(HotaruPalette.blush))
        case .open:
            ctx.setFillColor(color(HotaruPalette.blush))
            ctx.fillEllipse(in: CGRect(x: 15, y: -2.4, width: 1.6, height: 1.4))
        }
        ctx.restoreGState()

        // Waving: the front leg raised beside the face.
        if face.wave > 0 {
            // Reaches out past the face so it reads against the light behind it, with two motion marks.
            let lift = CGFloat(face.wave)
            let tip = CGPoint(x: 21 + 1.5 * lift, y: -3 + 7 * lift)
            stroke([CGPoint(x: 7, y: -3.6), CGPoint(x: 15, y: -6.5 + 2 * lift), tip], width: 1.3)
            for k in 0..<2 {
                let r = 2.2 + CGFloat(k) * 1.6
                ctx.addArc(center: tip, radius: r, startAngle: -0.5, endAngle: 0.6, clockwise: false)
                ctx.setStrokeColor(color(HotaruPalette.nightInk, 0.45))
                ctx.setLineWidth(0.7)
                ctx.strokePath()
            }
        }
    }

    // MARK: Menu-bar icon

    static func menuBarImage(theme: Theme) -> NSImage? {
        switch theme {
        case .minimal: return NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "Cursor highlighter")
        case .brushInk: return NSImage(systemSymbolName: "paintbrush.pointed", accessibilityDescription: "Cursor highlighter")
        case .cyberpunk: return NSImage(systemSymbolName: "scope", accessibilityDescription: "Cursor highlighter")
        case .keynoteGlow: return NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Cursor highlighter")
        case .hotaru:
            return hotaruTemplateIcon()
        }
    }

    /// The 18 pt menu-bar template: a solid black silhouette on clear so macOS tints it, with the
    /// lantern as a hollow ring around a dot (a template icon cannot glow).
    static func hotaruTemplateIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            // Lantern: ring and dot, lower left.
            ctx.setLineWidth(1.7)
            ctx.strokeEllipse(in: CGRect(x: 1.4, y: 1.4, width: 6.2, height: 6.2))
            ctx.fillEllipse(in: CGRect(x: 3.6, y: 3.6, width: 1.8, height: 1.8))
            // Body and head along a diagonal, up to the right.
            ctx.saveGState()
            ctx.translateBy(x: 9.6, y: 8.6)
            ctx.rotate(by: 40 * .pi / 180)
            ctx.fillEllipse(in: CGRect(x: -3.6, y: -2.2, width: 7.2, height: 4.4))
            ctx.restoreGState()
            ctx.fillEllipse(in: CGRect(x: 10.6, y: 9.8, width: 5.2, height: 5.2))
            // One wing, up and back, separated from the body by a clear gap.
            ctx.saveGState()
            ctx.translateBy(x: 7.4, y: 12.2)
            ctx.rotate(by: 25 * .pi / 180)
            ctx.fillEllipse(in: CGRect(x: -1.7, y: -1.2, width: 3.4, height: 6))
            ctx.restoreGState()
            // Antenna.
            ctx.setLineWidth(1.2)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 14.6, y: 14.6))
            ctx.addLine(to: CGPoint(x: 16.6, y: 17))
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cursor highlighter"
        return image
    }

    // MARK: Helpers

    static func shape(_ path: CGPath) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.path = path
        l.actions = ["position": NSNull(), "path": NSNull(), "bounds": NSNull()]
        return l
    }

    private static func glow(_ layer: CALayer, _ color: RGBA, radius: CGFloat) {
        layer.shadowColor = color.cg()
        layer.shadowOpacity = 1
        layer.shadowRadius = radius
        layer.shadowOffset = .zero
    }
}
