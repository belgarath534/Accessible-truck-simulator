import Foundation

/// A plane's numbers. Speeds in m/s.
public struct AircraftSpec: Equatable, Sendable {
    public let name: String
    /// Stall speed with flaps up.
    public let stallSpeed: Double
    /// Lift the nose off the runway from here.
    public let rotateSpeed: Double
    public let cruiseSpeed: Double
    /// Never exceed.
    public let maxSpeed: Double
    /// Forward acceleration at full throttle and no drag, m/s².
    public let thrust: Double
    public let idleRPM: Double
    public let maxRPM: Double

    /// A friendly single-engine trainer, like the ones real pilots learn on.
    public static let trainer = AircraftSpec(name: "Bluebird trainer", stallSpeed: 25, rotateSpeed: 28,
                                             cruiseSpeed: 55, maxSpeed: 82, thrust: 3.2,
                                             idleRPM: 700, maxRPM: 2_600)

    /// Stall speed with flaps: each notch lowers it.
    public func stallSpeed(flaps: Int) -> Double { stallSpeed * [1.0, 0.92, 0.85][max(0, min(2, flaps))] }

    /// Drag constant so full throttle in level flight tops out a bit above cruise.
    var dragK: Double { thrust / pow(cruiseSpeed * 1.15, 2) }
}
