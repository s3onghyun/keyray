import os

/// Unified-log channels. Read them with:
/// `log show --last 5m --predicate 'subsystem == "com.s3onghyun.cursor-proto"' --info`
enum Log {
    static let subsystem = "com.s3onghyun.cursor-proto"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let keys = Logger(subsystem: subsystem, category: "keys")
}
