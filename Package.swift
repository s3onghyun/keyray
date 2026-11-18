// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keyray",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Keyray", targets: ["Keyray"])],
    targets: [
        // Pure logic (settings, timing, keycap formatting, geometry) with no AppKit, so it is unit-testable.
        .target(name: "KeyrayCore"),
        .executableTarget(name: "Keyray", dependencies: ["KeyrayCore"]),
        .testTarget(name: "KeyrayCoreTests", dependencies: ["KeyrayCore"]),
    ]
)
