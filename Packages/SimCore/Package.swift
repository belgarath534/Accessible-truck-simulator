// swift-tools-version:5.9
import PackageDescription

// SimCore: the platform-independent driving simulation.
// No UIKit / AVFoundation imports allowed here, so it can be unit-tested anywhere (including Linux CI).
let package = Package(
    name: "SimCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SimCore", targets: ["SimCore"]),
    ],
    targets: [
        .target(name: "SimCore"),
        .testTarget(name: "SimCoreTests", dependencies: ["SimCore"]),
    ]
)
