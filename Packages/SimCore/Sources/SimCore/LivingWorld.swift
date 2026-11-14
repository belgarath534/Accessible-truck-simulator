import Foundation

/// Time of day, from the player's own clock: night has less traffic and more deer.
public enum TimeOfDay: String, CaseIterable, Codable, Sendable {
    case dawn, day, dusk, night

    public init(hour: Int) {
        switch hour {
        case 5..<7: self = .dawn
        case 7..<18: self = .day
        case 18..<21: self = .dusk
        default: self = .night
        }
    }

    /// Seconds between deer, as a range.
    var deerInterval: ClosedRange<Double> {
        switch self {
        case .night: return 60...150
        case .dawn, .dusk: return 90...200
        case .day: return 180...400
        }
    }

    /// Traffic is lighter at night (spawn timers are multiplied by this).
    var trafficFactor: Double { self == .night ? 1.8 : (self == .day ? 1 : 1.2) }

    /// Said at the start of a drive (nothing for daytime).
    public var announcement: String? {
        switch self {
        case .night: return "It's night. The roads are quiet, but watch for deer."
        case .dawn: return "The sun is coming up. Deer are out at dawn."
        case .dusk: return "The sun is going down. Deer come out at dusk."
        case .day: return nil
        }
    }
}

/// A deer on the road.
public struct Deer: Equatable, Sendable {
    /// Metres along the road.
    public var position: Double
    /// When it wanders off by itself (session time, seconds).
    public var leavesAt: Double
    /// Honked at: it's running off.
    public var scared = false
}

public extension DrivingSession {
    /// Toll at each booth, dollars.
    static let tollCost = 5
    /// Fine for driving through a toll booth too fast to pay.
    static let tollFine = 75
    /// Fastest you can go through a toll booth and still pay, m/s.
    static let tollSpeed = 30 / 3.6
    /// Hitting a deer faster than this is a crash; slower, it just jumps away, m/s.
    static let deerSafeSpeed = 15 / 3.6
    /// How far ahead (metres) a weigh station is announced: about half a mile.
    static let weighStationWarning = 800.0
    /// Fine for driving past a weigh station without pulling in. Counts as a ticket.
    static let weighStationSkipFine = 200
    /// Fine at the scale for a heavy load on a truck that crashed this trip.
    static let unsafeLoadFine = 150
    /// Loads heavier than this (kg) are checked for crash damage at the scale.
    static let heavyLoadKg = 20_000.0
}

// MARK: - Rest stops (light): long stretches at the wheel make the driver tired; a truck stop fixes it.

public enum Rest {
    /// Driving time before the "getting tired" warning, seconds.
    public static let tiredAfter = 18.0 * 60
    /// After this the driver starts nodding off: small drifts now and then.
    public static let drowsyAfter = 28.0 * 60
    /// A nap only happens if you've been driving at least this long.
    public static let napWorthwhile = 8.0 * 60
    /// Paid with the next delivery after a nap.
    public static let bonus = 100
}

extension DrivingSession {
    func stepTiredness(dt: Double, events: inout [SimEvent]) {
        guard restEnabled else { return }
        if truck.speed > 1 { awakeTime += dt }
        if awakeTime >= Rest.tiredAfter && !warnedTired {
            warnedTired = true
            events.append(.gettingTired)
        }
        if awakeTime < Rest.tiredAfter { warnedTired = false }
        guard awakeTime >= Rest.drowsyAfter, truck.speed > 8 else { return }
        nextDrowsy -= dt
        if nextDrowsy <= 0 {
            nextDrowsy = Double.random(in: 45...80, using: &rng)
            // Eyes closing for a moment: the truck wanders toward the edge.
            truck.lateralVelocity += (Bool.random(using: &rng) ? 1 : -1) * 0.7
            events.append(.drowsy)
        }
    }
}
