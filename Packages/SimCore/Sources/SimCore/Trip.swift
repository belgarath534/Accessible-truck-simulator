import Foundation

/// What a drive is for.
public enum TripGoal: Equatable, Sendable {
    /// Drive as long as you like; there's no destination.
    case freeDrive
    /// Drive `distance` metres and stop at the drop-off.
    case destination(name: String, distance: Double)

    public var name: String {
        switch self {
        case .freeDrive: return "Free Drive"
        case let .destination(name, _): return name
        }
    }

    public var distance: Double? {
        if case let .destination(_, d) = self { return d }
        return nil
    }

    /// One lap of a road, ending where it started.
    public static func practice(on road: Road) -> TripGoal {
        .destination(name: "Practice Drive", distance: road.totalLength)
    }
}

/// Running totals for the current drive.
public struct TripStats: Equatable, Sendable {
    /// Seconds since the truck first started moving.
    public var drivingTime: Double = 0
    public var distance: Double = 0
    public var crashes = 0
    public var topSpeed: Double = 0
    public var tooFastWarnings = 0
    public var fuelUsedLiters: Double = 0
    /// Money spent during the drive: fuel at truck stops and tows.
    public var fuelBoughtLiters: Double = 0
    public var fuelCost: Int = 0
    public var tows: Int = 0
    public var towCost: Int = 0

    public init() {}

    public var averageSpeed: Double { drivingTime > 0 ? distance / drivingTime : 0 }
}

/// The result of a finished trip.
public struct TripSummary: Equatable, Sendable {
    public var goalName: String
    public var stats: TripStats
    /// Metres between where the truck stopped and the drop-off; positive means it stopped past it.
    public var stopError: Double

    public init(goalName: String, stats: TripStats, stopError: Double) {
        self.goalName = goalName
        self.stats = stats
        self.stopError = stopError
    }

    public enum StopRating: String, Sendable { case perfect, good, overshot }

    public var stopRating: StopRating {
        if abs(stopError) <= 15 { return .perfect }
        if stopError <= DrivingSession.arrivalTolerance { return .good }
        return .overshot
    }
}
