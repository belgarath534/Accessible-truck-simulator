import Foundation

/// How the trucking world sees you. Earned by delivering well; it unlocks better work and pays a little more.
public enum ReputationLevel: Int, CaseIterable, Comparable, Sendable {
    case rookie, reliable, respected, pro, legend

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Reputation points needed.
    public var threshold: Int { [0, 100, 300, 700, 1_500][rawValue] }

    public var title: String { ["Rookie", "Reliable", "Respected", "Pro", "Legend"][rawValue] }

    /// Extra pay on every delivery.
    public var payBonus: Double { Double(rawValue) * 0.03 }

    public static func level(for points: Int) -> ReputationLevel {
        allCases.last { points >= $0.threshold } ?? .rookie
    }

    public var next: ReputationLevel? { ReputationLevel(rawValue: rawValue + 1) }

    /// What reaching this level opens up.
    public var unlocks: String? {
        switch self {
        case .rookie: return nil
        case .reliable: return "Oversize loads and company contracts are open to you, and every delivery pays 3% more."
        case .respected: return "Hazmat loads are open to you, and every delivery pays 6% more."
        case .pro: return "Contracts are bigger now, and every delivery pays 9% more."
        case .legend: return "You're a legend of the highway. Every delivery pays 12% more."
        }
    }
}

public extension CargoKind {
    /// The reputation a load needs.
    var requiredLevel: ReputationLevel {
        switch self {
        case .oversize: return .reliable
        case .hazmat: return .respected
        default: return .rookie
        }
    }
}

/// Several deliveries of one load for one client, all on time, for a big bonus.
public struct Contract: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var client: String
    public var cargoName: String
    public var total: Int
    public var done: Int
    public var bonus: Int

    public init(id: UUID = UUID(), client: String, cargoName: String, total: Int, done: Int = 0, bonus: Int) {
        self.id = id; self.client = client; self.cargoName = cargoName; self.total = total; self.done = done; self.bonus = bonus
    }

    public var cargo: Cargo { Cargo.catalog.first { $0.name == cargoName } ?? Cargo.catalog[0] }

    /// Who wants each kind of load.
    static func client(for cargo: Cargo) -> String {
        switch cargo.name {
        case "Cattle", "Chickens", "Fresh produce": return "Bayview Farms Co-op"
        case "Ice cream", "Frozen food", "Canned goods": return "Millbrook Grocers"
        case "Wind turbine blade": return "Ironton Wind Power"
        case "Fishing boat": return "Cedar Falls Boatworks"
        case "Gasoline", "Chemicals": return "Ridgeport Fuel and Chemical"
        case "Lumber", "Furniture": return "Cedar Falls Timber"
        case "Steel beams", "Gravel": return "Ironton Steel and Stone"
        case "Medical supplies": return "Bayview Hospital"
        default: return "Ridgeport Trading Company"
        }
    }
}

public extension CareerState {
    var reputationLevel: ReputationLevel { ReputationLevel.level(for: reputation) }

    /// Reputation for a finished delivery: up for delivering, on time, no crashes and a good stop; down for lateness,
    /// crashes, tickets and spills.
    static func reputationChange(job: DeliveryJob, summary: TripSummary) -> Int {
        let s = summary.stats
        if job.cargo.kind == .hazmat && s.hazmatSpilled { return -20 }
        var change = 10
        change += s.drivingTime <= job.timeLimit ? 5 : -5
        change += s.crashes == 0 ? 5 : -min(15, 3 * s.crashes)
        if summary.stopRating == .perfect { change += 3 }
        change -= 2 * s.tickets
        switch summary.dockRating {
        case .perfect: change += 5
        case .good: change += 2
        case .bumped: change -= 3
        default: break
        }
        return change
    }

