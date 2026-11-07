import Foundation

public enum UnitSystem: String, CaseIterable, Sendable {
    case metric, imperial

    public func speed(_ metresPerSecond: Double) -> Int {
        Int((metresPerSecond * (self == .metric ? 3.6 : 2.236_94)).rounded())
    }

    public var speedUnitSpoken: String { self == .metric ? "kilometers per hour" : "miles per hour" }

    /// Distances rounded the way a co-driver would say them.
    public func distance(_ metres: Double) -> String {
        switch self {
        case .metric:
            if metres >= 1_000 {
                let km = (metres / 100).rounded() / 10
                return km == km.rounded() ? "\(Int(km)) kilometers" : String(format: "%.1f kilometers", km)
            }
            let rounded = metres >= 200 ? (metres / 50).rounded() * 50 : (metres / 10).rounded() * 10
            return "\(Int(rounded)) meters"
        case .imperial:
            let feet = metres * 3.280_84
            if feet >= 1_000 {
                let miles = (metres / 1_609.34 * 10).rounded() / 10
                return miles == 1 ? "1 mile" : String(format: "%.1f miles", miles)
            }
            return "\(Int((feet / 50).rounded() * 50)) feet"
        }
    }
}

/// Builds the sentences the game speaks. Kept here (not in the app) so it is unit-testable.
public struct Phrases {
    public var units: UnitSystem

    public init(units: UnitSystem) { self.units = units }

    public func curve(_ c: UpcomingCurve) -> String {
        let suggest = units.speed(c.advisorySpeed)
        var text = "\(c.severity.rawValue.capitalized) \(c.direction.rawValue) curve in \(units.distance(c.distance))"
        if c.severity != .gentle { text += ", slow to \(suggest)" }
        return text + "."
    }

    public func roadAhead(_ c: UpcomingCurve?) -> String {
        guard let c else { return "Straight road ahead." }
        return "Next: " + curve(c)
    }

    public func dashboard(_ d: DashboardReading) -> String {
        var parts: [String] = []
        parts.append("\(units.speed(d.speed)) \(units.speedUnitSpoken)")
        switch d.engine {
        case .off: parts.append("engine off")
        case .starting: parts.append("engine starting")
        case .running:
            parts.append("gear \(d.gear)")
            parts.append("\(Int((d.rpm / 50).rounded() * 50)) RPM")
        }
        parts.append("fuel \(Int((d.fuelFraction * 100).rounded())) percent")
        let temp = units == .metric ? "\(Int(d.engineTempC.rounded())) degrees" : "\(Int((d.engineTempC * 9 / 5 + 32).rounded())) degrees"
        parts.append("engine temperature \(temp)")
        if case let .on(side) = d.signal { parts.append("\(side.rawValue) signal on") }
        parts.append("limit \(units.speed(d.speedLimit))")
        return parts.joined(separator: ", ") + "."
    }

    public func signal(_ s: SignalState) -> String {
        switch s {
        case .off: return "Signal off."
        case let .on(side): return "\(side.rawValue.capitalized) signal."
        }
    }

    public func crash(_ reason: CrashReason) -> String {
        switch reason {
        case let .leftRoad(side):
            return "Crash! You ran off the \(side.rawValue) side of the road. Truck recovered to the lane."
        }
    }
}
