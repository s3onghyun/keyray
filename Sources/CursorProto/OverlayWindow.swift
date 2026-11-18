import AppKit

extension NSWindow.Level {
    /// Above full-screen apps, slideshows and the menu bar.
    static let overlay = NSWindow.Level.screenSaver
}

/// A transparent, click-through panel covering one display, on every Space and over full-screen apps.
/// It never becomes key or main, so showing it or drawing on it never steals focus.
final class OverlayWindow: NSPanel {
    let displayID: CGDirectDisplayID
    let root = CALayer()

    init(screen: NSScreen) {
        displayID = screen.displayID
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configureAsOverlay(self)
        setFrame(screen.frame, display: false)

        // Layer-hosting (layer set before wantsLayer): AppKit leaves the layer tree alone, so moving
        // the ring is a bare Core Animation commit without an AppKit display pass.
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.layer = root
        view.wantsLayer = true
        root.masksToBounds = false
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Converts a global point (`NSEvent.mouseLocation`, bottom-left origin) to this window's layer space.
    func local(_ global: NSPoint) -> CGPoint {
        CGPoint(x: global.x - frame.minX, y: global.y - frame.minY)
    }
}

/// Shared window setup for the overlays and the keycap HUD.
@MainActor
func configureAsOverlay(_ window: NSWindow) {
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.level = .overlay
    window.ignoresMouseEvents = true
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    // Included in screen sharing and recordings of the whole display.
    window.sharingType = .readOnly
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    if let panel = window as? NSPanel {
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
