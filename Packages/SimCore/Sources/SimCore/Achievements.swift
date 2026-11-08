import Foundation

/// Achievements: tracked in the save file, so they work offline and without Game Center,
/// and reported to Game Center when the player is signed in.
///
/// The raw values are permanent: they are saved, and they are the Game Center ids ("trucksim." + raw value).
public enum Achievement: String, CaseIterable, Codable, Sendable {
    case tutorial
    case firstDelivery = "first_delivery"
    case fillUp = "fill_up"
    case busted
    case perfectStop = "perfect_stop"
    case cleanRun = "clean_run"
    case onTime = "on_time"
    case heavyHauler = "heavy_hauler"
    case handleWithCare = "handle_with_care"
    case deliveries10 = "deliveries_10"
    case deliveries50 = "deliveries_50"
    case deliveries100 = "deliveries_100"
    case earned10k = "earned_10k"
    case earned50k = "earned_50k"
    case thousandKilometers = "km_1000"
    case allTowns = "all_towns"
    case firstUpgrade = "first_upgrade"
    case maxedOut = "maxed_out"
    case workhorse
    case roadKing = "road_king"
    case firstDriver = "first_driver"
    case fleetOwner = "fleet_owner"

    public var gameCenterID: String { "trucksim." + rawValue }

    public var title: String {
        switch self {
        case .tutorial: return "Learner's Permit"
        case .firstDelivery: return "First Load"
        case .fillUp: return "Fill 'er Up"
        case .busted: return "Busted"
        case .perfectStop: return "Right on the Mark"
        case .cleanRun: return "Not a Scratch"
        case .onTime: return "On the Clock"
        case .heavyHauler: return "Heavy Hauler"
        case .handleWithCare: return "Handle with Care"
        case .deliveries10: return "Regular"
        case .deliveries50: return "Road Veteran"
        case .deliveries100: return "Legend of the Highway"
        case .earned10k: return "Ten Grand"
        case .earned50k: return "Big Money"
        case .thousandKilometers: return "A Thousand Kilometers"
        case .allTowns: return "Seen It All"
        case .firstUpgrade: return "Tuned Up"
        case .maxedOut: return "Maxed Out"
        case .workhorse: return "Second Truck"
        case .roadKing: return "King of the Road"
        case .firstDriver: return "Now Hiring"
        case .fleetOwner: return "Fleet Owner"
        }
    }

    /// What to do to earn it.
    public var detail: String {
        switch self {
        case .tutorial: return "Finish the tutorial."
        case .firstDelivery: return "Deliver your first job."
        case .fillUp: return "Fill up at a truck stop."
        case .busted: return "Get a speeding ticket. It happens to everyone."
        case .perfectStop: return "Make a perfect stop at a drop-off."
        case .cleanRun: return "Deliver a job without a single crash."
        case .onTime: return "Deliver a job on time."
        case .heavyHauler: return "Deliver a load of 20 tonnes or more."
        case .handleWithCare: return "Deliver fragile cargo without a crash."
        case .deliveries10: return "Deliver 10 jobs."
        case .deliveries50: return "Deliver 50 jobs."
        case .deliveries100: return "Deliver 100 jobs."
        case .earned10k: return "Earn $10,000 in total."
        case .earned50k: return "Earn $50,000 in total."
        case .thousandKilometers: return "Drive 1,000 kilometers, about 620 miles, in total."
        case .allTowns: return "Visit every town on the map."
        case .firstUpgrade: return "Buy your first upgrade."
        case .maxedOut: return "Buy the top level of any upgrade."
        case .workhorse: return "Buy the Workhorse."
        case .roadKing: return "Buy the Road King."
        case .firstDriver: return "Hire your first driver."
        case .fleetOwner: return "Have two drivers working for you at once."
        }
    }

