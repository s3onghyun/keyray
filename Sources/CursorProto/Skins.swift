import AppKit
import CursorProtoCore

/// How each theme draws the ring, click effect, laser tip and companion. All of it is built once
/// per settings change; per-move work stays a layer position update.
@MainActor
enum Skin {
    /// The firefly companion's drawing box, in points.
    static let companionSize: CGFloat = 48

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

        case .firefly:
            // A ring of small lights on a thin night-teal line.
            let line = shape(circle)
            line.fillColor = nil
            line.strokeColor = style.ringOutline?.cg()
            line.lineWidth = 1.5
            let lights = shape(circle)
            lights.fillColor = nil
            lights.strokeColor = style.ring.cg()
            lights.lineWidth = s.ringLineWidth + 2.5
            lights.lineCap = .round
            let gap = Double.pi * d / 12
            lights.lineDashPattern = [0, NSNumber(value: gap)]
            glow(lights, style.ring, radius: 3)
            container.addSublayer(line)
            container.addSublayer(lights)

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
    static func addClickEffect(to root: CALayer, at point: CGPoint, button: MouseButton, settings s: AppSettings) {
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
        case .firefly:
            lightBurst(root: root, at: point, color: color, duration: s.rippleDuration)
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

    /// Six small lights thrown outward, glowing as they go.
    private static func lightBurst(root: CALayer, at point: CGPoint, color: RGBA, duration: Double) {
        let dots = CGMutablePath()
        for i in 0..<6 {
            let a = Double(i) * .pi / 3 + .pi / 6
            let c = CGPoint(x: cos(a) * 11, y: sin(a) * 11)
            dots.addEllipse(in: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5))
        }
        let layer = shape(dots)
        layer.fillColor = color.cg()
        glow(layer, color, radius: 4)
        layer.position = point
        layer.opacity = 0

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.5
        scale.toValue = 2.8
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        let alpha = CABasicAnimation(keyPath: "opacity")
        alpha.fromValue = 1
        alpha.toValue = 0
        alpha.timingFunction = CAMediaTimingFunction(name: .easeIn)
        run(layer, in: root, animations: [scale, alpha], duration: max(duration, 0.45), delay: 0)
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

        case .firefly:
            // The firefly's light: a warm halo around a near-white core.
            let halo = shape(CGPath(ellipseIn: CGRect(x: -dot, y: -dot, width: dot * 2, height: dot * 2), transform: nil))
            halo.fillColor = style.laser.cg(alpha: 0.4)
            glow(halo, style.laser, radius: 10)
            let core = shape(CGPath(ellipseIn: CGRect(x: -dot / 3, y: -dot / 3, width: dot / 1.5, height: dot / 1.5), transform: nil))
            core.fillColor = RGBA(hex: 0xFFFBEA).cg()
            container.addSublayer(halo)
            container.addSublayer(core)
            ribbon.fillColor = style.laser.cg(alpha: 0.5)

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

    /// The firefly in a pose, drawn with Core Graphics at 2× and cached. Facing right by default.
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
        drawFirefly(in: ctx, face: CompanionFace.of(pose))
        let image = ctx.makeImage()
        companionCache[key] = image
        return image
    }

