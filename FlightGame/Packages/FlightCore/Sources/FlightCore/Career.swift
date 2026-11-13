import Foundation

/// A small, stable random number generator, so job boards can be tested.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public enum PilotRank: Int, Codable, CaseIterable, Comparable, Sendable {
    case student, privatePilot, commercial, captain

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var title: String { ["Student Pilot", "Private Pilot", "Commercial Pilot", "Captain"][rawValue] }
    /// Paid flights needed.
    public var flightsNeeded: Int { [0, 3, 8, 20][rawValue] }
    public var next: PilotRank? { PilotRank(rawValue: rawValue + 1) }

    public static func forFlights(_ n: Int) -> PilotRank { allCases.last { n >= $0.flightsNeeded } ?? .student }
}

public enum JobKind: String, Codable, CaseIterable, Sendable {
    case mail, cargo, passengers, medical, vip

    public var rank: PilotRank {
        switch self {
        case .mail, .cargo: return .student
        case .passengers: return .privatePilot
        case .medical: return .commercial
        case .vip: return .captain
        }
    }

    /// Dollars per nautical mile.
    var rate: Double {
        switch self {
        case .mail: return 28
        case .cargo: return 34
        case .passengers: return 42
        case .medical: return 60
        case .vip: return 85
        }
    }

    public var carriesPeople: Bool { self == .passengers || self == .vip }

    var loads: [String] {
        switch self {
        case .mail: return ["Sacks of mail", "Parcels", "Newspapers"]
        case .cargo: return ["Machine parts", "Crates of fruit", "Fishing gear", "Camping supplies"]
        case .passengers: return ["Two hikers", "A family of three", "A photographer and her assistant", "Three tourists"]
        case .medical: return ["Medicine for the clinic", "Blood supplies", "A doctor on call"]
        case .vip: return ["A film star", "The governor", "A famous chef"]
        }
    }
}

public struct FlightJob: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: JobKind
    public var load: String
    public var from: String
    public var to: String
    /// Metres.
    public var distance: Double
    public var pay: Int

    public var fromName: String { World.airport(from)?.name ?? from }
    public var toName: String { World.airport(to)?.name ?? to }

    /// "A family of three to Harbor City, 15 miles, pays $620."
    public var summary: String {
        "\(load) to \(toName), \(Units.distance(distance)), pays \(Phrases.money(pay))."
    }
}

/// What a flight earned, line by line.
public struct FlightPay: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let label: String
        public let amount: Int
    }
    public var lines: [Line] = []
    public var news: [String] = []
    public var total: Int { lines.reduce(0) { $0 + $1.amount } }

    public var spoken: String {
        var parts = lines.map { "\($0.label): \(Phrases.money($0.amount))." }
        if lines.count > 1 { parts.append("Total: \(Phrases.money(total)).") }
        return (parts + news).joined(separator: " ")
    }
}

/// The pilot's career: money, rank, where the plane is, the job board, and the plane's condition.
public struct PilotCareer: Codable, Equatable, Sendable {
    public var money = 500
    public var flightsDone = 0
    public var totalEarned = 0
    public var location = World.airports[0].id
    public var board: [FlightJob] = []
    /// The plane's condition, 0...1. Flying wears it a little; firm and hard landings and crashes wear it a lot.
    public var condition = 1.0
    public var bestComfort = 0

    public init() {}

    public static let boardSize = 3
    /// Below this the mechanic won't let you fly paid jobs.
    public static let unsafeCondition = 0.3
    public static let fullRepairCost = 3_000.0

    public var rank: PilotRank { PilotRank.forFlights(flightsDone) }
    public var locationName: String { World.airport(location)?.name ?? location }
    public var conditionPercent: Int { Int((condition * 100).rounded()) }
    public var canFlyJobs: Bool { condition >= Self.unsafeCondition }

    /// A worn engine loses power: full power above 70 percent condition, down to 80 percent power when worn out.
    public var powerFactor: Double { condition >= 0.7 ? 1 : 0.8 + 0.2 * (condition / 0.7) }

    public var repairCost: Int { Int((Self.fullRepairCost * (1 - condition) / 10).rounded()) * 10 }

