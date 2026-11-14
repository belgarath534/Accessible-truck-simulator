import Foundation

/// Online Race: two players drive the same route at the same time, each in their own truck, connected through
/// Game Center with a room code. Each side sends its state a few times a second; the other truck is placed on
/// your road when it's near, so you hear it, can pass it and can crash into it. Fastest time wins, with the same
/// 15-second crash penalty as Duel Mode.

/// What the other player's game tells yours, a few times a second.
public struct RivalState: Codable, Equatable, Sendable {
    /// Metres left to the drop-off.
    public var remaining: Double
    /// Metres from the centre of their lane (negative = toward the left lane).
    public var lateral: Double
    public var speed: Double
    public var crashes: Int
    /// Their clock: seconds since they started moving.
    public var drivingTime: Double
    public var finished: Bool
    public var quit: Bool

    public init(remaining: Double, lateral: Double = 0, speed: Double = 0, crashes: Int = 0, drivingTime: Double = 0,
                finished: Bool = false, quit: Bool = false) {
        self.remaining = remaining; self.lateral = lateral; self.speed = speed; self.crashes = crashes
        self.drivingTime = drivingTime; self.finished = finished; self.quit = quit
    }

    /// Time plus crash penalties.
    public var total: Double { drivingTime + Double(crashes) * Duel.crashPenalty }
}

/// The race both players drive: chosen by whoever made the room.
public struct RaceSetup: Codable, Equatable, Sendable {
    public var from: String
    public var to: String
    public var cargoName: String
    public var seed: UInt64
    public var weather: Weather

    public init(from: String, to: String, cargoName: String, seed: UInt64, weather: Weather) {
        self.from = from; self.to = to; self.cargoName = cargoName; self.seed = seed; self.weather = weather
    }

    public var cargo: Cargo { Cargo.catalog.first { $0.name == cargoName } ?? Cargo.catalog[0] }
    public var job: DeliveryJob? { Duel.makeJob(from: from, to: to, cargo: cargo) }
}

/// Everything sent between the two games.
public enum RaceMessage: Codable, Equatable, Sendable {
    /// Sent first. `creator`: this player made the room and chooses the route.
    case hello(name: String, creator: Bool, version: Int)
    case setup(RaceSetup)
    case ready
    case state(RivalState)
    case quit

    /// Both games must speak the same version of these messages.
    public static let version = 1

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    public static func decode(_ data: Data) -> RaceMessage? { try? JSONDecoder().decode(RaceMessage.self, from: data) }
}

public enum RaceCode {
    /// A four-digit room code, never starting with zero, so it's easy to read out.
    public static func random<R: RandomNumberGenerator>(using rng: inout R) -> Int { Int.random(in: 1_000...9_999, using: &rng) }

    public static func random() -> Int {
        var rng = SystemRandomNumberGenerator()
        return random(using: &rng)
    }

    /// "4 8 2 7", so the voice reads digits, not "four thousand...".
    public static func spoken(_ code: Int) -> String { String(code).map(String.init).joined(separator: " ") }

    /// A typed code, if it's a valid one.
    public static func parse(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard digits.count == 4, let n = Int(digits), n >= 1_000 else { return nil }
        return n
    }
}

/// The result once both are done (or one left).
public enum RaceOutcome: Equatable, Sendable {
    case won, lost, tie

    public static let tieMargin = 0.5

    /// - Parameters: my clock, my crashes and whether I delivered; and the other player.
    public static func decide(myTime: Double, myCrashes: Int, iFinished: Bool, rival: RivalState) -> RaceOutcome? {
        let mine = myTime + Double(myCrashes) * Duel.crashPenalty
        switch (iFinished, rival.finished) {
        case (true, true):
            if abs(mine - rival.total) < tieMargin { return .tie }
            return mine < rival.total ? .won : .lost
        case (true, false): return rival.quit ? .won : nil   // still waiting for them
        case (false, true): return .lost
        case (false, false): return rival.quit ? nil : nil
        }
    }
}

/// What the game says about the other truck during the race.
public struct RaceAnnouncer: Sendable {
    public let rivalName: String
    public let units: UnitSystem
    private var leader = 0           // 1: you're ahead, -1: they are
    private var lastStatus = 0.0
    private var lastClose = -100.0
    private var seenCrashes = 0
    private var saidAlmostThere = false
    private var saidFinished = false
    private var saidQuit = false
    private var saidMoving = false

