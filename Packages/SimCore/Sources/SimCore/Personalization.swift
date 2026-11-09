import Foundation

/// Horns from the horn shop. Raw values are saved: never change them.
public enum Horn: String, CaseIterable, Codable, Sendable {
    case air, train, ship, musical, twin

    public var title: String {
        switch self {
        case .air: return "Air horn"
        case .train: return "Train horn"
        case .ship: return "Ship horn"
        case .musical: return "Musical horn"
        case .twin: return "Twin trumpet horn"
        }
    }

    public var detail: String {
        switch self {
        case .air: return "The classic truck air horn. Comes with every truck."
        case .train: return "A deep, five-chime locomotive horn. Deer don't stand a chance."
        case .ship: return "A huge, low foghorn, like a cargo ship leaving Ridgeport."
        case .musical: return "Plays a cheerful little tune. Other drivers will smile. Probably."
        case .twin: return "Two loud, bright trumpets, like an old highway hauler."
        }
    }

    public var price: Int {
        switch self {
        case .air: return 0
        case .twin: return 800
        case .musical: return 1_200
        case .ship: return 2_000
        case .train: return 3_500
        }
    }

    /// The recording's file name.
    public var soundFile: String { self == .air ? "horn" : "horn_" + rawValue }
}

public extension CareerState {
    /// Longest name allowed for a truck or company.
    static let maxNameLength = 30

    /// Tidies a typed name: trims spaces, drops line breaks, limits the length. Empty means no name.
    static func cleanName(_ raw: String) -> String? {
        let one = raw.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = one.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNameLength))
    }

    var horn: Horn { Horn(rawValue: selectedHorn) ?? .air }

    func ownsHorn(_ horn: Horn) -> Bool { horn == .air || ownedHorns.contains(horn.rawValue) }

    /// Buys a horn and puts it on (every truck shares it).
    @discardableResult
    mutating func buyHorn(_ horn: Horn) -> PurchaseResult {
        if ownsHorn(horn) { return .alreadyOwned }
        guard money >= horn.price else { return .notEnoughMoney(short: horn.price - money) }
        money -= horn.price
        ownedHorns.append(horn.rawValue)
        selectedHorn = horn.rawValue
        return .bought
    }

    @discardableResult
    mutating func selectHorn(_ horn: Horn) -> Bool {
        guard ownsHorn(horn) else { return false }
        selectedHorn = horn.rawValue
        return true
    }

    /// The name you gave a truck, if any.
    func nickname(for truck: TruckSpec) -> String? { truckNames[truck.id] }

    /// "Big Bertha, your Road King", or just "Road King".
    func displayName(for truck: TruckSpec) -> String {
        nickname(for: truck).map { "\($0), your \(truck.name)" } ?? truck.name
    }

    mutating func setNickname(_ name: String, for truck: TruckSpec) {
        truckNames[truck.id] = CareerState.cleanName(name)
    }

    mutating func setCompanyName(_ name: String) {
        companyName = CareerState.cleanName(name)
    }

    /// The company's name, or a default.
    var companyDisplayName: String { companyName ?? "Your Trucking Company" }
}
