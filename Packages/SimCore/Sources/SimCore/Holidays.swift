import Foundation

/// Holiday events, on by themselves by date: holiday cargo on the job board with a bonus, a greeting,
/// and snow much more likely at Christmas.
public enum Holiday: String, CaseIterable, Sendable {
    case halloween, thanksgiving, christmas, newYear

    /// The holiday on a date, if any (month and day, any year).
    public static func on(_ date: Date, calendar: Calendar = .current) -> Holiday? {
        let c = calendar.dateComponents([.month, .day], from: date)
        guard let m = c.month, let d = c.day else { return nil }
        switch (m, d) {
        case (10, 25...31): return .halloween
        case (11, 20...30): return .thanksgiving
        case (12, 15...26): return .christmas
        case (12, 31...31), (1, 1...2): return .newYear
        default: return nil
        }
    }

    public var name: String {
        switch self {
        case .halloween: return "Halloween"
        case .thanksgiving: return "Thanksgiving"
        case .christmas: return "Christmas"
        case .newYear: return "New Year"
        }
    }

    /// Said when a drive starts during the holiday.
    public var greeting: String {
        switch self {
        case .halloween: return "Happy Halloween, trucker! Pumpkin deliveries pay a holiday bonus this week."
        case .thanksgiving: return "Happy Thanksgiving, trucker! Turkeys and pies pay a holiday bonus this week."
        case .christmas: return "Merry Christmas, trucker! Presents and Christmas trees pay a holiday bonus, and it might just snow."
        case .newYear: return "Happy New Year, trucker! Fireworks deliveries pay a holiday bonus. Careful: they're hazmat."
        }
    }

    /// The holiday's own loads.
    public var cargo: [Cargo] {
        switch self {
        case .halloween:
            return [Cargo(name: "Pumpkins", massKg: 12_000, ratePerKm: 160)]
        case .thanksgiving:
            return [Cargo(name: "Turkeys", massKg: 10_000, ratePerKm: 175, urgent: true, kind: .refrigerated),
                    Cargo(name: "Pumpkin pies", massKg: 4_000, ratePerKm: 165, fragile: true, urgent: true)]
        case .christmas:
            return [Cargo(name: "Christmas presents", massKg: 5_000, ratePerKm: 185, fragile: true, urgent: true),
                    Cargo(name: "Christmas trees", massKg: 9_000, ratePerKm: 165)]
        case .newYear:
            return [Cargo(name: "Fireworks", massKg: 6_000, ratePerKm: 245, kind: .hazmat)]
        }
    }

    /// Extra pay on holiday loads.
    public static let bonus = 0.15

    /// Holiday loads, by name (for the bonus and for saved jobs).
    public static func isHolidayCargo(_ name: String) -> Bool { allCases.contains { $0.cargo.contains { $0.name == name } } }

    /// Christmas week: snow much more likely (otherwise the usual winter weather).
    public static func weather<R: RandomNumberGenerator>(using rng: inout R, date: Date, calendar: Calendar = .current) -> Weather {
        let month = calendar.component(.month, from: date)
        if Holiday.on(date, calendar: calendar) == .christmas, Double.random(in: 0...1, using: &rng) < 0.5 { return .snow }
        return Weather.random(using: &rng, month: month)
    }
}

public extension JobBoard {
    /// During a holiday, the last job on the board is holiday cargo.
    static func addHolidayJob<R: RandomNumberGenerator>(to board: inout [DeliveryJob], holiday: Holiday?, using rng: inout R,
                                                        from origin: String, level: ReputationLevel) {
        guard let holiday, !board.isEmpty else { return }
        let choices = holiday.cargo.filter { $0.kind.requiredLevel <= level }
        guard let cargo = choices.randomElement(using: &rng) else { return }
        let job = makeJob(using: &rng, from: origin, level: level, cargo: cargo)
        // Keep story missions and contract jobs; replace the last ordinary job.
        if let i = board.lastIndex(where: { $0.storyID == nil && $0.contractID == nil }) { board[i] = job }
    }
}
