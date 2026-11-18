import Carbon.HIToolbox
import KeyrayCore

/// Global shortcuts through Carbon's RegisterEventHotKey. Unlike a key event tap or a global
/// key monitor, this needs no Accessibility or Input Monitoring permission and works in the sandbox.
@MainActor
final class HotKeys {
    private var refs: [AppShortcut: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private let onPress: (AppShortcut) -> Void
    private static let signature: OSType = 0x4350_5254 // "CPRT"

    init(onPress: @escaping (AppShortcut) -> Void) {
        self.onPress = onPress
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard let userData, let shortcut = AppShortcut.allCases[safe: Int(id.id)] else { return noErr }
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKeys.onPress(shortcut) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        if status != noErr { Log.app.error("InstallEventHandler failed: \(status)") }
    }

    func register(_ shortcut: AppShortcut) {
        guard refs[shortcut] == nil, let index = AppShortcut.allCases.firstIndex(of: shortcut) else { return }
        var ref: EventHotKeyRef?
        let s = shortcut.stroke
        let status = RegisterEventHotKey(UInt32(s.keyCode), Self.carbonModifiers(s.modifiers),
                                         EventHotKeyID(signature: Self.signature, id: UInt32(index)),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[shortcut] = ref
        } else {
            Log.app.error("RegisterEventHotKey \(shortcut.rawValue, privacy: .public) failed: \(status)")
        }
    }

    func unregister(_ shortcut: AppShortcut) {
        guard let ref = refs.removeValue(forKey: shortcut) else { return }
        UnregisterEventHotKey(ref)
    }

    var registered: [AppShortcut] { AppShortcut.allCases.filter { refs[$0] != nil } }

    private static func carbonModifiers(_ m: KeyModifiers) -> UInt32 {
        var c = 0
        if m.contains(.command) { c |= cmdKey }
        if m.contains(.shift) { c |= shiftKey }
        if m.contains(.option) { c |= optionKey }
        if m.contains(.control) { c |= controlKey }
        return UInt32(c)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
