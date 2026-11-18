import Foundation

/// Ease-out cubic: fast start, gentle stop.
public func easeOut(_ t: Double) -> Double {
    let u = 1 - t.clamped(0, 1)
    return 1 - u * u * u
}

/// A click ripple: a ring that grows from `startScale` to full size while fading out.
public struct RippleTiming: Equatable, Sendable {
    public var duration: Double
    public var startScale = 0.25
    public var startAlpha = 0.9

    public init(duration: Double) { self.duration = max(duration, 0.01) }

    /// 0 at the click, 1 when the ripple is gone.
    public func progress(age: Double) -> Double { (age / duration).clamped(0, 1) }

    public func scale(age: Double) -> Double {
        startScale + (1 - startScale) * easeOut(progress(age: age))
    }

    public func alpha(age: Double) -> Double { startAlpha * (1 - progress(age: age)) }

    public func isFinished(age: Double) -> Bool { age >= duration }
}

/// Temporary ink: fully visible for `hold` seconds after the stroke ends, then a linear fade.
public struct InkFade: Equatable, Sendable {
    public var hold: Double
    public var fade: Double

    public init(hold: Double, fade: Double) {
        self.hold = max(hold, 0)
        self.fade = max(fade, 0.01)
    }

    /// `age` counts from the end of the stroke; a stroke still being drawn has a negative age.
    public func alpha(age: Double) -> Double {
        if age <= hold { return 1 }
        return (1 - (age - hold) / fade).clamped(0, 1)
    }

    public var lifetime: Double { hold + fade }

    public func isFinished(age: Double) -> Bool { age >= lifetime }
}

/// Ring visibility in `.always` mode: hidden after `idleSeconds` without movement, with a short fade.
public struct IdleVisibility: Equatable, Sendable {
    public var idleSeconds: Double
    public var fadeSeconds = 0.3

    public init(idleSeconds: Double) { self.idleSeconds = idleSeconds }

    public func alpha(sinceLastMove: Double) -> Double {
        guard idleSeconds > 0 else { return 1 }
        if sinceLastMove <= idleSeconds { return 1 }
        return (1 - (sinceLastMove - idleSeconds) / fadeSeconds).clamped(0, 1)
    }

    /// Seconds until the ring starts hiding, or nil when it never hides.
    public func secondsUntilHide(sinceLastMove: Double) -> Double? {
        guard idleSeconds > 0 else { return nil }
        return max(idleSeconds - sinceLastMove, 0)
    }
}

public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to p: Point) -> Double { hypot(p.x - x, p.y - y) }
}

public struct TimedPoint: Equatable, Sendable {
    public var point: Point
    public var time: Double
    public init(_ point: Point, time: Double) {
        self.point = point
        self.time = time
    }
}

/// The vanishing laser trail: recent cursor positions that thin out and disappear after `duration`.
public struct LaserTrail: Sendable {
    public var duration: Double
    public var maxWidth: Double
    public private(set) var points: [TimedPoint] = []

    public init(duration: Double, maxWidth: Double) {
        self.duration = max(duration, 0.01)
        self.maxWidth = maxWidth
    }

    /// Adds a sample, skipping ones closer than half a point to the previous sample.
    public mutating func add(_ p: Point, time: Double) {
        if let last = points.last, last.point.distance(to: p) < 0.5 {
            points[points.count - 1].time = time
            return
        }
        points.append(TimedPoint(p, time: time))
    }

    /// Drops samples older than `duration`. Returns true while anything is left to draw.
    @discardableResult
    public mutating func prune(now: Double) -> Bool {
        points.removeAll { now - $0.time >= duration }
        return !points.isEmpty
    }

    public mutating func clear() { points.removeAll() }

    /// Width at a sample: full at the newest end, tapering to zero at `duration` old.
    public func width(age: Double) -> Double { maxWidth * (1 - age / duration).clamped(0, 1) }

    /// A closed polygon around the trail (left side forward, right side back), so one filled
    /// path draws a tapered ribbon. Empty when fewer than two samples are alive.
    public func ribbon(now: Double) -> [Point] {
        let alive = points.filter { now - $0.time < duration }
        guard alive.count >= 2 else { return [] }
        var left: [Point] = []
        var right: [Point] = []
        for (i, s) in alive.enumerated() {
            let a = alive[max(i - 1, 0)].point
            let b = alive[min(i + 1, alive.count - 1)].point
            var dx = b.x - a.x
            var dy = b.y - a.y
            let len = hypot(dx, dy)
            if len > 0 {
                dx /= len
                dy /= len
            }
            let half = width(age: now - s.time) / 2
            left.append(Point(s.point.x - dy * half, s.point.y + dx * half))
            right.append(Point(s.point.x + dy * half, s.point.y - dx * half))
        }
        return left + right.reversed()
    }
}

/// Arrowhead wings for a stroke from `start` to `end`: two points that, joined to `end`, draw the head.
/// Nil for strokes too short to point anywhere.
public func arrowHead(from start: Point, to end: Point, length: Double, spreadDegrees: Double = 28) -> (Point, Point)? {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let len = hypot(dx, dy)
    guard len >= 4 else { return nil }
    let headLength = min(length, len * 0.6)
    let angle = atan2(dy, dx)
    let spread = spreadDegrees * .pi / 180
    let a1 = angle + .pi - spread
    let a2 = angle + .pi + spread
    return (Point(end.x + cos(a1) * headLength, end.y + sin(a1) * headLength),
            Point(end.x + cos(a2) * headLength, end.y + sin(a2) * headLength))
}
