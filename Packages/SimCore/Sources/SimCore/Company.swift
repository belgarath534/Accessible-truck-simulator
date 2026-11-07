import Foundation

/// A hired driver who runs deliveries in one of your trucks, even while the game is closed.
public struct Driver: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// 1 to 3 stars.
    public var skill: Int
    /// The truck they drive (truck id), or nil if they're waiting for one.
    public var truckID: String?
    /// When their work was last counted.
    public var lastUpdate: Date
    /// Seconds into the current job.
    public var progress: Double
    public var jobsDone: Int
    public var earned: Int

    public init(id: UUID = UUID(), name: String, skill: Int, truckID: String? = nil, lastUpdate: Date = Date(),
                progress: Double = 0, jobsDone: Int = 0, earned: Int = 0) {
        self.id = id
        self.name = name
        self.skill = min(3, max(1, skill))
        self.truckID = truckID
        self.lastUpdate = lastUpdate
        self.progress = progress
        self.jobsDone = jobsDone
        self.earned = earned
    }

    /// Fee to hire.
    public var hireFee: Int { [1_500, 4_000, 9_000][skill - 1] }
    /// Minutes per delivery (better drivers are quicker).
    public var minutesPerJob: Double { [30, 25, 20][skill - 1] }
    /// Your company's take from each delivery, after the driver's wages.
    public var payPerJob: Int { [300, 375, 430][skill - 1] }
    /// Roughly what they bring in per hour.
    public var hourlyEarnings: Int { Int((Double(payPerJob) * 60 / minutesPerJob).rounded()) }

    public var stars: String { "\(skill) star\(skill == 1 ? "" : "s")" }
}

/// What a driver did since you last checked.
public struct DriverReport: Equatable, Sendable {
    public var name: String
    public var jobs: Int
    public var earned: Int
}

public enum Company {
    /// Work done while away is counted for at most this long (seconds) at a time.
    public static let maxAwaySeconds = 8 * 3_600.0

    static let firstNames = ["Sam", "Maria", "Dale", "Priya", "Luis", "Tamika", "Gus", "Wendy", "Ray", "Keiko",
                             "Hank", "Rosa", "Earl", "Nadia", "Bo", "Ivy", "Otis", "June", "Frank", "Lena"]
    static let lastNames = ["Hayes", "Ortiz", "Brooks", "Patel", "Nguyen", "Carter", "Wells", "Doyle", "Reyes",
                            "Price", "Lowe", "Kim", "Shaw", "Baker", "Grant"]

    /// Three drivers looking for work: one of each skill level.
    public static func candidates<R: RandomNumberGenerator>(using rng: inout R, now: Date = Date()) -> [Driver] {
        (1...3).map { skill in
            Driver(name: "\(firstNames.randomElement(using: &rng)!) \(lastNames.randomElement(using: &rng)!)",
                   skill: skill, lastUpdate: now)
        }
    }
}

public extension CareerState {
    enum HireResult: Equatable, Sendable { case hired, notEnoughMoney(short: Int), notACandidate }

    /// Hires a candidate. They'll start once they have a truck.
    @discardableResult
    mutating func hire(_ candidate: Driver, now: Date = Date()) -> HireResult {
        guard let index = candidates.firstIndex(where: { $0.id == candidate.id }) else { return .notACandidate }
        guard money >= candidate.hireFee else { return .notEnoughMoney(short: candidate.hireFee - money) }
        money -= candidate.hireFee
        var driver = candidates.remove(at: index)
        driver.lastUpdate = now
        drivers.append(driver)
        // A new face takes their place on the list.
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        var rng = SeededRandom(seed: seed)
        var replacement = Company.candidates(using: &rng, now: now)[candidate.skill - 1]
        replacement.skill = candidate.skill
        candidates.insert(replacement, at: min(index, candidates.count))
        // A free truck goes to them right away.
        if let truck = freeTrucks.first { assign(driver.id, to: truck, now: now) }
        return .hired
    }

    /// Owned trucks that nobody is driving (not you, not a driver).
    var freeTrucks: [TruckSpec] {
        TruckSpec.catalog.filter { truck in
            owns(truck) && truck.id != selectedTruck && !drivers.contains { $0.truckID == truck.id }
        }
    }

    /// Gives a driver a truck (or takes it away with nil). Counts their work up to now first.
    @discardableResult
    mutating func assign(_ driverID: UUID, to truck: TruckSpec?, now: Date = Date()) -> Bool {
        guard let index = drivers.firstIndex(where: { $0.id == driverID }) else { return false }
        if let truck {
            guard owns(truck), truck.id != selectedTruck,
                  !drivers.contains(where: { $0.truckID == truck.id && $0.id != driverID }) else { return false }
        }
        _ = updateDrivers(now: now)
        drivers[index].truckID = truck?.id
        drivers[index].progress = 0
        drivers[index].lastUpdate = now
        return true
    }

    /// Lets a driver go (the hiring fee isn't refunded).
    mutating func fire(_ driverID: UUID, now: Date = Date()) {
        _ = updateDrivers(now: now)
        drivers.removeAll { $0.id == driverID }
    }

    /// Counts the drivers' work since the last update: finished jobs pay into the bank.
    mutating func updateDrivers(now: Date = Date()) -> [DriverReport] {
        var reports: [DriverReport] = []
        for i in drivers.indices {
            let elapsed = min(Company.maxAwaySeconds, max(0, now.timeIntervalSince(drivers[i].lastUpdate)))
            drivers[i].lastUpdate = now
            guard drivers[i].truckID != nil, elapsed > 0 else { continue }
            let jobSeconds = drivers[i].minutesPerJob * 60
            let total = drivers[i].progress + elapsed
            let jobs = Int(total / jobSeconds)
            drivers[i].progress = total - Double(jobs) * jobSeconds
            guard jobs > 0 else { continue }
            let pay = jobs * drivers[i].payPerJob
            drivers[i].jobsDone += jobs
            drivers[i].earned += pay
            money += pay
            totalEarned += pay
            reports.append(DriverReport(name: drivers[i].name, jobs: jobs, earned: pay))
        }
        return reports
    }
}
