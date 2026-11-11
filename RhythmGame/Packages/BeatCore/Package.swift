// swift-tools-version:5.9
import PackageDescription

// BeatCore: songs, charts, timing and sound synthesis for Beat by Ear.
// No UIKit / AVFoundation here, so it can be tested anywhere (including Linux CI).
let package = Package(
    name: "BeatCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BeatCore", targets: ["BeatCore"]),
    ],
    targets: [
        .target(name: "BeatCore"),
        .testTarget(name: "BeatCoreTests", dependencies: ["BeatCore"]),
    ]
)