    public var mechanicReport: String {
        switch condition {
        case 0.9...: return "The plane is in great shape."
        case 0.7..<0.9: return "A little worn, but flying fine."
        case Self.unsafeCondition..<0.7: return "The engine is tired and making less power. Takeoffs will be longer. Time for a repair."
        default: return "The plane isn't safe for paid flights. It needs a repair first."
        }
    }

    public mutating func refreshBoard<R: RandomNumberGenerator>(using rng: inout R) {
        let kinds = JobKind.allCases.filter { $0.rank <= rank }
        let destinations = World.airports.filter { $0.id != location }.shuffled(using: &rng)
        guard let here = World.airport(location) else { return }
        board = destinations.prefix(Self.boardSize).map { dest in
            // The best kind you're allowed is more likely, so a new rank feels different.
            let kind = Double.random(in: 0...1, using: &rng) < 0.4 ? kinds.last! : kinds.randomElement(using: &rng)!
            let distance = World.distance(fromX: here.x, y: here.y, to: dest)
            let pay = Int((distance / 1_852 * kind.rate / 10).rounded()) * 10
            return FlightJob(id: UUID(), kind: kind, load: kind.loads.randomElement(using: &rng)!, from: location,
                             to: dest.id, distance: distance, pay: pay)
        }
    }

    public mutating func refreshBoard() {
        var rng = SystemRandomNumberGenerator()
        refreshBoard(using: &rng)
    }

    /// Wear from any flight (jobs, lessons, free flights).
    public mutating func wear(_ s: FlightSummary) {
        var loss = 0.01
        if s.crash != nil { loss += 0.4 }
        else if s.landing == .hard { loss += 0.08 }
        else if s.landing == .firm { loss += 0.03 }
        condition = max(0, condition - loss)
    }

    /// Settles a job flight. Pays only for landing at the destination.
    public mutating func finish<R: RandomNumberGenerator>(_ job: FlightJob, summary s: FlightSummary, comfort: Int,
                                                          using rng: inout R) -> FlightPay {
        var pay = FlightPay()
        let rankBefore = rank
        wear(s)
        if s.crash != nil {
            pay.news.append("No pay for a crashed flight, and the plane took damage. See the mechanic.")
        } else if s.landedAt != job.to {
            if let at = s.landedAt { location = at }
            pay.news.append("That wasn't \(job.toName), so the job doesn't pay.")
        } else {
            location = job.to
            pay.lines.append(.init(label: job.kind.carriesPeople ? "Fare" : "Delivery", amount: job.pay))
            if s.landing == .butter { pay.lines.append(.init(label: "Butter landing bonus", amount: job.pay / 5)) }
            else if s.landing == .smooth { pay.lines.append(.init(label: "Smooth landing bonus", amount: job.pay / 10)) }
            if job.kind.carriesPeople {
                bestComfort = max(bestComfort, comfort)
                if comfort >= 90 {
                    pay.lines.append(.init(label: "Tips from happy passengers", amount: job.pay * (job.kind == .vip ? 30 : 15) / 100))
                    pay.news.append("Comfort \(comfort) out of 100. Your passengers loved the flight.")
                } else if comfort >= 60 {
                    pay.news.append("Comfort \(comfort) out of 100. A decent ride.")
                } else {
                    pay.lines.append(.init(label: "Refund for a rough ride", amount: -job.pay / 4))
                    pay.news.append("Comfort \(comfort) out of 100. Your passengers did not enjoy that.")
                }
            }
            flightsDone += 1
            totalEarned += max(0, pay.total)
            if rank > rankBefore {
                pay.news.append("Promoted! You're now a \(rank.title).")
            } else if let next = rank.next {
                let left = next.flightsNeeded - flightsDone
                pay.news.append("\(left) more paid flight\(left == 1 ? "" : "s") to \(next.title).")
            }
        }
        money += pay.total
        if !canFlyJobs { pay.news.append(mechanicReport) }
        refreshBoard(using: &rng)
        return pay
    }

    /// Pays the mechanic for a full repair. Returns false if you can't afford it.
    public mutating func repair() -> Bool {
        let cost = repairCost
        guard cost > 0, money >= cost else { return false }
        money -= cost
        condition = 1
        return true
    }

    /// Broke and grounded: the mechanic patches the plane up just enough, on the house.
    public mutating func emergencyRepairIfStuck() -> Bool {
        guard !canFlyJobs, money < repairCost else { return false }
        condition = 0.5
        return true
    }
}
