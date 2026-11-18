import AppKit
import KeyrayCore

/// Listen-only keyboard event tap. A sandboxed app may do this with the Input Monitoring
/// privilege (not Accessibility). The tap can only observe; it never changes or swallows events,
/// and macOS withholds keystrokes typed into secure fields (passwords) from it.
@MainActor
final class KeyTap {
    enum State: Equatable {
        case stopped
        /// Input Monitoring is not granted (CGPreflightListenEventAccess returned false).
        case needsPermission
        /// Permission reported granted but CGEvent.tapCreate still returned nil.
        case tapFailed
        case running
    }

    private(set) var state = State.stopped
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let onKey: (KeyStroke, Bool) -> Void

    init(onKey: @escaping (KeyStroke, _ isRepeat: Bool) -> Void) {
        self.onKey = onKey
    }

    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system Input Monitoring prompt (only the first time; afterwards macOS just returns
    /// the current answer). Returns whether access is granted right now.
    @discardableResult
    static func requestPermission() -> Bool {
        let granted = CGRequestListenEventAccess()
        Log.keys.notice("CGRequestListenEventAccess -> \(granted)")
        return granted
    }

    /// Starts the tap if allowed. Safe to call repeatedly.
    @discardableResult
    func start() -> State {
        if state == .running { return state }
        let preflight = Self.hasPermission
        Log.keys.notice("CGPreflightListenEventAccess -> \(preflight)")
        guard preflight else {
            state = .needsPermission
            return state
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: keyTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Log.keys.error("CGEvent.tapCreate(listenOnly) returned nil")
            state = .tapFailed
            return state
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        state = .running
        Log.keys.notice("listen-only key tap running")
        return state
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        if state == .running { state = .stopped }
    }

    fileprivate func received(_ type: CGEventType, keyCode: Int, flags: CGEventFlags, isRepeat: Bool) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.keys.notice("key tap re-enabled after \(type.rawValue)")
        case .keyDown:
            onKey(KeyStroke(keyCode: keyCode, modifiers: KeyModifiers(flags)), isRepeat)
        default:
            break
        }
    }
}

private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let tap = Unmanaged<KeyTap>.fromOpaque(userInfo).takeUnretainedValue()
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let flags = event.flags
        // The run loop source is on the main run loop, so this runs on the main thread.
        MainActor.assumeIsolated { tap.received(type, keyCode: keyCode, flags: flags, isRepeat: isRepeat) }
    }
    return Unmanaged.passUnretained(event)
}

extension KeyModifiers {
    init(_ flags: CGEventFlags) {
        var m: KeyModifiers = []
        if flags.contains(.maskControl) { m.insert(.control) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskAlphaShift) { m.insert(.capsLock) }
        if flags.contains(.maskSecondaryFn) { m.insert(.function) }
        self = m
    }
}
