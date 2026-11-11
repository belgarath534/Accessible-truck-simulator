import Foundation

// MARK: - Daily delivery streak

public extension CareerState {
    /// The bonus for the first delivery of each day: $100 per day in the streak, up to a week.
    static func streakBonus(days: Int) -> Int { 100 * min(max(days, 1), 7) }

    /// A day as yyyymmdd, in the player's calendar.
    static func dayNumber(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 2026) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    /// The streak bonus line if this is the day's first delivery (nil otherwise). Call before `recordStreak`.
    func streakLine(now: Date = Date(), calendar: Calendar = .current) -> Payout.Line? {
        let today = Self.dayNumber(now, calendar: calendar)
        guard lastDeliveryDay != today else { return nil }
        let days = nextStreak(now: now, calendar: calendar)
        return Payout.Line(label: "Daily streak bonus, day \(days)", amount: Self.streakBonus(days: days))
    }

    private func nextStreak(now: Date, calendar: Calendar) -> Int {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return 1 }
        return lastDeliveryDay == Self.dayNumber(yesterday, calendar: calendar) ? streakDays + 1 : 1
    }

    /// Records today's delivery for the streak. Returns news when the streak grows.
    mutating func recordStreak(now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let today = Self.dayNumber(now, calendar: calendar)
        guard lastDeliveryDay != today else { return [] }
        streakDays = nextStreak(now: now, calendar: calendar)
        lastDeliveryDay = today
        bestStreak = max(bestStreak, streakDays)
        return streakDays > 1 ? ["Daily streak: \(streakDays) days in a row! Deliver again tomorrow to keep it going."]
                              : ["Daily streak started. Deliver again tomorrow for a bigger bonus."]
    }
}

// MARK: - The rival company

public enum Rival {
    public static let name = "Speedy Freight"

    /// What the rival earns in a whole week: more as your reputation grows, a bit different every week.
    public static func weeklyTarget(week: Int, level: ReputationLevel) -> Int {
        var rng = SeededRandom(seed: UInt64(week) &* 2_654_435_761 &+ 99)
        let base = [9_000.0, 15_000, 24_000, 36_000, 50_000][level.rawValue]
        return Int((base * Double.random(in: 0.8...1.25, using: &rng) / 100).rounded()) * 100
    }

    /// How far into the week a date is (0 on Monday morning, 1 at the end of Sunday).
    public static func weekFraction(_ date: Date, calendar: Calendar = .current) -> Double {
        var cal = calendar
        cal.firstWeekday = 2
        guard let start = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / (7 * 86_400)))
    }
}

public extension CareerState {
    /// What the rival has earned so far this week.
    func rivalSoFar(now: Date = Date()) -> Int {
        let target = Rival.weeklyTarget(week: WeeklyChallenge.weekNumber(of: now), level: reputationLevel)
        return Int((Double(target) * Rival.weekFraction(now) / 100).rounded()) * 100
    }

    /// What you've earned this week (from deliveries and drives).
    func earnedThisWeek(now: Date = Date()) -> Int {
        weekEarnedWeek == WeeklyChallenge.weekNumber(of: now) ? weekEarned : 0
    }

    /// Adds money earned to this week's race with the rival. When a new week starts, settles last week's race
    /// and returns the result.
    mutating func recordRace(earned: Int, now: Date = Date()) -> [String] {
        let week = WeeklyChallenge.weekNumber(of: now)
        var news: [String] = []
        if weekEarnedWeek != week {
            if weekEarnedWeek != 0 {
                let theirs = Rival.weeklyTarget(week: weekEarnedWeek, level: reputationLevel)
                if weekEarned > theirs {
                    rivalWins += 1
                    news.append("Last week you beat \(Rival.name): \(Phrases.money(weekEarned)) to their \(Phrases.money(theirs))!")
                } else {
                    news.append("Last week \(Rival.name) beat you: \(Phrases.money(theirs)) to your \(Phrases.money(weekEarned)). Get them this week!")
                }
            }
            weekEarnedWeek = week
            weekEarned = 0
        }
        weekEarned += max(0, earned)
        return news
    }

    /// "You're ahead of Speedy Freight by $1,200 this week."
    func raceStatus(now: Date = Date()) -> String {
        let mine = earnedThisWeek(now: now), theirs = rivalSoFar(now: now)
        if mine > theirs { return "You're ahead of \(Rival.name) by \(Phrases.money(mine - theirs)) this week." }
        if mine < theirs { return "\(Rival.name) is ahead of you by \(Phrases.money(theirs - mine)) this week." }
        return "You and \(Rival.name) are tied this week."
    }
}

// MARK: - Career stats

public extension CareerState {
    /// Everything for the career stats page, as lines to read.
    func statsLines(units: UnitSystem) -> [String] {
        let mph = bestTurboSpeed * 2.236_94
        var lines = [
            "Deliveries: \(jobsCompleted).",
            "Money earned: \(Phrases.money(totalEarned)).",
            "Distance driven: \(units.distance(kilometersDriven * 1_000)).",
            "Reputation: \(reputationLevel.title), \(reputation) points.",
            "Crash-free deliveries: \(cleanDeliveries). Perfect stops: \(perfectStops).",
            "Trucks owned: \(ownedTrucks.count). Drivers hired: \(drivers.count).",
            "Achievements: \(achievements.count) of \(Achievement.allCases.count).",
            "Story missions finished: \(storyProgress) of \(StoryMission.all.count).",
            "Weekly challenges won: \(weeklyChallengesWon). Weeks you beat \(Rival.name): \(rivalWins).",
            "Best daily streak: \(bestStreak) day\(bestStreak == 1 ? "" : "s").",
            "Towns visited: \(visitedTowns.count) of \(WorldMap.standard.towns.count).",
        ]
        if mph > 0 { lines.append("Top speed in Turbo Mode: \(Int(mph.rounded())) miles per hour.") }
        return lines
    }
}
