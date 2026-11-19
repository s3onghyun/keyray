import os

/// Unified-log channels. Read them with:
/// `log show --last 5m --predicate 'subsystem == "com.s3onghyun.keyray"' --info`
enum Log {
    static let subsystem = "com.s3onghyun.keyray"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let keys = Logger(subsystem: subsystem, category: "keys")
    /// Intervals for Instruments' Points of Interest track: pointer events (with how old the event
    /// was on arrival and once handled), laser frames, click effects and keycap renders.
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
