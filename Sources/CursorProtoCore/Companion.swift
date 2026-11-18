/// The firefly companion's poses. It rests beside the cursor, beats its wings while the cursor
/// moves, beams and lights up on a left click, tilts its head at a right click, holds its tail
/// light steady while the laser is on, and dozes off when the cursor stops.
public enum CompanionPose: String, CaseIterable, Sendable {
    case rest, flyA, flyB, happy, glow, curious, focus, doze
}

/// How a pose looks, as plain values the drawing code reads.
public struct CompanionFace: Equatable, Sendable {
    public enum Eyes: Equatable, Sendable { case open, wide, happy, half, closed }
    public enum Mouth: Equatable, Sendable { case smile, open, flat, small }

    public var eyes: Eyes
    public var mouth: Mouth
    /// Tail light, 0 (off) to 1 (full).
    public var glow: Double
    /// Wing angle in degrees above level.
    public var wing: Double
    /// Head tilt in degrees (positive leans toward the cursor).
    public var tilt: Double

    public static func of(_ pose: CompanionPose) -> CompanionFace {
        switch pose {
        case .rest: CompanionFace(eyes: .open, mouth: .smile, glow: 0.45, wing: 10, tilt: 0)
        case .flyA: CompanionFace(eyes: .open, mouth: .small, glow: 0.55, wing: 40, tilt: 4)
        case .flyB: CompanionFace(eyes: .open, mouth: .small, glow: 0.55, wing: -12, tilt: 4)
        case .happy: CompanionFace(eyes: .happy, mouth: .open, glow: 0.8, wing: 30, tilt: 0)
        case .glow: CompanionFace(eyes: .happy, mouth: .smile, glow: 1, wing: 20, tilt: 0)
        case .curious: CompanionFace(eyes: .wide, mouth: .small, glow: 0.6, wing: 15, tilt: 14)
        case .focus: CompanionFace(eyes: .open, mouth: .flat, glow: 1, wing: 25, tilt: 6)
        case .doze: CompanionFace(eyes: .closed, mouth: .small, glow: 0.2, wing: 0, tilt: -6)
        }
    }
}

/// Which pose the companion shows. Event-driven so a still cursor needs no timer: wings flap
/// every `strokeLength` points of travel, clicks react, and the caller asks for `pose(at:)` again
/// only when `nextChange(after:)` says something will change.
public struct CompanionAnimator: Sendable {
    public var strokeLength = 12.0
    /// Back to resting this long after the last move.
    public var settleDelay = 0.25
    public var reactionDuration = 0.75
    /// A left-click beam turns into the tail flash this far in.
    public var glowAt = 0.3

    public private(set) var facingLeft = false
    private var travel = 0.0
    private var lastMove = -Double.infinity
    private var reactionStart = -Double.infinity
    private var reaction = CompanionPose.happy

    public init() {}

    public mutating func moved(dx: Double, dy: Double, time: Double) {
        travel += (dx * dx + dy * dy).squareRoot()
        if abs(dx) > 0.5 { facingLeft = dx < 0 }
        lastMove = time
    }

    /// Left click beams (then flashes its tail); right and middle clicks get a curious tilt.
    public mutating func clicked(_ button: MouseButton, time: Double) {
        reactionStart = time
        reaction = button == .left ? .happy : .curious
    }

    /// `laser` holds the focus pose; `idle` (the cursor has gone quiet) shows the doze pose.
    public func pose(at time: Double, laser: Bool = false, idle: Bool = false) -> CompanionPose {
        let sinceReaction = time - reactionStart
        if sinceReaction >= 0 && sinceReaction < reactionDuration {
            if reaction == .happy { return sinceReaction < glowAt ? .happy : .glow }
            return reaction
        }
        if time - lastMove < settleDelay {
            return Int(travel / strokeLength).isMultiple(of: 2) ? .flyA : .flyB
        }
        if laser { return .focus }
        return idle ? .doze : .rest
    }

    /// When the pose will next change with no further input, or nil if it is settled.
    public func nextChange(after time: Double) -> Double? {
        let reactionEnd = reactionStart + reactionDuration
        if reaction == .happy && time < reactionStart + glowAt { return reactionStart + glowAt }
        if time < reactionEnd { return max(reactionEnd, lastMove + settleDelay) }
        if time < lastMove + settleDelay { return lastMove + settleDelay }
        return nil
    }
}

/// A seal stamp landing: it drops in slightly large, settles, holds, then fades.
public struct StampTiming: Equatable, Sendable {
    public var land = 0.12
    public var hold = 0.45
    public var fade = 0.45
    public var startScale = 1.35

    public init() {}

    public var duration: Double { land + hold + fade }

    public func scale(age: Double) -> Double {
        guard age < land else { return 1 }
        return startScale - (startScale - 1) * easeOut(max(age, 0) / land)
    }

    public func alpha(age: Double) -> Double {
        if age < 0 { return 0 }
        if age < land { return age / land }
        if age < land + hold { return 1 }
        return (1 - (age - land - hold) / fade).clamped(0, 1)
    }
}
