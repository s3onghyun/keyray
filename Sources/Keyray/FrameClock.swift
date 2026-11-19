import AppKit

/// Calls `onFrame` once per refresh of the display a view is on (60 or 120 Hz), in step with the
/// screen instead of a free-running timer, and costs nothing while stopped.
@MainActor
final class FrameClock: NSObject {
    private var link: CADisplayLink?
    private weak var view: NSView?
    private let onFrame: (CADisplayLink) -> Void

    init(onFrame: @escaping (CADisplayLink) -> Void) {
        self.onFrame = onFrame
    }

    /// Runs the clock for `view`'s display, moving it there if it was following another view.
    func start(on view: NSView) {
        if self.view !== view {
            link?.invalidate()
            let link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
            self.view = view
        }
        // Only on a change: setting isPaused on a running link restarts its schedule, and doing
        // that every frame makes it skip every other frame.
        if link?.isPaused == true { link?.isPaused = false }
    }

    func stop() {
        if link?.isPaused == false { link?.isPaused = true }
    }

    var isRunning: Bool { link.map { !$0.isPaused } ?? false }

    @objc private func tick(_ link: CADisplayLink) {
        onFrame(link)
    }
}
