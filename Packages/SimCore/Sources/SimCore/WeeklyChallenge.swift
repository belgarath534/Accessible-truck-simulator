import Foundation

/// A challenge that changes every week (Monday to Sunday, by the player's calendar), with a money prize.
/// Everyone gets the same challenge in the same week: it comes from the week's number.
public struct WeeklyChallenge: Equatable, Sendable {
    public enum Goal: Equatable, Sendable {
        /// Deliver this many loads of a kind (livestock, refrigerated, oversize, hazmat).
        case deliverKind(CargoKind, count: Int)
        /// Deliveries with no crashes.
        case cleanDeliveries(count: Int)
        /// On-time deliveries.
        case onTime(count: Int)
        /// Perfect stops or perfect dockings.
        case perfectFinishes(count: Int)
        /// Deliveries to one town.
        case deliverTo(town: String, count: Int)
        /// Deliveries in rain, storms or snow.
        case badWeather(count: Int)
    }

    /// Year and week number, like 202646.
    public let week: Int
    public let goal: Goal
    public let prize: Int

    public var target: Int {
        switch goal {
        case let .deliverKind(_, n), let .cleanDeliveries(n), let .onTime(n), let .perfectFinishes(n),
             let .deliverTo(_, n), let .badWeather(n): return n
        }
    }

    /// "Deliver 4 livestock loads."
    public var description: String {
        switch goal {
        case let .deliverKind(kind, n): return "Deliver \(n) \(kind.label ?? "special") load\(n == 1 ? "" : "s")."
        case let .cleanDeliveries(n): return "Make \(n) deliveries without a single crash."
        case let .onTime(n): return "Deliver \(n) jobs on time."
        case let .perfectFinishes(n): return "Finish \(n) deliveries with a perfect stop or a perfect docking."
        case let .deliverTo(town, n):
            return "Deliver \(n) loads to \(WorldMap.standard.node(town)?.name ?? town)."
        case let .badWeather(n): return "Deliver \(n) loads in rain, storms or snow."
        }
    }

    /// The challenge for a week: picked from the week number, so it's the same for every player.
    public static func forWeek(_ week: Int) -> WeeklyChallenge {
        var rng = SeededRandom(seed: UInt64(week) &* 0x9E37_79B9_7F4A_7C15 &+ 17)
        let towns = WorldMap.standard.towns.map(\.id)
        let goals: [Goal] = [
            .deliverKind(.livestock, count: 4), .deliverKind(.refrigerated, count: 4), .deliverKind(.oversize, count: 3),
            .deliverKind(.hazmat, count: 3), .cleanDeliveries(count: 5), .onTime(count: 6), .perfectFinishes(count: 4),
            .deliverTo(town: towns.randomElement(using: &rng)!, count: 4), .badWeather(count: 3),
        ]
        let goal = goals.randomElement(using: &rng)!
        let prize: Int
        switch goal {
        case let .deliverKind(kind, _): prize = kind == .hazmat || kind == .oversize ? 6_000 : 4_000
        case .perfectFinishes, .badWeather: prize = 5_000
        default: prize = 3_500
        }
        return WeeklyChallenge(week: week, goal: goal, prize: prize)
    }

    /// The week a date falls in (Monday first), as year * 100 + week number.
    public static func weekNumber(of date: Date, calendar: Calendar = .current) -> Int {
        var cal = calendar
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return (c.yearForWeekOfYear ?? 2026) * 100 + (c.weekOfYear ?? 1)
    }

    /// Whether a finished delivery counts toward this challenge.
    func counts(job: DeliveryJob, summary: TripSummary, weather: Weather) -> Bool {
        let s = summary.stats
        guard !(job.cargo.kind == .hazmat && s.hazmatSpilled) else { return false }
        switch goal {
        case let .deliverKind(kind, _): return job.cargo.kind == kind
        case .cleanDeliveries: return s.crashes == 0
        case .onTime: return s.drivingTime <= job.timeLimit
        case .perfectFinishes: return summary.stopRating == .perfect || summary.dockRating == .perfect
        case let .deliverTo(town, _): return job.destination == town
        case .badWeather: return weather != .clear
        }
    }
}

public extension CareerState {
    /// This week's challenge (a new one starts each Monday).
    func weeklyChallenge(now: Date = Date()) -> WeeklyChallenge {
        WeeklyChallenge.forWeek(WeeklyChallenge.weekNumber(of: now))
    }

    /// Progress on this week's challenge (0 in a new week).
    func weeklyProgress(now: Date = Date()) -> Int {
        weeklyWeek == WeeklyChallenge.weekNumber(of: now) ? weeklyCount : 0
    }

    func weeklyDone(now: Date = Date()) -> Bool {
        weeklyWeek == WeeklyChallenge.weekNumber(of: now) && weeklyClaimed
    }

    /// Counts a delivery toward the weekly challenge and pays the prize when it's done. Returns news.
    mutating func recordWeekly(job: DeliveryJob, summary: TripSummary, weather: Weather, now: Date = Date()) -> [String] {
        let challenge = weeklyChallenge(now: now)
        if weeklyWeek != challenge.week {
            weeklyWeek = challenge.week
            weeklyCount = 0
            weeklyClaimed = false
        }
        guard !weeklyClaimed, challenge.counts(job: job, summary: summary, weather: weather) else { return [] }
        weeklyCount += 1
        if weeklyCount >= challenge.target {
            weeklyClaimed = true
            weeklyChallengesWon += 1
            money += challenge.prize
            totalEarned += challenge.prize
            return ["Weekly challenge complete! You won \(Phrases.money(challenge.prize)). A new challenge starts on Monday."]
        }
        return ["Weekly challenge: \(weeklyCount) of \(challenge.target)."]
    }
}
