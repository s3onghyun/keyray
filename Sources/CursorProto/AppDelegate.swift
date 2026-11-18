import AppKit
import Combine
import CursorProtoCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = SettingsStore()
    private var overlay: OverlayController!
    private var keycaps: KeycapHUD!
    private var keyTap: KeyTap!
    private var hotKeys: HotKeys!
    private var statusItem: NSStatusItem!
    private var monitors: [Any] = []
    private var cancellables: Set<AnyCancellable> = []
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var lastKeycapMode = KeycapMode.shortcutsOnly
    private var permissionPoll: Timer?

    /// Reasons the overlays are hidden right now; they show only when this is empty.
    private enum HideReason: Hashable { case switchedOff, permissionPrompt, systemUI }
    private var hideReasons: Set<HideReason> = []

    /// Frontmost apps that put up permission or password UI. Clicks on such UI can be refused
    /// while another app's window floats above it, so the overlays step aside.
    private static let systemUIBundles: Set<String> = [
        "com.apple.systempreferences", "com.apple.Settings", "com.apple.SecurityAgent",
        "com.apple.UserNotificationCenter", "com.apple.coreservices.uiagent",
    ]

    private var settings: AppSettings { store.settings }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        Log.app.notice("launch: sandboxed=\(sandboxed) bundle=\(Bundle.main.bundleIdentifier ?? "-", privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier)")
        // Inside the App Sandbox the home directory is the app's container.
        Log.app.notice("home: \(NSHomeDirectory().replacingOccurrences(of: "/Users/\(NSUserName())", with: "~"), privacy: .public)")

        overlay = OverlayController(settings: settings)
        overlay.onInkAutoRelease = { [weak self] in self?.setInk(false) }
        keycaps = KeycapHUD(settings: settings)
        keycaps.onMoved = { [weak self] p in self?.store.settings.keycapPosition = p }
        keyTap = KeyTap { [weak self] stroke, isRepeat in self?.keycaps.record(stroke, isRepeat: isRepeat) }
        hotKeys = HotKeys { [weak self] in self?.perform($0) }
        for s in AppShortcut.permanent { hotKeys.register(s) }
        Log.app.notice("hotkeys registered: \(self.hotKeys.registered.map(\.rawValue).joined(separator: ","), privacy: .public)")

        setUpStatusItem()

        store.$settings.dropFirst().sink { [weak self] s in
            // @Published fires before the value is stored; apply on the next turn.
            DispatchQueue.main.async { self?.settingsChanged(s) }
        }.store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.overlay.rebuildWindows() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.frontmostChanged(id) }
        }

        if !settings.enabled { hideReasons.insert(.switchedOff) }
        if settings.keycapMode != .off { lastKeycapMode = settings.keycapMode; startKeycaps(prompt: false) }
        frontmostChanged(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        updateVisibility()
    }

    // MARK: Input

    /// Mouse position and clicks from every app. NSEvent's global monitor needs no permission for
    /// mouse events (only key events require Accessibility), so this works in the sandbox as is.
    private func installMouseMonitors() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                           .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                           .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.overlay.handle(e) }
        }) { monitors.append(global) }
        // Our own overlay windows while ink mode holds the mouse.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated {
                if e.window is OverlayWindow { self?.overlay.handle(e) }
            }
            return e
        }) { monitors.append(local) }
        Log.app.notice("mouse monitors installed: \(self.monitors.count)")
    }

    /// While everything is hidden the app stops receiving mouse events altogether.
    private func removeMouseMonitors() {
        guard !monitors.isEmpty else { return }
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        Log.app.notice("mouse monitors removed")
    }

    private func perform(_ shortcut: AppShortcut) {
        Log.app.notice("hotkey \(shortcut.rawValue, privacy: .public)")
        switch shortcut {
        case .toggleOverlays: store.settings.enabled.toggle()
        case .toggleLaser: setLaser(!overlay.laserOn)
        case .toggleInk: setInk(!overlay.inkArmed)
        case .toggleKeycaps: toggleKeycaps()
        case .pen: selectTool(.pen)
        case .arrow: selectTool(.arrow)
        case .highlighter: selectTool(.highlighter)
        case .clearInk: overlay.clearInk()
        case .exitInk: setInk(false)
        }
    }

    private func setLaser(_ on: Bool) {
        if on && !settings.enabled { store.settings.enabled = true }
        overlay.laserOn = on
        refreshStatusIcon()
    }

    private func setInk(_ on: Bool) {
        if on && !settings.enabled { store.settings.enabled = true }
        overlay.inkArmed = on
        // Esc leaves ink mode, but only while it is armed; otherwise Esc belongs to the frontmost app.
        if on { hotKeys.register(.exitInk) } else { hotKeys.unregister(.exitInk) }
        refreshStatusIcon()
    }

    private func selectTool(_ tool: InkTool) {
        store.settings.inkTool = tool
        setInk(true)
    }

    // MARK: AppSettings and visibility

    private func settingsChanged(_ s: AppSettings) {
        overlay.apply(s)
        keycaps.apply(s)
        if s.enabled { hideReasons.remove(.switchedOff) } else { hideReasons.insert(.switchedOff) }
        if s.keycapMode == .off {
            keyTap.stop()
        } else {
            lastKeycapMode = s.keycapMode
            if keyTap.state != .running { startKeycaps(prompt: false) }
        }
        if !s.hideWhileSystemSettingsFrontmost { hideReasons.remove(.systemUI) }
        updateVisibility()
        refreshStatusIcon()
    }

    private func updateVisibility() {
        let show = hideReasons.isEmpty
        if !show && overlay.inkArmed { setInk(false) }
        if show { installMouseMonitors() } else { removeMouseMonitors() }
        overlay.setVisible(show)
        keycaps.setSuppressed(!show)
    }

    private func frontmostChanged(_ bundleID: String?) {
        guard let bundleID else { return }
        let system = settings.hideWhileSystemSettingsFrontmost && Self.systemUIBundles.contains(bundleID)
        let had = hideReasons.contains(.systemUI)
        if system { hideReasons.insert(.systemUI) } else { hideReasons.remove(.systemUI) }
        if had != system {
            Log.app.notice("frontmost \(bundleID, privacy: .public): overlays \(system ? "hidden for system UI" : "restored", privacy: .public)")
            updateVisibility()
        }
    }

    // MARK: Keycaps and Input Monitoring

    private func toggleKeycaps() {
        store.settings.keycapMode = settings.keycapMode == .off ? lastKeycapMode : .off
        if settings.keycapMode != .off && keyTap.state != .running { showOnboarding() }
    }

    private func startKeycaps(prompt: Bool) {
        let state = keyTap.start()
        Log.keys.notice("keycaps start -> \(String(describing: state), privacy: .public)")
        if state == .needsPermission && prompt { showOnboarding() }
        rebuildMenu()
    }

    /// Asks macOS for Input Monitoring with every overlay hidden, so nothing floats over the prompt.
    private func requestInputMonitoring() {
        hideReasons.insert(.permissionPrompt)
        updateVisibility()
        let granted = KeyTap.requestPermission()
        if granted {
            endPermissionWait()
            return
        }
        // Poll briefly for the grant; give the screen back after 30 s either way.
        let started = Date()
        permissionPoll?.invalidate()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if KeyTap.hasPermission || Date().timeIntervalSince(started) > 30 { self.endPermissionWait() }
            }
        }
    }

    private func endPermissionWait() {
        permissionPoll?.invalidate()
        permissionPoll = nil
        hideReasons.remove(.permissionPrompt)
        updateVisibility()
        if settings.keycapMode == .off { store.settings.keycapMode = lastKeycapMode }
        startKeycaps(prompt: false)
        if keyTap.state == .running { onboardingWindow?.close() }
        refreshOnboarding()
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(
                status: { [weak self] in self?.keycapStatusText ?? "" },
                request: { [weak self] in self?.requestInputMonitoring() },
                openSettings: { [weak self] in self?.openInputMonitoringSettings() },
                retry: { [weak self] in self?.startKeycaps(prompt: false); self?.refreshOnboarding() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Keycaps need Input Monitoring"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            onboardingWindow = w
        }
        refreshOnboarding()
        if let w = onboardingWindow, let size = w.contentViewController?.view.fittingSize { w.setContentSize(size) }
        onboardingWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func refreshOnboarding() {
        NotificationCenter.default.post(name: .keycapStatusChanged, object: nil)
    }

    private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private var keycapStatusText: String {
        switch keyTap.state {
        case .running: "Keycaps are on (listen-only, Input Monitoring granted)."
        case .needsPermission: "Input Monitoring is not granted yet."
        case .tapFailed: "Input Monitoring looks granted, but the key tap could not start. Quit and reopen the app."
        case .stopped: KeyTap.hasPermission ? "Input Monitoring is granted. Keycaps are off." : "Input Monitoring is not granted yet."
        }
    }

    // MARK: Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshStatusIcon()
        rebuildMenu()
    }

    private func refreshStatusIcon() {
        let name: String
        if !settings.enabled { name = "cursorarrow.slash" }
        else if overlay?.inkArmed == true { name = "pencil.tip" }
        else if overlay?.laserOn == true { name = "light.max" }
        else {
            statusItem?.button?.image = Skin.menuBarImage(theme: settings.theme)
            return
        }
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Cursor highlighter")
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        let s = settings

        menu.addItem(item("Overlays On", shortcut: .toggleOverlays, checked: s.enabled) { $0.store.settings.enabled.toggle() })
        menu.addItem(.separator())

        let themes = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for theme in Theme.offered {
            themeMenu.addItem(item(theme.title, checked: s.theme == theme) { $0.store.settings.theme = theme })
        }
        themes.submenu = themeMenu
        menu.addItem(themes)
        menu.addItem(.separator())

        menu.addItem(header("Cursor"))
        for mode in RingMode.allCases {
            let title = switch mode { case .always: "Ring: always"; case .clickOnly: "Ring: only while clicking"; case .off: "Ring: off" }
            menu.addItem(item(title, checked: s.ringMode == mode, indent: 1) { $0.store.settings.ringMode = mode })
        }
        menu.addItem(item("Click ripples", checked: s.ripplesEnabled, indent: 1) { $0.store.settings.ripplesEnabled.toggle() })
        menu.addItem(item("Laser pointer", shortcut: .toggleLaser, checked: overlay.laserOn, indent: 1) { $0.setLaser(!$0.overlay.laserOn) })

        menu.addItem(header("Draw"))
        menu.addItem(item(overlay.inkArmed ? "Drawing (Esc to stop)" : "Start drawing", shortcut: .toggleInk,
                          checked: overlay.inkArmed, indent: 1) { $0.setInk(!$0.overlay.inkArmed) })
        for (tool, sc) in [(InkTool.pen, AppShortcut.pen), (.arrow, .arrow), (.highlighter, .highlighter)] {
            menu.addItem(item(sc.title, shortcut: sc, checked: s.inkTool == tool, indent: 1) { $0.selectTool(tool) })
        }
        menu.addItem(item("Clear ink", shortcut: .clearInk, indent: 1) { $0.overlay.clearInk() })

        menu.addItem(header("Keycaps"))
        for mode in KeycapMode.allCases {
            let title = switch mode { case .shortcutsOnly: "Shortcuts only"; case .allKeys: "All keys"; case .off: "Off" }
            menu.addItem(item(title, checked: s.keycapMode == mode, indent: 1) { d in
                d.store.settings.keycapMode = mode
                if mode != .off && d.keyTap.state != .running { d.showOnboarding() }
            })
        }
        if s.keycapMode != .off && keyTap.state != .running {
            menu.addItem(item("Set up Input Monitoring…", indent: 1) { $0.showOnboarding() })
        }
        menu.addItem(item("Preview keycaps", indent: 1) { $0.keycaps.preview() })
        menu.addItem(item(keycaps.isPositioning ? "Done moving keycaps" : "Move keycaps…", indent: 1) { d in
            if d.keycaps.isPositioning { d.keycaps.endPositioning() } else { d.keycaps.beginPositioning() }
        })

        menu.addItem(.separator())
        menu.addItem(item("Screen sharing tips…") { $0.showSharingTips() })
        menu.addItem(item("Settings…", key: ",") { $0.showSettings() })
        menu.addItem(.separator())
        menu.addItem(item("Quit", key: "q") { _ in NSApp.terminate(nil) })
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func item(_ title: String, shortcut: AppShortcut? = nil, key: String = "", checked: Bool = false,
                      indent: Int = 0, action: @escaping (AppDelegate) -> Void) -> NSMenuItem {
        let i = ClosureMenuItem(title: title, keyEquivalent: key) { [weak self] in
            guard let self else { return }
            action(self)
            self.rebuildMenu()
        }
        if let shortcut, let ch = KeyNames.ansiCharacters[shortcut.stroke.keyCode] {
            // Shown for reference; the global hotkey does the work.
            i.keyEquivalent = ch
            i.keyEquivalentModifierMask = [.control, .option, .command]
        }
        i.state = checked ? .on : .off
        i.indentationLevel = indent
        return i
    }

    // MARK: Windows

    private func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            w.title = "Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        if let w = settingsWindow, let size = w.contentViewController?.view.fittingSize { w.setContentSize(size) }
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showSharingTips() {
        let alert = NSAlert()
        alert.messageText = "Make the highlights visible to your audience"
        alert.informativeText = """
        Zoom, Google Meet, Teams: share your entire screen ("Desktop", "Entire screen" or "Screen 1"), \
        not a single window or tab. A window share sends only that app's window, so the ring, ripples, \
        laser, ink and keycaps are not in it.

        Keynote and PowerPoint: play the slideshow on the screen you share. If the slideshow runs on a \
        second display, share that display.

        QuickTime and other recorders: record the entire screen; everything shows up in the recording.

        ⌃⌥⌘O turns every overlay off and on at once.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

extension Notification.Name {
    static let keycapStatusChanged = Notification.Name("keycapStatusChanged")
}
