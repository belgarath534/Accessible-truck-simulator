import Foundation

// MARK: - Cargo and jobs

/// Something to haul. Heavier cargo makes the truck slower to speed up and stop;
/// fragile cargo is damaged more by crashes.
public struct Cargo: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var massKg: Double
    /// Dollars per kilometre.
    public var ratePerKm: Double
    public var fragile: Bool
    /// Urgent loads (like frozen food) get tighter deadlines and pay more.
    public var urgent: Bool

    public init(name: String, massKg: Double, ratePerKm: Double, fragile: Bool = false, urgent: Bool = false) {
        self.name = name
        self.massKg = massKg
        self.ratePerKm = ratePerKm
        self.fragile = fragile
        self.urgent = urgent
    }

    public static let catalog: [Cargo] = [
        Cargo(name: "Furniture", massKg: 6_000, ratePerKm: 110),
        Cargo(name: "Frozen food", massKg: 14_000, ratePerKm: 145, urgent: true),
        Cargo(name: "Steel beams", massKg: 24_000, ratePerKm: 170),
        Cargo(name: "Electronics", massKg: 5_000, ratePerKm: 150, fragile: true),
        Cargo(name: "Lumber", massKg: 18_000, ratePerKm: 130),
        Cargo(name: "Glassware", massKg: 4_000, ratePerKm: 160, fragile: true),
        Cargo(name: "Gravel", massKg: 25_000, ratePerKm: 120),
        Cargo(name: "Medical supplies", massKg: 3_000, ratePerKm: 165, fragile: true, urgent: true),
        Cargo(name: "Canned goods", massKg: 12_000, ratePerKm: 115),
        Cargo(name: "Fresh produce", massKg: 10_000, ratePerKm: 140, urgent: true),
    ]
}

/// A delivery offered on the job board.
public struct DeliveryJob: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var cargo: Cargo
    /// Metres to drive.
    public var distance: Double
    /// Dollars paid for a clean, on-time delivery (before bonuses).
    public var pay: Int
    /// Seconds allowed.
    public var timeLimit: Double

    public init(id: UUID = UUID(), cargo: Cargo, distance: Double, pay: Int, timeLimit: Double) {
        self.id = id
        self.cargo = cargo
        self.distance = distance
        self.pay = pay
        self.timeLimit = timeLimit
    }

    public var goal: TripGoal { .destination(name: "\(cargo.name) delivery", distance: distance) }
}

/// Small deterministic random generator, so the job board can be tested and reproduced.
public struct SeededRandom: RandomNumberGenerator {
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

public enum JobBoard {
    public static let size = 3
    /// Average speed a fair deadline assumes, m/s (about 50 km/h including curves).
    static let fairSpeed = 50 / 3.6

    public static func makeJob<R: RandomNumberGenerator>(using rng: inout R) -> DeliveryJob {
        let cargo = Cargo.catalog.randomElement(using: &rng)!
        let distance = (Double(Int.random(in: 8...40, using: &rng)) * 500) // 4 km to 20 km
        let pay = Int((distance / 1_000 * cargo.ratePerKm / 10).rounded()) * 10
        let slack = cargo.urgent ? 1.35 : 1.7
        let timeLimit = ((distance / fairSpeed * slack + 120) / 60).rounded(.up) * 60
        return DeliveryJob(cargo: cargo, distance: distance, pay: pay, timeLimit: timeLimit)
    }

    public static func makeBoard<R: RandomNumberGenerator>(using rng: inout R) -> [DeliveryJob] {
        var jobs: [DeliveryJob] = []
        while jobs.count < size {
            let job = makeJob(using: &rng)
            // Keep the board varied: no two jobs with the same cargo.
            if !jobs.contains(where: { $0.cargo == job.cargo }) { jobs.append(job) }
        }
        return jobs
    }
}

// MARK: - Pay

/// What a drive earned, line by line, so it can be read out and shown.
public struct Payout: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var label: String
        public var amount: Int
    }

    public var lines: [Line]
    public var total: Int { max(0, lines.reduce(0) { $0 + $1.amount }) }

    /// Free Drive pays a small amount per kilometre: steady but slow money.
    public static let freeDriveRatePerKm = 35.0
    /// Each crash costs this much in repairs.
    public static let repairCost = 150

    public static func freeDrive(_ stats: TripStats) -> Payout {
        var lines = [Line(label: "Driving pay", amount: Int((stats.distance / 1_000 * freeDriveRatePerKm).rounded()))]
        if stats.crashes > 0 {
            lines.append(Line(label: "Repairs for \(stats.crashes) crash\(stats.crashes == 1 ? "" : "es")",
                              amount: -repairCost * stats.crashes))
        }
        return Payout(lines: lines)
    }

    public static func delivery(_ job: DeliveryJob, summary: TripSummary) -> Payout {
        let base = job.pay
        var lines = [Line(label: "Delivery pay", amount: base)]
        let stats = summary.stats

        let late = stats.drivingTime - job.timeLimit
        if late > 0 {
            let minutes = Int((late / 60).rounded(.up))
            let fraction = min(0.5, Double(minutes) * 0.03)
            lines.append(Line(label: "Late by \(minutes) minute\(minutes == 1 ? "" : "s")",
                              amount: -Int((Double(base) * fraction).rounded())))
        } else {
            lines.append(Line(label: "On-time bonus", amount: Int((Double(base) * 0.10).rounded())))
        }

        if stats.crashes > 0 {
            let perCrash = job.cargo.fragile ? 0.20 : 0.10
            let fraction = min(0.6, Double(stats.crashes) * perCrash)
            lines.append(Line(label: "Cargo damage from \(stats.crashes) crash\(stats.crashes == 1 ? "" : "es")",
                              amount: -Int((Double(base) * fraction).rounded())))
        } else {
            lines.append(Line(label: "No-crash bonus", amount: Int((Double(base) * 0.10).rounded())))
        }

        if summary.stopRating == .perfect {
            lines.append(Line(label: "Perfect stop bonus", amount: Int((Double(base) * 0.05).rounded())))
        }
        return Payout(lines: lines)
    }
}

