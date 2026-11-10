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
    /// Livestock, refrigerated, oversize, hazmat, or ordinary freight.
    public var kind: CargoKind

    public init(name: String, massKg: Double, ratePerKm: Double, fragile: Bool = false, urgent: Bool = false,
                kind: CargoKind = .standard) {
        self.name = name
        self.massKg = massKg
        self.ratePerKm = ratePerKm
        self.fragile = fragile
        self.urgent = urgent
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey { case name, massKg, ratePerKm, fragile, urgent, kind }

    /// Jobs saved before special cargo get their kind from the catalog.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .name)
        self.name = name
        massKg = try c.decode(Double.self, forKey: .massKg)
        ratePerKm = try c.decode(Double.self, forKey: .ratePerKm)
        fragile = try c.decode(Bool.self, forKey: .fragile)
        urgent = try c.decode(Bool.self, forKey: .urgent)
        let saved = try c.decodeIfPresent(CargoKind.self, forKey: .kind)
        kind = saved ?? Cargo.catalog.first { $0.name == name }?.kind ?? .standard
    }

    public static let catalog: [Cargo] = [
        Cargo(name: "Furniture", massKg: 6_000, ratePerKm: 110),
        Cargo(name: "Frozen food", massKg: 14_000, ratePerKm: 145, urgent: true, kind: .refrigerated),
        Cargo(name: "Steel beams", massKg: 24_000, ratePerKm: 170),
        Cargo(name: "Electronics", massKg: 5_000, ratePerKm: 150, fragile: true),
        Cargo(name: "Lumber", massKg: 18_000, ratePerKm: 130),
        Cargo(name: "Glassware", massKg: 4_000, ratePerKm: 160, fragile: true),
        Cargo(name: "Gravel", massKg: 25_000, ratePerKm: 120),
        Cargo(name: "Medical supplies", massKg: 3_000, ratePerKm: 165, fragile: true, urgent: true),
        Cargo(name: "Canned goods", massKg: 12_000, ratePerKm: 115),
        Cargo(name: "Fresh produce", massKg: 10_000, ratePerKm: 140, urgent: true, kind: .refrigerated),
        // Special cargo
        Cargo(name: "Cattle", massKg: 16_000, ratePerKm: 175, kind: .livestock),
        Cargo(name: "Chickens", massKg: 7_000, ratePerKm: 150, kind: .livestock),
        Cargo(name: "Ice cream", massKg: 11_000, ratePerKm: 165, urgent: true, kind: .refrigerated),
        Cargo(name: "Wind turbine blade", massKg: 19_000, ratePerKm: 210, kind: .oversize),
        Cargo(name: "Fishing boat", massKg: 9_000, ratePerKm: 190, kind: .oversize),
        Cargo(name: "Gasoline", massKg: 22_000, ratePerKm: 240, kind: .hazmat),
        Cargo(name: "Chemicals", massKg: 15_000, ratePerKm: 230, fragile: true, kind: .hazmat),
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
    /// The contract this job is part of, if any.
    public var contractID: UUID?
    /// The story mission this job is, if any.
    public var storyID: Int?
    /// A road on the way closed for repairs (map edge index): the job's distance includes the detour.
    public var closedRoad: Int?
    /// A tow call (tow truck only): where the stranded car is.
    public var tow: TowCall?
    /// Map town ids (nil for jobs from before the map).
    public var origin: String?
    public var destination: String?

    public init(id: UUID = UUID(), cargo: Cargo, distance: Double, pay: Int, timeLimit: Double,
                origin: String? = nil, destination: String? = nil) {
        self.id = id
        self.cargo = cargo
        self.distance = distance
        self.pay = pay
        self.timeLimit = timeLimit
        self.origin = origin
        self.destination = destination
    }

    public var destinationName: String? { destination.flatMap { WorldMap.standard.node($0)?.name } }
    public var originName: String? { origin.flatMap { WorldMap.standard.node($0)?.name } }

    public var goal: TripGoal {
        .destination(name: destinationName.map { "\(cargo.name) to \($0)" } ?? "\(cargo.name) delivery", distance: distance)
    }
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

    /// A job from `origin` to another town. Cargo is usually something the origin town ships, and only what the
    /// player's reputation allows. `cargo` forces the load (contract jobs).
    public static func makeJob<R: RandomNumberGenerator>(using rng: inout R, map: WorldMap = .standard,
                                                        from origin: String, level: ReputationLevel = .legend,
                                                        cargo forced: Cargo? = nil) -> DeliveryJob {
        let others = map.towns.filter { $0.id != origin }
        let destination = others.randomElement(using: &rng)!
        let exports = map.node(origin)?.exports ?? []
        let allowed = Cargo.catalog.filter { $0.kind.requiredLevel <= level }
        let local = allowed.filter { exports.contains($0.name) }
        let cargo = forced ?? (!local.isEmpty && Double.random(in: 0...1, using: &rng) < 0.7 ? local : allowed)
            .randomElement(using: &rng)!
        var distance = map.route(from: origin, to: destination.id).map(map.length(of:)) ?? 10_000
        // Now and then a road on the way is closed for repairs: the job goes around it.
        var closedRoad: Int?
        if Double.random(in: 0...1, using: &rng) < detourChance, let r = map.route(from: origin, to: destination.id), r.count > 2 {
            for candidate in r.dropFirst().dropLast().shuffled(using: &rng) {
                if let detour = map.route(from: origin, to: destination.id, avoiding: [candidate.index]),
                   map.length(of: detour) <= min(distance * 2, 32_000) {
                    closedRoad = candidate.index
                    distance = map.length(of: detour)
                    break
                }
            }
        }
        let pay = Int((distance / 1_000 * cargo.ratePerKm / 10).rounded()) * 10
        let slack = cargo.urgent ? 1.35 : 1.7
        let timeLimit = ((distance / fairSpeed * slack + 120) / 60).rounded(.up) * 60
        var job = DeliveryJob(cargo: cargo, distance: distance, pay: pay, timeLimit: timeLimit,
                              origin: origin, destination: destination.id)
        job.closedRoad = closedRoad
        return job
    }

    /// Share of jobs with a road closed on the way.
    public static let detourChance = 0.2

    public static func makeBoard<R: RandomNumberGenerator>(using rng: inout R, map: WorldMap = .standard,
                                                          from origin: String, level: ReputationLevel = .legend,
                                                          contract: Contract? = nil) -> [DeliveryJob] {
        var jobs: [DeliveryJob] = []
        // The current contract's next load comes first.
        if let contract {
            var job = makeJob(using: &rng, map: map, from: origin, level: level, cargo: contract.cargo)
            job.contractID = contract.id
            jobs.append(job)
        }
        var tries = 0
        while jobs.count < size {
            let job = makeJob(using: &rng, map: map, from: origin, level: level)
            tries += 1
            // Keep the board varied: different cargo and, where possible, different destinations.
            let sameCargo = jobs.contains { $0.cargo == job.cargo }
            let sameTown = jobs.contains { $0.destination == job.destination }
            if !sameCargo && (!sameTown || tries > 30) { jobs.append(job) }
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
        public init(label: String, amount: Int) { self.label = label; self.amount = amount }
    }

    public var lines: [Line]
    /// Things to tell the player after the pay (reputation, contracts).
    public var news: [String] = []

    public init(lines: [Line]) { self.lines = lines }
    /// Can be negative: a drive with fuel or tow costs and no pay (practice) costs money.
    public var total: Int { lines.reduce(0) { $0 + $1.amount } }

    /// Fuel bought at truck stops and tows during a drive.
    public static func expenses(_ stats: TripStats) -> [Line] {
        var lines: [Line] = []
        if stats.fuelCost > 0 {
            lines.append(Line(label: "Fuel at truck stops", amount: -stats.fuelCost))
        }
        if stats.ticketCost > 0 {
            lines.append(Line(label: "Speeding ticket\(stats.tickets == 1 ? "" : "s, \(stats.tickets)")", amount: -stats.ticketCost))
        }
        if stats.tollCost > 0 {
            lines.append(Line(label: "Tolls", amount: -stats.tollCost))
        }
        if stats.weighStationFines > 0 {
            lines.append(Line(label: "Weigh station fine", amount: -stats.weighStationFines))
        }
        if stats.repairCost > 0 {
            lines.append(Line(label: "Roadside tire change", amount: -stats.repairCost))
        }
        if stats.towCost > 0 {
            lines.append(Line(label: "Tow truck\(stats.tows == 1 ? "" : ", \(stats.tows) times")", amount: -stats.towCost))
        }
        return lines
    }

    /// Practice pays nothing; this is only its costs, or nil if there were none.
    public static func practice(_ stats: TripStats) -> Payout? {
        let lines = expenses(stats)
        return lines.isEmpty ? nil : Payout(lines: lines)
    }

    /// Free Drive pays a small amount per kilometre: steady but slow money.
    public static let freeDriveRatePerKm = 35.0
    /// Each crash costs this much in repairs.
    public static let repairCost = 150

    public static func freeDrive(_ stats: TripStats) -> Payout {
        let pay = Int((stats.distance / 1_000 * freeDriveRatePerKm).rounded())
        var lines = [Line(label: "Driving pay", amount: pay)]
        if let turbo = turboBonus(stats) { lines.append(turbo) }
        if stats.crashes > 0 {
            // Repairs never cost more than the drive earned.
            lines.append(Line(label: "Repairs for \(stats.crashes) crash\(stats.crashes == 1 ? "" : "es")",
                              amount: -min(pay, repairCost * stats.crashes)))
        }
        return Payout(lines: lines + expenses(stats))
    }

    public static func delivery(_ job: DeliveryJob, summary: TripSummary, weather: Weather = .clear) -> Payout {
        let base = job.pay
        var lines = [Line(label: "Delivery pay", amount: base)]
        if weather.payBonus > 0 {
            lines.append(Line(label: weather == .storm ? "Storm bonus" : (weather == .snow ? "Snow bonus" : "Rain bonus"),
                              amount: Int((Double(base) * weather.payBonus).rounded())))
        }
        let stats = summary.stats

        // A hazmat spill loses the load: no pay or bonuses, and a cleanup bill.
        if job.cargo.kind == .hazmat && stats.hazmatSpilled {
            return Payout(lines: [Line(label: "Load lost in a hazmat spill", amount: 0),
                                  Line(label: "Hazmat cleanup", amount: -DrivingSession.hazmatCleanupCost)] + expenses(stats))
        }

        let late = stats.drivingTime - job.timeLimit
        lines += specialCargoLines(job, stats: stats, late: late > 0)
        if late > 0 {
            let minutes = Int((late / 60).rounded(.up))
            let fraction = min(0.5, Double(minutes) * 0.03)
            lines.append(Line(label: "Late by \(minutes) minute\(minutes == 1 ? "" : "s")",
                              amount: -Int((Double(base) * fraction).rounded())))
        } else {
            lines.append(Line(label: "On-time bonus", amount: Int((Double(base) * 0.10).rounded())))
        }

        if stats.crashes > 0 {
            let perCrash = job.cargo.fragile ? 0.10 : 0.05
            let fraction = min(0.4, Double(stats.crashes) * perCrash)
            lines.append(Line(label: "Cargo damage from \(stats.crashes) crash\(stats.crashes == 1 ? "" : "es")",
                              amount: -Int((Double(base) * fraction).rounded())))
        } else {
            lines.append(Line(label: "No-crash bonus", amount: Int((Double(base) * 0.10).rounded())))
        }

        if summary.stopRating == .perfect {
            lines.append(Line(label: "Perfect stop bonus", amount: Int((Double(base) * 0.05).rounded())))
        }
        if let turbo = turboBonus(stats) { lines.append(turbo) }
        if let dock = dockingLine(summary.dockRating, pay: base) { lines.append(dock) }
        return Payout(lines: lines + expenses(stats))
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
    /// Litres in each truck's tank, by truck id (missing = full).
    public var fuel: [String: Double]
    /// The town the truck is parked in (map town id).
    public var currentTown: String
    /// Your hired drivers, and drivers looking for work.
    public var drivers: [Driver]
    public var candidates: [Driver]
    /// Achievement ids earned (see Achievement), in the order they were earned.
    public var achievements: [String]
    /// Towns the truck has been to (for the Seen It All achievement).
    public var visitedTowns: [String]
    /// A drive saved part-way, to continue later.
    public var savedDrive: SavedDrive?
    /// Your company's name (nil until you pick one).
    public var companyName: String?
    /// Names you gave your trucks, by truck id.
    public var truckNames: [String: String] = [:]
    /// Horns bought at the horn shop (the air horn is free and not listed).
    public var ownedHorns: [String] = []
    public var selectedHorn: String = Horn.air.rawValue
    /// Snow chains, for every truck.
    public var hasChains = false
    /// Towns with a depot of yours (cheap fuel, better-paying jobs).
    public var depots: [String] = []
    /// The weekly challenge: which week, progress, whether the prize was paid, and how many were won.
    public var weeklyWeek = 0
    public var weeklyCount = 0
    public var weeklyClaimed = false
    public var weeklyChallengesWon = 0
    /// What you still owe the bank, dollars.
    public var loanOwed = 0
    /// Each truck's condition (percent), by truck id; missing means 100.
    public var truckCondition: [String: Double] = [:]
    /// Fastest speed reached in Turbo Mode, m/s (for the Top Speed leaderboard).
    public var bestTurboSpeed: Double = 0
    /// Reputation points (see ReputationLevel).
    public var reputation: Int = 0
    /// The contract being worked on, and one on offer.
    public var contract: Contract?
    public var contractOffer: Contract?
    /// Story missions finished, in order.
    public var storyProgress: Int = 0
    /// Hired drivers' trucks can break down (not saved; tests that count deliveries turn it off).
    public var driverBreakdowns = true
    public static let homeTown = "millbrook"

    /// Dollars per litre to fill up at your own yard (truck stops are cheaper).
    public static let yardFuelPrice = 3.0

    public static let startingMoney = 500

    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        money = CareerState.startingMoney
        jobsCompleted = 0
        kilometersDriven = 0
        totalEarned = 0
        self.seed = seed
        currentTown = CareerState.homeTown
        var rng = SeededRandom(seed: seed)
        jobBoard = JobBoard.makeBoard(using: &rng, from: CareerState.homeTown, level: .rookie)
        ownedTrucks = [TruckSpec.starter.id]
        selectedTruck = TruckSpec.starter.id
        upgrades = [:]
        fuel = [:]
        drivers = []
        candidates = Company.candidates(using: &rng)
        achievements = []
        visitedTowns = [CareerState.homeTown]
    }

    // Saves from before the garage existed have no truck fields: give them the starter truck.
    enum CodingKeys: String, CodingKey {
        case money, jobsCompleted, kilometersDriven, totalEarned, jobBoard, seed, ownedTrucks, selectedTruck, upgrades, fuel, currentTown, drivers, candidates, achievements, visitedTowns, savedDrive
        case companyName, truckNames, ownedHorns, selectedHorn, bestTurboSpeed, hasChains, truckCondition, depots, loanOwed
        case weeklyWeek, weeklyCount, weeklyClaimed, weeklyChallengesWon
        case reputation, contract, contractOffer, storyProgress
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
        fuel = try c.decodeIfPresent([String: Double].self, forKey: .fuel) ?? [:]
        currentTown = try c.decodeIfPresent(String.self, forKey: .currentTown) ?? CareerState.homeTown
        drivers = try c.decodeIfPresent([Driver].self, forKey: .drivers) ?? []
        if let saved = try c.decodeIfPresent([Driver].self, forKey: .candidates), !saved.isEmpty {
            candidates = saved
        } else {
            var rng = SeededRandom(seed: seed &+ 99)
            candidates = Company.candidates(using: &rng)
        }
        achievements = try c.decodeIfPresent([String].self, forKey: .achievements) ?? []
        savedDrive = try c.decodeIfPresent(SavedDrive.self, forKey: .savedDrive)
        companyName = try c.decodeIfPresent(String.self, forKey: .companyName)
        truckNames = try c.decodeIfPresent([String: String].self, forKey: .truckNames) ?? [:]
        ownedHorns = try c.decodeIfPresent([String].self, forKey: .ownedHorns) ?? []
        selectedHorn = try c.decodeIfPresent(String.self, forKey: .selectedHorn) ?? Horn.air.rawValue
        bestTurboSpeed = try c.decodeIfPresent(Double.self, forKey: .bestTurboSpeed) ?? 0
        hasChains = try c.decodeIfPresent(Bool.self, forKey: .hasChains) ?? false
        truckCondition = try c.decodeIfPresent([String: Double].self, forKey: .truckCondition) ?? [:]
        depots = try c.decodeIfPresent([String].self, forKey: .depots) ?? []
        loanOwed = try c.decodeIfPresent(Int.self, forKey: .loanOwed) ?? 0
        weeklyWeek = try c.decodeIfPresent(Int.self, forKey: .weeklyWeek) ?? 0
        weeklyCount = try c.decodeIfPresent(Int.self, forKey: .weeklyCount) ?? 0
        weeklyClaimed = try c.decodeIfPresent(Bool.self, forKey: .weeklyClaimed) ?? false
        weeklyChallengesWon = try c.decodeIfPresent(Int.self, forKey: .weeklyChallengesWon) ?? 0
        // Saves from before reputation: credit the deliveries already made.
        reputation = try c.decodeIfPresent(Int.self, forKey: .reputation) ?? jobsCompleted * 15
        contract = try c.decodeIfPresent(Contract.self, forKey: .contract)
        contractOffer = try c.decodeIfPresent(Contract.self, forKey: .contractOffer)
        storyProgress = try c.decodeIfPresent(Int.self, forKey: .storyProgress) ?? 0
        visitedTowns = try c.decodeIfPresent([String].self, forKey: .visitedTowns)
            ?? Array(Set([CareerState.homeTown, currentTown])).sorted()
        // Jobs saved before the map (or from another town) are replaced with jobs from here.
        if jobBoard.contains(where: { $0.origin != currentTown }) { refreshBoard() }
    }

    /// Roughly how many litres a trip needs: heavier cargo burns more (measured: a 24-tonne load about 25 percent
    /// more), plus a 15 percent margin.
    public static func fuelNeeded(forDistance metres: Double, cargoKg: Double = 0) -> Double {
        metres * DrivingSession.typicalFuelPerMetre * (1 + cargoKg / 80_000) * 1.15
    }

    /// Litres in the selected truck's tank.
    public func fuelLiters(for truck: TruckSpec) -> Double {
        min(fuel[truck.id] ?? .infinity, truck.upgraded(upgradeLevels(for: truck)).fuelCapacityLiters)
    }

    public mutating func setFuel(_ liters: Double, for truck: TruckSpec) {
        fuel[truck.id] = max(0, liters)
    }

    /// Cost to fill a truck at the yard.
    public func yardFillCost(for truck: TruckSpec) -> Int {
        let capacity = truck.upgraded(upgradeLevels(for: truck)).fuelCapacityLiters
        return Int(((capacity - fuelLiters(for: truck)) * fuelPriceHere).rounded())
    }

    /// Fills the tank at the yard. Returns false if there isn't enough money (fills what you can afford).
    @discardableResult
    public mutating func fillAtYard(_ truck: TruckSpec) -> Bool {
        let capacity = truck.upgraded(upgradeLevels(for: truck)).fuelCapacityLiters
        let current = fuelLiters(for: truck)
        let affordable = Double(max(0, money)) / fuelPriceHere
        let liters = min(capacity - current, affordable)
        money -= Int((liters * fuelPriceHere).rounded())
        fuel[truck.id] = current + liters
        return current + liters >= capacity - 0.01
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
        let wasTow = TruckSpec.withID(selectedTruck).isTowTruck
        selectedTruck = truck.id
        if wasTow != truck.isTowTruck { refreshBoard() }
        return .bought
    }

    /// Picks an owned truck to drive. Returns false if it isn't owned.
    @discardableResult
    public mutating func select(_ truck: TruckSpec) -> Bool {
        guard owns(truck) else { return false }
        // If a driver has that truck, they swap to the one you were driving.
        if let i = drivers.firstIndex(where: { $0.truckID == truck.id }) {
            _ = updateDrivers()
            drivers[i].truckID = selectedTruck
            drivers[i].progress = 0
        }
        let wasTow = TruckSpec.withID(selectedTruck).isTowTruck
        selectedTruck = truck.id
        // Tow calls or freight: the board follows the truck.
        if wasTow != truck.isTowTruck { refreshBoard() }
        return true
    }

    /// Adds a drive's earnings and distance.
    public mutating func record(_ payout: Payout, distance: Double) {
        money += payout.total
        totalEarned += payout.total
        kilometersDriven += distance / 1_000
    }

    /// Removes a finished job and puts a new one on the board.
    /// Delivering a job moves you to its destination town, where there are new jobs.
    public mutating func completeJob(_ job: DeliveryJob) {
        jobsCompleted += 1
        if let destination = job.destination { currentTown = destination }
        visit(currentTown)
        refreshBoard()
    }

    /// Moves to a town (after a Free Drive) and refreshes the jobs there.
    public mutating func move(to town: String) {
        guard town != currentTown, WorldMap.standard.node(town)?.isTown == true else { return }
        currentTown = town
        visit(town)
        refreshBoard()
    }

    private mutating func visit(_ town: String) {
        if !visitedTowns.contains(town) { visitedTowns.append(town) }
    }

    /// A whole new set of jobs from the current town.
    public mutating func refreshBoard() {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        var rng = SeededRandom(seed: seed)
        if TruckSpec.withID(selectedTruck).isTowTruck {
            // The tow truck takes tow calls instead of freight.
            jobBoard = (0..<JobBoard.size).map { _ in JobBoard.makeTowJob(using: &rng, from: currentTown) }
            return
        }
        jobBoard = JobBoard.makeBoard(using: &rng, from: currentTown, level: reputationLevel, contract: contract)
        // The next story mission goes on the board in its own town.
        if let mission = nextStoryMission, mission.from == currentTown {
            jobBoard.insert(mission.job(), at: 0)
        }
        if contract == nil && contractOffer == nil {
            contractOffer = CareerState.makeOffer(using: &rng, level: reputationLevel)
        }
    }

    public var currentTownName: String { WorldMap.standard.node(currentTown)?.name ?? "Millbrook" }
}
