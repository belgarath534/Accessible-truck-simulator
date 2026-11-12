// swift-tools-version:5.9
import PackageDescription

// FlightCore: the flight model, airports, navigation, lessons and gestures for Accessible Flight Simulator.
// No UIKit / AVFoundation here, so it can be tested anywhere (including Linux CI).
let package = Package(
    name: "FlightCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FlightCore", targets: ["FlightCore"]),
    ],
    targets: [
        .target(name: "FlightCore"),
        .testTarget(name: "FlightCoreTests", dependencies: ["FlightCore"]),
    ]
)
