// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CursorProto",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CursorProto", targets: ["CursorProto"])],
    targets: [
        // Pure logic (settings, timing, keycap formatting, geometry) with no AppKit, so it is unit-testable.
        .target(name: "CursorProtoCore"),
        .executableTarget(name: "CursorProto", dependencies: ["CursorProtoCore"]),
        .testTarget(name: "CursorProtoCoreTests", dependencies: ["CursorProtoCore"]),
    ]
)
