import Foundation

/// Hand-made missions with a story, one after another. Each needs a reputation level, is told by the
/// dispatcher, and pays a big bonus when delivered on time (and, for hazmat, without a spill).
public struct StoryMission: Equatable, Sendable {
    public let id: Int
    public let title: String
    public let cargoName: String
    public let from: String
    public let to: String
    /// The deadline, as a share of a normal job's deadline (tighter is harder).
    public let deadlineFactor: Double
    public let bonus: Int
    public let level: ReputationLevel
    /// Read out by the dispatcher when the mission starts.
    public let briefing: String
    /// Read out when it's delivered on time.
    public let success: String

    public static let all: [StoryMission] = [
        StoryMission(id: 1, title: "The Medicine Run", cargoName: "Medical supplies", from: "ridgeport", to: "bayview",
                     deadlineFactor: 0.85, bonus: 2_000, level: .rookie,
                     briefing: "Driver, this one matters. Bayview Hospital is out of medicine, and the bridge on the way closes for repairs soon. Get these supplies there before it does. Drive safe, but don't dawdle.",
                     success: "You made it! The hospital has its medicine, and the bridge closed right behind you. Nice work, driver."),
        StoryMission(id: 2, title: "The Ice Cream Emergency", cargoName: "Ice cream", from: "millbrook", to: "ridgeport",
                     deadlineFactor: 0.9, bonus: 2_500, level: .reliable,
                     briefing: "Driver, the Ridgeport summer fair just ran out of ice cream, and there are a lot of unhappy kids down there. Keep it cold and get it there fast.",
                     success: "The fair is saved! I hear the line for ice cream goes around the block. Good job."),
        StoryMission(id: 3, title: "The Giant Blade", cargoName: "Wind turbine blade", from: "ironton", to: "cedar_falls",
                     deadlineFactor: 1.0, bonus: 3_500, level: .reliable,
                     briefing: "Driver, Cedar Falls is building its first wind farm, and the last blade is waiting for you in Ironton. It's long, it's wide, and it's the only one they've got. Keep it under the oversize limit.",
                     success: "The last blade is in! Cedar Falls will have clean power by spring, thanks to you."),
        StoryMission(id: 4, title: "Fuel for the Storm", cargoName: "Gasoline", from: "ridgeport", to: "cedar_falls",
                     deadlineFactor: 1.0, bonus: 5_000, level: .respected,
                     briefing: "Driver, a big storm is coming, and Cedar Falls needs fuel for its generators before it hits. It's hazmat, so one crash and it's all over. Steady hands.",
                     success: "The generators are full and the lights stay on in Cedar Falls. You're a hero tonight, driver."),
        StoryMission(id: 5, title: "The Legend's Load", cargoName: "Steel beams", from: "ironton", to: "millbrook",
                     deadlineFactor: 0.85, bonus: 8_000, level: .pro,
                     briefing: "Driver, Millbrook is rebuilding its old bridge, and they asked for the best driver in the state to bring the last steel. That's you. It's heavy and the deadline is tight. Make it count.",
                     success: "The last beam is in place. They're naming the new bridge after the trucker who brought it. That's legendary, driver."),
    ]

    public var cargo: Cargo { Cargo.catalog.first { $0.name == cargoName } ?? Cargo.catalog[0] }

    public static func withID(_ id: Int?) -> StoryMission? { all.first { $0.id == id } }

    /// The mission as a job on the board.
    public func job(map: WorldMap = .standard) -> DeliveryJob {
        let distance = map.route(from: from, to: to).map(map.length(of:)) ?? 15_000
        let pay = Int((distance / 1_000 * cargo.ratePerKm / 10).rounded()) * 10
        let normal = (distance / JobBoard.fairSpeed * (cargo.urgent ? 1.35 : 1.7) + 120)
        let timeLimit = ((normal * deadlineFactor) / 60).rounded(.up) * 60
        var job = DeliveryJob(cargo: cargo, distance: distance, pay: pay, timeLimit: timeLimit, origin: from, destination: to)
        job.storyID = id
        return job
    }
}

public extension CareerState {
    /// The next story mission, if the player has the reputation for it.
    var nextStoryMission: StoryMission? {
        guard let m = StoryMission.all.first(where: { $0.id == storyProgress + 1 }) else { return nil }
        return reputationLevel >= m.level ? m : nil
    }

    /// The next mission still locked by reputation, to say what it takes.
    var lockedStoryMission: StoryMission? {
        guard let m = StoryMission.all.first(where: { $0.id == storyProgress + 1 }), reputationLevel < m.level else { return nil }
        return m
    }

    static func countsForStory(_ job: DeliveryJob, summary: TripSummary) -> Bool {
        countsForContract(job, summary: summary)
    }
}

// MARK: - Breakdowns: calls from your drivers

public extension Driver {
    /// A tow for a broken-down driver.
    static let towCost = 300
    /// How long a breakdown lasts if you let them wait it out.
    static let breakdownWait: TimeInterval = 2 * 3600
    /// Chance of a breakdown on each delivery.
    static let breakdownChance = 0.04
}

public extension CareerState {
    /// Pays for a tow: the driver is back on the road right away.
    @discardableResult
    mutating func sendTow(_ driver: Driver, now: Date = Date()) -> Bool {
        guard let i = drivers.firstIndex(where: { $0.id == driver.id }), drivers[i].brokeDownIn != nil,
              money >= Driver.towCost else { return false }
        money -= Driver.towCost
        drivers[i].brokeDownIn = nil
        drivers[i].stuckUntil = nil
        drivers[i].lastUpdate = now
        return true
    }

    /// Lets them wait for a free repair: they're stuck for two hours.
    mutating func letWait(_ driver: Driver, now: Date = Date()) {
        guard let i = drivers.firstIndex(where: { $0.id == driver.id }), drivers[i].brokeDownIn != nil else { return }
        drivers[i].stuckUntil = now.addingTimeInterval(Driver.breakdownWait)
    }
}

// MARK: - CB radio

public extension DrivingSession {
    /// Seconds between CB radio calls from other truckers.
    static let cbInterval: ClosedRange<Double> = 150...330
}