    /// The delivery's pay: the usual payout, plus the reputation bonus and, when it finishes a contract, the
    /// contract bonus. Call before `completeDelivery`.
    func deliveryPayout(_ job: DeliveryJob, summary: TripSummary, weather: Weather = .clear) -> Payout {
        var payout = Payout.delivery(job, summary: summary, weather: weather)
        let spilled = job.cargo.kind == .hazmat && summary.stats.hazmatSpilled
        let level = reputationLevel
        if level.payBonus > 0 && !spilled {
            let insertAt = payout.lines.firstIndex { $0.amount < 0 && $0.label.hasPrefix("Fuel") } ?? payout.lines.endIndex
            payout.lines.insert(Payout.Line(label: "\(level.title) reputation bonus",
                                            amount: Int((Double(job.pay) * level.payBonus).rounded())), at: insertAt)
        }
        if let contract, job.contractID == contract.id, Self.countsForContract(job, summary: summary),
           contract.done + 1 >= contract.total {
            payout.lines.append(Payout.Line(label: "Contract bonus from \(contract.client)", amount: contract.bonus))
        }
        if let mission = StoryMission.withID(job.storyID), Self.countsForStory(job, summary: summary) {
            payout.lines.append(Payout.Line(label: "Story bonus: \(mission.title)", amount: mission.bonus))
        }
        return payout
    }

    static func countsForContract(_ job: DeliveryJob, summary: TripSummary) -> Bool {
        summary.stats.drivingTime <= job.timeLimit && !(job.cargo.kind == .hazmat && summary.stats.hazmatSpilled)
    }

    /// Records a finished delivery: reputation, contract progress, the move to the next town and a new job board.
    /// Returns news to tell the player (contract progress, a new reputation level).
    @discardableResult
    mutating func completeDelivery(_ job: DeliveryJob, summary: TripSummary) -> [String] {
        var news: [String] = []
        let before = reputationLevel
        var change = Self.reputationChange(job: job, summary: summary)

        if var c = contract, job.contractID == c.id {
            if Self.countsForContract(job, summary: summary) {
                c.done += 1
                if c.done >= c.total {
                    news.append("Contract complete! \(c.client) paid a \(Phrases.money(c.bonus)) bonus.")
                    change += 25
                    contract = nil
                } else {
                    news.append("Contract for \(c.client): \(c.done) of \(c.total) delivered.")
                    contract = c
                }
            } else {
                news.append("Contract broken: \(c.client) needed that load on time. No contract bonus.")
                change -= 15
                contract = nil
            }
        }

        if let mission = StoryMission.withID(job.storyID) {
            if Self.countsForStory(job, summary: summary) {
                storyProgress = max(storyProgress, mission.id)
                news.append(mission.success)
                change += 20
                if let next = StoryMission.withID(mission.id + 1) {
                    news.append("A new story mission is coming: \(next.title)" + (reputationLevel >= next.level || ReputationLevel.level(for: reputation + change) >= next.level
                        ? ". It's on the Job Board." : ", once you're \(next.level.title)."))
                } else {
                    news.append("That's the last story mission. You've finished the story!")
                }
            } else {
                news.append("\(mission.title) failed: it had to be there on time. Try it again from the Job Board.")
            }
        }

        reputation = max(0, reputation + change)
        news.insert("Reputation \(change >= 0 ? "up" : "down") \(abs(change)) points, to \(reputation).", at: 0)
        let after = reputationLevel
        if after > before {
            news.append("You're now \(after.title)! " + (after.unlocks ?? ""))
        } else if after < before {
            news.append("Your reputation dropped to \(after.title).")
        }
        completeJob(job)
        return news
    }

    /// Takes the offered contract; its first job goes on the board.
    mutating func acceptContract() {
        guard contract == nil, let offer = contractOffer else { return }
        contract = offer
        contractOffer = nil
        refreshBoard()
    }

    /// Gives up the current contract (costs reputation).
    mutating func abandonContract() {
        guard contract != nil else { return }
        contract = nil
        reputation = max(0, reputation - 15)
        refreshBoard()
    }

    /// A new contract offer, when the player has the reputation for one.
    static func makeOffer<R: RandomNumberGenerator>(using rng: inout R, level: ReputationLevel) -> Contract? {
        guard level >= .reliable else { return nil }
        let choices = Cargo.catalog.filter { $0.kind.requiredLevel <= level }
        guard let cargo = choices.randomElement(using: &rng) else { return nil }
        let total = level >= .pro ? 4 : 3
        let bonus = Int((cargo.ratePerKm * 10 * Double(total) / 100).rounded()) * 100
        return Contract(client: Contract.client(for: cargo), cargoName: cargo.name, total: total, bonus: bonus)
    }
}