    /// Game Center points (all together at most 1,000).
    public var points: Int {
        switch self {
        case .tutorial, .fillUp, .busted, .onTime: return 10
        case .firstDelivery, .cleanRun, .firstUpgrade: return 20
        case .perfectStop, .heavyHauler, .handleWithCare, .deliveries10, .workhorse, .firstDriver: return 30
        case .earned10k: return 40
        case .maxedOut, .thousandKilometers: return 50
        case .deliveries50, .allTowns, .fleetOwner: return 60
        case .roadKing, .earned50k: return 80
        case .deliveries100: return 100
        }
    }

    /// Spoken when it's earned.
    public var announcement: String { "Achievement unlocked: \(title)! \(detail)" }
}

/// Leaderboards, by Game Center id.
public enum Leaderboard: String, CaseIterable, Sendable {
    case totalEarned = "trucksim.total_earned"
    case deliveries = "trucksim.deliveries"

    public var title: String {
        switch self {
        case .totalEarned: return "Money Earned"
        case .deliveries: return "Deliveries"
        }
    }

    public func score(_ career: CareerState) -> Int {
        switch self {
        case .totalEarned: return max(0, career.totalEarned)
        case .deliveries: return career.jobsCompleted
        }
    }
}

/// What happened on the drive that just ended, for the achievements that depend on it.
public struct TripResult: Sendable {
    public var job: DeliveryJob?
    public var summary: TripSummary?
    public var stats: TripStats

    public init(job: DeliveryJob?, summary: TripSummary?, stats: TripStats) {
        self.job = job
        self.summary = summary
        self.stats = stats
    }
}

public extension CareerState {
    func has(_ achievement: Achievement) -> Bool { achievements.contains(achievement.rawValue) }

    /// Unlocks one achievement. Returns true if it's new.
    @discardableResult
    mutating func unlock(_ achievement: Achievement) -> Bool {
        guard !has(achievement) else { return false }
        achievements.append(achievement.rawValue)
        return true
    }

    /// Checks everything that can be earned and unlocks what's new. Pass the drive that just ended, if any.
    /// Returns the newly unlocked achievements, in the order to announce them.
    @discardableResult
    mutating func checkAchievements(after trip: TripResult? = nil) -> [Achievement] {
        var earned: [Achievement] = []
        func check(_ a: Achievement, _ condition: Bool) {
            if condition && unlock(a) { earned.append(a) }
        }
        if let trip {
            let s = trip.stats
            check(.fillUp, s.fuelCost > 0 && s.tows == 0) // a tow's fuel doesn't count
            check(.busted, s.tickets > 0)
            if let job = trip.job, let summary = trip.summary {
                check(.perfectStop, summary.stopRating == .perfect)
                check(.cleanRun, s.crashes == 0)
                check(.onTime, s.drivingTime <= job.timeLimit)
                check(.heavyHauler, job.cargo.massKg >= 20_000)
                check(.handleWithCare, job.cargo.fragile && s.crashes == 0)
            }
        }
        check(.firstDelivery, jobsCompleted >= 1)
        check(.deliveries10, jobsCompleted >= 10)
        check(.deliveries50, jobsCompleted >= 50)
        check(.deliveries100, jobsCompleted >= 100)
        check(.earned10k, totalEarned >= 10_000)
        check(.earned50k, totalEarned >= 50_000)
        check(.thousandKilometers, kilometersDriven >= 1_000)
        check(.allTowns, WorldMap.standard.towns.allSatisfy { visitedTowns.contains($0.id) })
        check(.firstUpgrade, upgrades.values.contains { l in UpgradeKind.allCases.contains { l[$0] > 0 } })
        check(.maxedOut, upgrades.values.contains { l in UpgradeKind.allCases.contains { $0.price(after: l[$0]) == nil } })
        check(.workhorse, owns(.workhorse))
        check(.roadKing, owns(.roadKing))
        check(.firstDriver, !drivers.isEmpty)
        check(.fleetOwner, drivers.filter { $0.truckID != nil }.count >= 2)
        return earned
    }
}
