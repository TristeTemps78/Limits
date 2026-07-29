// swift-tools-version:5.9
import PackageDescription

// Platforms: iOS 17 is the real target, macOS 13 is deliberate (see AGENTS.md rule 4).
// `swift test` runs against macOS on the CI runner, which mechanically forbids any
// SwiftUI/WidgetKit import creeping into this package — LimitsCore stays UI-free.
let package = Package(
    name: "LimitsCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LimitsCore", targets: ["LimitsCore"])
    ],
    targets: [
        .target(name: "LimitsCore"),
        .testTarget(name: "LimitsCoreTests", dependencies: ["LimitsCore"])
    ]
)