    /// The firefly in a 48×48 pt box (y up): a round night-teal body, a cream face that looks
    /// toward the cursor (to the right), two antennae, clear wings and a light in its tail.
    static func drawFirefly(in ctx: CGContext, face: CompanionFace) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: 6, y: 2) // room for the tail glow
        func color(_ hex: UInt32, _ a: Double = 1) -> CGColor { RGBA(hex: hex, alpha: a).cg() }
        func ellipse(_ r: CGRect, _ fill: CGColor) { ctx.setFillColor(fill); ctx.fillEllipse(in: r) }

        // Tail light and its glow.
        let tail = CGPoint(x: 10, y: 13)
        if face.glow > 0.05 {
            let glowColors = [color(FireflyPalette.lightGlow, 0.85 * face.glow), color(FireflyPalette.lightGlow, 0)] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: glowColors, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: tail, startRadius: 0, endCenter: tail, endRadius: 6 + 9 * face.glow, options: [])
            }
        }
        ellipse(CGRect(x: tail.x - 6, y: tail.y - 5, width: 12, height: 10),
                color(FireflyPalette.light, 0.45 + 0.55 * face.glow))

        // Back wing, body, front wing.
        func wing(_ origin: CGPoint, _ angle: Double, _ alpha: Double) {
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.rotate(by: CGFloat((90 + angle) * .pi / 180))
            let r = CGRect(x: -4, y: -1, width: 8, height: 15)
            ctx.setFillColor(color(FireflyPalette.wing, alpha))
            ctx.fillEllipse(in: r)
            ctx.setStrokeColor(color(FireflyPalette.body, 0.5))
            ctx.setLineWidth(0.8)
            ctx.strokeEllipse(in: r)
            ctx.restoreGState()
        }
        wing(CGPoint(x: 19, y: 22), face.wing + 12, 0.5)
        ellipse(CGRect(x: 10, y: 8, width: 20, height: 17), color(FireflyPalette.body))
        ellipse(CGRect(x: 12, y: 8, width: 16, height: 6), color(FireflyPalette.bodyShade, 0.6))
        wing(CGPoint(x: 17, y: 21), face.wing, 0.75)

        // Head, tilted toward the cursor.
        ctx.saveGState()
        let neck = CGPoint(x: 27, y: 19)
        ctx.translateBy(x: neck.x, y: neck.y)
        ctx.rotate(by: CGFloat(-face.tilt * .pi / 180))
        ctx.translateBy(x: -neck.x, y: -neck.y)

        // Antennae with small lit tips.
        ctx.setStrokeColor(color(FireflyPalette.body))
        ctx.setLineWidth(1.4)
        ctx.setLineCap(.round)
        for (base, tip, ctl) in [(CGPoint(x: 26, y: 31), CGPoint(x: 23, y: 39), CGPoint(x: 23, y: 35)),
                                 (CGPoint(x: 31, y: 31), CGPoint(x: 35, y: 39), CGPoint(x: 35, y: 34))] {
            ctx.move(to: base)
            ctx.addQuadCurve(to: tip, control: ctl)
            ctx.strokePath()
            ellipse(CGRect(x: tip.x - 1.8, y: tip.y - 1.8, width: 3.6, height: 3.6), color(FireflyPalette.light))
        }

        ellipse(CGRect(x: 19, y: 15, width: 18, height: 18), color(FireflyPalette.body))
        let faceRect = CGRect(x: 22, y: 16.5, width: 14, height: 13)
        ellipse(faceRect, color(FireflyPalette.face))
        ellipse(CGRect(x: 23, y: 19.5, width: 3, height: 2), color(FireflyPalette.cheek, 0.7))
        ellipse(CGRect(x: 32.5, y: 19.5, width: 3, height: 2), color(FireflyPalette.cheek, 0.7))

        // Eyes look toward the cursor (right).
        ctx.setStrokeColor(color(FireflyPalette.eye))
        ctx.setLineWidth(1.3)
        for x in [26.6, 31.6] {
            let c = CGPoint(x: x, y: 24)
            switch face.eyes {
            case .open, .wide:
                let w: CGFloat = face.eyes == .wide ? 3.2 : 2.6, h: CGFloat = face.eyes == .wide ? 3.8 : 3.2
                ellipse(CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), color(FireflyPalette.eye))
                ellipse(CGRect(x: c.x - w / 2 + 1.4, y: c.y + h / 2 - 1.5, width: 1, height: 1), color(0xFFFFFF))
            case .happy:
                ctx.move(to: CGPoint(x: c.x - 1.6, y: c.y - 0.5))
                ctx.addQuadCurve(to: CGPoint(x: c.x + 1.6, y: c.y - 0.5), control: CGPoint(x: c.x, y: c.y + 2.2))
                ctx.strokePath()
            case .half:
                ellipse(CGRect(x: c.x - 1.3, y: c.y - 1.2, width: 2.6, height: 1.8), color(FireflyPalette.eye))
            case .closed:
                ctx.move(to: CGPoint(x: c.x - 1.5, y: c.y))
                ctx.addQuadCurve(to: CGPoint(x: c.x + 1.5, y: c.y), control: CGPoint(x: c.x, y: c.y - 1.6))
                ctx.strokePath()
            }
        }

        // Mouth.
        let m = CGPoint(x: 29.2, y: 20)
        ctx.setLineWidth(1.1)
        switch face.mouth {
        case .smile:
            ctx.move(to: CGPoint(x: m.x - 1.6, y: m.y + 0.6))
            ctx.addQuadCurve(to: CGPoint(x: m.x + 1.6, y: m.y + 0.6), control: CGPoint(x: m.x, y: m.y - 1.2))
            ctx.strokePath()
        case .open:
            ellipse(CGRect(x: m.x - 1.5, y: m.y - 1.2, width: 3, height: 2.4), color(0xC0504D))
        case .flat:
            ctx.move(to: CGPoint(x: m.x - 1.2, y: m.y))
            ctx.addLine(to: CGPoint(x: m.x + 1.2, y: m.y))
            ctx.strokePath()
        case .small:
            ellipse(CGRect(x: m.x - 0.8, y: m.y - 0.6, width: 1.6, height: 1.4), color(FireflyPalette.eye))
        }
        ctx.restoreGState()
    }

    // MARK: Menu-bar icon

    static func menuBarImage(theme: Theme) -> NSImage? {
        switch theme {
        case .minimal: return NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "Cursor highlighter")
        case .brushInk: return NSImage(systemSymbolName: "paintbrush.pointed", accessibilityDescription: "Cursor highlighter")
        case .keynoteGlow: return NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Cursor highlighter")
        case .firefly:
            let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                ctx.scaleBy(x: rect.width / companionSize, y: rect.height / companionSize)
                drawFirefly(in: ctx, face: CompanionFace.of(.rest))
                return true
            }
            image.accessibilityDescription = "Cursor highlighter"
            return image
        }
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
