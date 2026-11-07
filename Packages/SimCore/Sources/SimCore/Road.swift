import Foundation

public enum Side: String, Equatable, Sendable {
    case left, right
}

/// One piece of road. Curvature sign convention: positive bends to the RIGHT.
public struct RoadSegment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case straight
        case curve(direction: Side, radius: Double)
    }

    public var kind: Kind
    public var length: Double

    public init(_ kind: Kind, length: Double) {
        self.kind = kind
        self.length = length
    }

    public static func straight(_ length: Double) -> RoadSegment { .init(.straight, length: length) }
    public static func left(radius: Double, length: Double) -> RoadSegment { .init(.curve(direction: .left, radius: radius), length: length) }
    public static func right(radius: Double, length: Double) -> RoadSegment { .init(.curve(direction: .right, radius: radius), length: length) }

    /// Peak curvature of this segment (1/m, positive = right).
    public var peakCurvature: Double {
        switch kind {
        case .straight: return 0
        case let .curve(direction, radius): return (direction == .right ? 1 : -1) / radius
        }
    }
}

public enum CurveSeverity: String, Equatable, Sendable {
    case gentle, moderate, sharp

    public init(radius: Double) {
        switch radius {
        case ..<250: self = .sharp
        case ..<700: self = .moderate
        default: self = .gentle
        }
    }
}

/// A curve the driver is approaching.
public struct UpcomingCurve: Equatable, Sendable {
    public var segmentIndex: Int
    public var direction: Side
    public var radius: Double
    public var severity: CurveSeverity
    /// Metres from the truck to the start of the curve.
    public var distance: Double
    /// A comfortable speed through the curve, m/s.
    public var advisorySpeed: Double
}

/// A single road made of segments. Positions are measured in metres along the road.
/// Curvature ramps in and out over `transitionLength` so curves build gradually, like real roads.
public struct Road: Sendable {
    public var segments: [RoadSegment]
    public var loops: Bool
    public var laneWidth: Double = 3.7
    public var speedLimit: Double // m/s
    public var transitionLength: Double = 40

    /// Comfortable lateral acceleration used to compute advisory speeds, m/s².
    public static let comfortLatAccel = 1.8

    private var starts: [Double]
    public let totalLength: Double

    /// Positions (metres along the road) of truck stops with fuel pumps.
    public var truckStops: [Double] = []
    /// Stretches with their own speed limit (towns).
    public var speedZones: [SpeedZone] = []
    /// Spots where a police car may be parked, watching for speeders (metres along the road).
    public var policeSpots: [Double] = []

    public init(segments: [RoadSegment], loops: Bool = true, speedLimit: Double = 80 / 3.6,
                truckStops: [Double] = []) {
        self.segments = segments
        self.loops = loops
        self.speedLimit = speedLimit
        self.truckStops = truckStops.sorted()
        var s = 0.0
        var starts: [Double] = []
        for seg in segments {
            starts.append(s)
            s += seg.length
        }
        self.starts = starts
        self.totalLength = s
    }

    /// Wraps a distance onto the road (for looping roads).
    public func normalized(_ s: Double) -> Double {
        guard loops, totalLength > 0 else { return min(max(s, 0), totalLength) }
        let r = s.truncatingRemainder(dividingBy: totalLength)
        return r < 0 ? r + totalLength : r
    }

    public func segmentIndex(at s: Double) -> Int {
        let s = normalized(s)
        var lo = 0, hi = segments.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= s { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    public func start(ofSegment i: Int) -> Double { starts[i] }

    /// Road curvature at a position (1/m, positive = bends right).
    public func curvature(at position: Double) -> Double {
        guard !segments.isEmpty else { return 0 }
        let s = normalized(position)
        let i = segmentIndex(at: s)
        let seg = segments[i]
        let k = seg.peakCurvature
        guard k != 0 else { return 0 }
        let into = s - starts[i]
        let remaining = seg.length - into
        let ramp = min(transitionLength, seg.length / 2)
        let factor = min(1, min(into, remaining) / ramp)
        return k * factor
    }

    /// The next curve starting within `lookahead` metres of `position`, if any.
    /// A curve the truck is already inside is not returned.
    /// The next truck stop ahead: its index and the distance to it (metres). Wraps on looping roads.
    public func nextTruckStop(after position: Double) -> (index: Int, distance: Double)? {
        guard !truckStops.isEmpty else { return nil }
        let s = normalized(position)
        if let i = truckStops.firstIndex(where: { $0 >= s }) { return (i, truckStops[i] - s) }
        guard loops else { return nil }
        return (0, truckStops[0] + totalLength - s)
    }

    /// Puts truck stops in the middle of the given straight segments.
    func withTruckStops(onSegments indices: [Int]) -> Road {
        var r = self
        r.truckStops = indices.map { starts[$0] + segments[$0].length / 2 }.sorted()
        return r
    }

    public func nextCurve(after position: Double, within lookahead: Double) -> UpcomingCurve? {
        guard !segments.isEmpty else { return nil }
        let s = normalized(position)
        let current = segmentIndex(at: s)
        var distance = starts[current] + segments[current].length - s
        var i = current
        for _ in 0..<segments.count {
            i += 1
            if i >= segments.count {
                guard loops else { return nil }
                i = 0
            }
            if distance > lookahead { return nil }
            let seg = segments[i]
            if case let .curve(direction, radius) = seg.kind {
                return UpcomingCurve(
                    segmentIndex: i, direction: direction, radius: radius,
                    severity: CurveSeverity(radius: radius), distance: distance,
                    advisorySpeed: min(speedLimit, (Road.comfortLatAccel * radius).squareRoot())
                )
            }
            distance += seg.length
        }
        return nil
    }
}

public extension Road {
    /// A ~12 km country loop for the prototype: long straights to get up to speed,
    /// then a mix of gentle, moderate and sharp curves in both directions.
    static let practiceLoop = Road(segments: [
        .straight(800),
        .right(radius: 900, length: 400),
        .straight(600),
        .left(radius: 500, length: 350),
        .straight(400),
        .right(radius: 350, length: 300),
        .straight(700),
        .left(radius: 1_200, length: 500),
        .straight(300),
        .left(radius: 220, length: 250),
        .straight(250),
        .right(radius: 220, length: 250),
        .straight(900),
        .right(radius: 600, length: 450),
        .straight(500),
        .left(radius: 400, length: 400),
        .straight(600),
        .right(radius: 160, length: 220),
        .straight(1_000),
        .left(radius: 800, length: 600),
        .straight(1_200),
    ])
        .withTruckStops(onSegments: [6, 12, 20])
}