// MARK: - Career

/// Everything saved between sessions.
public struct CareerState: Codable, Equatable, Sendable {
    public var money: Int
    public var jobsCompleted: Int
    public var kilometersDriven: Double
    public var totalEarned: Int
    public var jobBoard: [DeliveryJob]
    public var seed: UInt64
    /// Garage: ids of trucks the player owns, and the one they drive.
    public var ownedTrucks: [String]
    public var selectedTruck: String
    /// Upgrade levels per truck id.
    public var upgrades: [String: UpgradeLevels]

    public static let startingMoney = 500

    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        money = CareerState.startingMoney
        jobsCompleted = 0
        kilometersDriven = 0
        totalEarned = 0
        self.seed = seed
        var rng = SeededRandom(seed: seed)
        jobBoard = JobBoard.makeBoard(using: &rng)
        ownedTrucks = [TruckSpec.starter.id]
        selectedTruck = TruckSpec.starter.id
        upgrades = [:]
    }

    // Saves from before the garage existed have no truck fields: give them the starter truck.
    enum CodingKeys: String, CodingKey {
        case money, jobsCompleted, kilometersDriven, totalEarned, jobBoard, seed, ownedTrucks, selectedTruck, upgrades
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        money = try c.decode(Int.self, forKey: .money)
        jobsCompleted = try c.decode(Int.self, forKey: .jobsCompleted)
        kilometersDriven = try c.decode(Double.self, forKey: .kilometersDriven)
        totalEarned = try c.decode(Int.self, forKey: .totalEarned)
        jobBoard = try c.decode([DeliveryJob].self, forKey: .jobBoard)
        seed = try c.decode(UInt64.self, forKey: .seed)
        ownedTrucks = try c.decodeIfPresent([String].self, forKey: .ownedTrucks) ?? [TruckSpec.starter.id]
        selectedTruck = try c.decodeIfPresent(String.self, forKey: .selectedTruck) ?? TruckSpec.starter.id
        upgrades = try c.decodeIfPresent([String: UpgradeLevels].self, forKey: .upgrades) ?? [:]
    }

    /// The truck being driven, with its upgrades.
    public var truck: TruckSpec { TruckSpec.withID(selectedTruck).upgraded(upgradeLevels(for: TruckSpec.withID(selectedTruck))) }

    public func upgradeLevels(for truck: TruckSpec) -> UpgradeLevels { upgrades[truck.id] ?? UpgradeLevels() }

    public enum UpgradeResult: Equatable, Sendable { case upgraded(level: Int), maxed, notOwned, notEnoughMoney(short: Int) }

    /// Buys the next level of an upgrade for a truck the player owns.
    @discardableResult
    public mutating func buyUpgrade(_ kind: UpgradeKind, for truck: TruckSpec) -> UpgradeResult {
        guard owns(truck) else { return .notOwned }
        var levels = upgradeLevels(for: truck)
        guard let price = kind.price(after: levels[kind]) else { return .maxed }
        guard money >= price else { return .notEnoughMoney(short: price - money) }
        money -= price
        levels[kind] += 1
        upgrades[truck.id] = levels
        return .upgraded(level: levels[kind])
    }

    public func owns(_ truck: TruckSpec) -> Bool { ownedTrucks.contains(truck.id) }

    public enum PurchaseResult: Equatable, Sendable { case bought, alreadyOwned, notEnoughMoney(short: Int) }

    /// Buys a truck (and starts driving it).
    @discardableResult
    public mutating func buy(_ truck: TruckSpec) -> PurchaseResult {
        if owns(truck) { return .alreadyOwned }
        guard money >= truck.price else { return .notEnoughMoney(short: truck.price - money) }
        money -= truck.price
        ownedTrucks.append(truck.id)
        selectedTruck = truck.id
        return .bought
    }

    /// Picks an owned truck to drive. Returns false if it isn't owned.
    @discardableResult
    public mutating func select(_ truck: TruckSpec) -> Bool {
        guard owns(truck) else { return false }
        selectedTruck = truck.id
        return true
    }

    /// Adds a drive's earnings and distance.
    public mutating func record(_ payout: Payout, distance: Double) {
        money += payout.total
        totalEarned += payout.total
        kilometersDriven += distance / 1_000
    }

    /// Removes a finished job and puts a new one on the board.
    public mutating func completeJob(_ job: DeliveryJob) {
        jobsCompleted += 1
        replaceJob(job)
    }

    public mutating func replaceJob(_ job: DeliveryJob) {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        var rng = SeededRandom(seed: seed)
        guard let index = jobBoard.firstIndex(where: { $0.id == job.id }) else { return }
        var fresh = JobBoard.makeJob(using: &rng)
        var tries = 0
        while jobBoard.contains(where: { $0.cargo == fresh.cargo }) && tries < 20 {
            fresh = JobBoard.makeJob(using: &rng)
            tries += 1
        }
        jobBoard[index] = fresh
    }

    /// A whole new set of jobs.
    public mutating func refreshBoard() {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        var rng = SeededRandom(seed: seed)
        jobBoard = JobBoard.makeBoard(using: &rng)
    }
}
