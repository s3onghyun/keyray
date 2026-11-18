/// Hotaru's poses, from the character sheet. It rests beside the cursor with its lantern on,
/// beats its wings while moving, flashes its lantern on a left click, tilts its head at a right or
/// middle click, holds its light as the laser pointer, dozes with the lantern dimmed, and waves
/// hello once on first launch.
public enum CompanionPose: String, CaseIterable, Sendable {
    case rest, flyA, flyB, flash, curious, focus, doze, waveA, waveB
}

/// How a pose looks, as plain values the drawing code reads.
public struct CompanionFace: Equatable, Sendable {
    public enum Eyes: Equatable, Sendable { case open, wide, happy, half, closed }
    public enum Mouth: Equatable, Sendable { case none, smile, open }

    public var eyes: Eyes
    public var mouth: Mouth
    /// Lantern light, 0 (off) to 1 (full). Dozing keeps about 15%.
    public var glow: Double
    /// Wing angle in degrees above the body.
    public var wing: Double
    /// Head tilt in degrees (positive tips the head back, looking up).
    public var tilt: Double
    /// Body pitch in degrees (positive raises the head end).
    public var pitch: Double
    /// Blush is only for happy and waving.
    public var blush: Bool
    /// Front leg raised (waving), 0 = down, 1 = up.
    public var wave: Double

    public static func of(_ pose: CompanionPose) -> CompanionFace {
        switch pose {
        case .rest: CompanionFace(eyes: .open, mouth: .none, glow: 0.6, wing: 0, tilt: 0, pitch: 0, blush: false, wave: 0)
        case .flyA: CompanionFace(eyes: .open, mouth: .none, glow: 0.65, wing: 30, tilt: 0, pitch: 8, blush: false, wave: 0)
        case .flyB: CompanionFace(eyes: .open, mouth: .none, glow: 0.65, wing: -6, tilt: 0, pitch: 8, blush: false, wave: 0)
        case .flash: CompanionFace(eyes: .happy, mouth: .smile, glow: 1, wing: 10, tilt: 0, pitch: 0, blush: true, wave: 0)
        case .curious: CompanionFace(eyes: .wide, mouth: .none, glow: 0.7, wing: 4, tilt: 14, pitch: 0, blush: false, wave: 0)
        case .focus: CompanionFace(eyes: .half, mouth: .none, glow: 1, wing: 6, tilt: -4, pitch: 0, blush: false, wave: 0)
        case .doze: CompanionFace(eyes: .closed, mouth: .none, glow: 0.15, wing: -4, tilt: -8, pitch: -4, blush: false, wave: 0)
        case .waveA: CompanionFace(eyes: .happy, mouth: .smile, glow: 0.8, wing: 8, tilt: 4, pitch: 0, blush: true, wave: 1)
        case .waveB: CompanionFace(eyes: .happy, mouth: .smile, glow: 0.8, wing: 8, tilt: 4, pitch: 0, blush: true, wave: 0.45)
        }
    }
}

/// Which pose the companion shows. Event-driven so a still cursor needs no timer: wings beat every
/// `strokeLength` points of travel, clicks and the greeting play for a fixed time, and the caller
/// asks for `pose(at:)` again only when `nextChange(after:)` says something will change.
public struct CompanionAnimator: Sendable {
    public var strokeLength = 12.0
    /// Back to resting this long after the last move.
    public var settleDelay = 0.25
    /// Click flash: about 120 ms up and 400 ms back (the lantern animation itself runs in Core
    /// Animation; this is how long the face shows it).
    public var flashDuration = 0.52
    public var curiousDuration = 0.75
    public var waveDuration = 2.4
    /// Each wave stroke.
    public var waveStroke = 0.3

    public private(set) var facingLeft = false
    private var travel = 0.0
    private var lastMove = -Double.infinity
    private var reactionStart = -Double.infinity
    private var reaction = CompanionPose.flash
    private var waveStart = -Double.infinity

    public init() {}

    public mutating func moved(dx: Double, dy: Double, time: Double) {
        travel += (dx * dx + dy * dy).squareRoot()
        if abs(dx) > 0.5 { facingLeft = dx < 0 }
        lastMove = time
    }

    /// Left click flashes the lantern; right and middle clicks get a curious tilt.
    public mutating func clicked(_ button: MouseButton, time: Double) {
        reactionStart = time
        reaction = button == .left ? .flash : .curious
    }

    /// The first-launch hello.
    public mutating func greet(time: Double) { waveStart = time }

    private var reactionDuration: Double { reaction == .flash ? flashDuration : curiousDuration }

    public func isWaving(at time: Double) -> Bool { time >= waveStart && time - waveStart < waveDuration }

    /// `laser` holds the light as the pointer; `idle` (the cursor has gone quiet) dozes.
    public func pose(at time: Double, laser: Bool = false, idle: Bool = false) -> CompanionPose {
        let sinceReaction = time - reactionStart
        if sinceReaction >= 0 && sinceReaction < reactionDuration { return reaction }
        if isWaving(at: time) {
            return Int((time - waveStart) / waveStroke).isMultiple(of: 2) ? .waveA : .waveB
        }
        if time - lastMove < settleDelay {
            return Int(travel / strokeLength).isMultiple(of: 2) ? .flyA : .flyB
        }
        if laser { return .focus }
        return idle ? .doze : .rest
    }

    /// When the pose will next change with no further input, or nil if it is settled.
    public func nextChange(after time: Double) -> Double? {
        var candidates: [Double] = []
        let reactionEnd = reactionStart + reactionDuration
        if time < reactionEnd { candidates.append(reactionEnd) }
        if isWaving(at: time) {
            let next = waveStart + (((time - waveStart) / waveStroke).rounded(.down) + 1) * waveStroke
            candidates.append(min(next, waveStart + waveDuration))
        }
        if time < lastMove + settleDelay { candidates.append(lastMove + settleDelay) }
        return candidates.filter { $0 > time }.min()
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
