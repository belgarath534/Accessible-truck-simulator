import Foundation

/// An airport with one runway. Positions are metres east (x) and north (y) of the map's centre.
public struct Airport: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let x: Double
    public let y: Double
    /// The direction you take off and land on its main runway, degrees.
    public let runwayHeading: Double
    public let runwayLength: Double
    public static let runwayHalfWidth = 22.0

    /// "Runway 9" for heading 090.
    public var runwayName: String {
        let n = Int((runwayHeading / 10).rounded()) % 36
        return "runway \(n == 0 ? 36 : n)"
    }

    /// Where the runway starts (the threshold) and its direction as a unit vector.
    public var threshold: (x: Double, y: Double) {
        let r = runwayHeading * .pi / 180
        return (x - sin(r) * runwayLength / 2, y - cos(r) * runwayLength / 2)
    }

    /// A point in runway terms: `along` metres past the threshold, `across` metres right of the centreline.
    public func runwayCoordinates(x px: Double, y py: Double) -> (along: Double, across: Double) {
        let r = runwayHeading * .pi / 180
        let t = threshold
        let dx = px - t.x, dy = py - t.y
        return (dx * sin(r) + dy * cos(r), dx * cos(r) - dy * sin(r))
    }

    public func isOnRunway(x: Double, y: Double, margin: Double = 0) -> Bool {
        let c = runwayCoordinates(x: x, y: y)
        return c.along >= -margin && c.along <= runwayLength + margin && abs(c.across) <= Airport.runwayHalfWidth + margin
    }
}

public enum World {
    public static let airports: [Airport] = [
        Airport(id: "pine", name: "Pine Valley", x: 0, y: 0, runwayHeading: 90, runwayLength: 1_800),
        Airport(id: "harbor", name: "Harbor City", x: 26_000, y: 9_000, runwayHeading: 60, runwayLength: 2_400),
        Airport(id: "mesa", name: "Red Mesa", x: -18_000, y: -22_000, runwayHeading: 340, runwayLength: 2_000),
        Airport(id: "summit", name: "Summit Field", x: 6_000, y: 31_000, runwayHeading: 10, runwayLength: 1_600),
        Airport(id: "lakeside", name: "Lakeside", x: 38_000, y: -16_000, runwayHeading: 120, runwayLength: 2_200),
    ]

    public static func airport(_ id: String) -> Airport? { airports.first { $0.id == id } }

    /// Straight-line distance and bearing from a point to an airport.
    public static func distance(fromX x: Double, y: Double, to a: Airport) -> Double { hypot(a.x - x, a.y - y) }
    public static func bearing(fromX x: Double, y: Double, to a: Airport) -> Double {
        Units.heading(atan2(a.x - x, a.y - y) * 180 / .pi)
    }

    /// The airport whose runway this point is on, if any.
    public static func runway(atX x: Double, y: Double, margin: Double = 0) -> Airport? {
        airports.first { $0.isOnRunway(x: x, y: y, margin: margin) }
    }
}
