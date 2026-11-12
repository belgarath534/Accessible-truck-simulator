import Foundation

/// Duel Mode: pass-and-play on one phone. Everyone drives the same route, with the same traffic, weather and
/// deer (one seed for all), one after another. Fastest time wins; each crash adds a time penalty.
public struct Duel: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var name: String
        /// Driving time in seconds (nil until they've driven).
        public var time: Double?
        public var crashes = 0
        public var delivered = false
        public var played = false

        public init(name: String) { self.name = name }

        /// Time plus crash penalties; nil if they didn't deliver.
        public var total: Double? {
            guard delivered, let time else { return nil }
            return time + Double(crashes) * Duel.crashPenalty
        }
    }

    public static let crashPenalty = 15.0
    public static let maxPlayers = 4

    public let job: DeliveryJob
    public let seed: UInt64
    public let weather: Weather
    public private(set) var players: [Entry]
    public private(set) var turn = 0

    public init(job: DeliveryJob, players names: [String], seed: UInt64, weather: Weather) {
        self.job = job
        self.seed = seed
        self.weather = weather
        players = names.prefix(Duel.maxPlayers).enumerated().map { i, raw in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return Entry(name: name.isEmpty ? "Player \(i + 1)" : name)
        }
    }

    /// A duel job between two towns with a chosen cargo. No pay and no time limit: it's a race.
    public static func makeJob(from origin: String, to destination: String, cargo: Cargo,
                               map: WorldMap = .standard) -> DeliveryJob? {
        guard origin != destination, let route = map.route(from: origin, to: destination) else { return nil }
        let distance = map.length(of: route)
        // A generous limit that never matters: the duel is about who's fastest.
        return DeliveryJob(cargo: cargo, distance: distance, pay: 0, timeLimit: max(3_600, distance / 3),
                           origin: origin, destination: destination)
    }

    public var current: Entry? { turn < players.count ? players[turn] : nil }
    public var isOver: Bool { turn >= players.count }

    /// Records the current player's drive and moves on to the next player.
    public mutating func record(time: Double, crashes: Int, delivered: Bool) {
        guard !isOver else { return }
        players[turn].time = time
        players[turn].crashes = crashes
        players[turn].delivered = delivered
        players[turn].played = true
        turn += 1
    }

    /// Best first; anyone who didn't deliver comes last.
    public var standings: [Entry] {
        players.filter(\.played).sorted { a, b in
            switch (a.total, b.total) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            default: return false
            }
        }
    }

    public var winner: Entry? {
        let s = standings
        guard let first = s.first, let best = first.total else { return nil }
        // A dead heat has no single winner.
        if s.count > 1, let second = s[1].total, abs(second - best) < 0.05 { return nil }
        return first
    }

    public static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 60 ? "\(s / 60) minute\(s / 60 == 1 ? "" : "s") \(s % 60) second\(s % 60 == 1 ? "" : "s")"
                       : "\(s) second\(s == 1 ? "" : "s")"
    }

    /// One player's line: "Sam: 6 minutes 12 seconds, 1 crash (plus 15 seconds), total 6 minutes 27 seconds."
    public static func line(_ e: Entry) -> String {
        guard e.delivered, let time = e.time, let total = e.total else { return "\(e.name): didn't finish." }
        if e.crashes == 0 { return "\(e.name): \(clock(time)), no crashes." }
        let penalty = Int(Double(e.crashes) * crashPenalty)
        return "\(e.name): \(clock(time)), \(e.crashes) crash\(e.crashes == 1 ? "" : "es") (plus \(penalty) seconds), total \(clock(total))."
    }

    public var spokenResults: String {
        let lines = standings.map(Duel.line).joined(separator: " ")
        if let winner { return "\(winner.name) wins! " + lines }
        if standings.contains(where: { $0.total != nil }) { return "It's a tie! " + lines }
        return "Nobody finished. " + lines
    }

    /// "Sam's turn. Deliver ..."
    public func turnIntro(units: UnitSystem) -> String {
        guard let p = current else { return "" }
        let route = "\(job.cargo.name) from \(job.originName ?? "town") to \(job.destinationName ?? "the drop-off"), \(units.distance(job.distance))"
        let target = standings.first?.total.map { " Time to beat: \(Duel.clock($0))." } ?? ""
        return "Duel. \(p.name)'s turn, player \(turn + 1) of \(players.count). \(route). Fastest time wins, and each crash adds \(Int(Duel.crashPenalty)) seconds.\(target)"
    }
}