    /// How often the "who's ahead" update comes.
    public static let statusEvery = 60.0

    public init(rivalName: String, units: UnitSystem) {
        self.rivalName = rivalName
        self.units = units
    }

    /// - Parameters: metres I have left, the rival, my clock (seconds since I started moving).
    public mutating func update(myRemaining: Double, rival r: RivalState, time: Double) -> [String] {
        var lines: [String] = []
        let name = rivalName
        if r.quit {
            if !saidQuit { saidQuit = true; lines.append("\(name) left the race. Deliver your load to win.") }
            return lines
        }
        if r.finished {
            if !saidFinished {
                saidFinished = true
                lines.append("\(name) delivered, in \(Duel.clock(r.total)) with penalties. Finish to see who won.")
            }
            return lines
        }
        if !saidMoving, r.drivingTime > 0 { saidMoving = true; lines.append("\(name) is on the move!") }
        if r.crashes > seenCrashes {
            seenCrashes = r.crashes
            lines.append("\(name) crashed!")
        }
        // Positive gap: they're ahead.
        let gap = myRemaining - r.remaining
        let now = gap > 30 ? -1 : gap < -30 ? 1 : leader
        if leader != 0, now != leader, time > 15 {
            lines.append(now == 1 ? "You passed \(name)!" : "\(name) passed you!")
            lastStatus = time
        }
        leader = now
        if !saidAlmostThere, r.remaining < 1_500, gap > 0 {
            saidAlmostThere = true
            lines.append("\(name) is almost at the drop-off. Go faster!")
        } else if gap < -15, gap > -150, time - lastClose > 30, time - lastStatus > 10 {
            lastClose = time
            lines.append("\(name) is right behind you!")
        } else if time - lastStatus >= Self.statusEvery {
            lastStatus = time
            lines.append(status(gap: gap))
        }
        return lines
    }

    /// "You're ahead of Sam by 400 meters." Also for the dashboard.
    public func status(gap: Double) -> String {
        if abs(gap) < 30 { return "You and \(rivalName) are side by side." }
        return gap > 0 ? "\(rivalName) is \(units.distance(gap)) ahead of you."
                       : "You're ahead of \(rivalName) by \(units.distance(-gap))."
    }
}

/// The practice bot: a pretend rival that drives the route, so a race can be tried without another player.
public struct RaceBot: Sendable {
    public enum Level: String, CaseIterable, Sendable {
        case easy, normal, hard
        public var name: String { rawValue.capitalized }
        /// Average speed, m/s (about 40, 55 and 68 km/h).
        var speed: Double { [11.0, 15.0, 19.0][Level.allCases.firstIndex(of: self)!] }
    }

    public let level: Level
    public private(set) var state: RivalState
    private var rng: SeededRandom
    private var crashAt: Double?
    private var stoppedUntil = 0.0

    public static let name = "Robo Rick"

    public init(routeLength: Double, level: Level, seed: UInt64) {
        self.level = level
        state = RivalState(remaining: routeLength)
        rng = SeededRandom(seed: seed &+ 77)
        // The easy and normal bots crash once, somewhere along the way.
        if level != .hard { crashAt = Double.random(in: 60...240, using: &rng) }
    }

    /// Moves the bot on. It waits until `started` (the player has started moving), so the start is fair.
    public mutating func update(dt: Double, started: Bool) -> RivalState {
        guard started, !state.finished else { return state }
        state.drivingTime += dt
        let t = state.drivingTime
        if let c = crashAt, t >= c {
            crashAt = nil
            state.crashes += 1
            stoppedUntil = t + 8
        }
        // Speeds up and slows down along the way, like towns and curves; never faster than the limit allows.
        let target = t < stoppedUntil ? 0 : level.speed * (0.85 + 0.25 * sin(t / 23) + 0.05 * sin(t / 7))
        state.speed += (target - state.speed) * min(1, dt * 0.6)
        state.lateral = 0
        state.remaining = max(0, state.remaining - state.speed * dt)
        if state.remaining <= 0 { state.finished = true; state.speed = 0 }
        return state
    }
}
