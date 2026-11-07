import Foundation

/// Simple, leveled truck upgrades. Players see "Engine level 2", never gear ratios.
public enum UpgradeKind: String, CaseIterable, Codable, Sendable {
    case engine, brakes, tires, fuelTank

    public static let maxLevel = 3

    public var name: String {
        switch self {
        case .engine: return "Engine"
        case .brakes: return "Brakes"
        case .tires: return "Tires"
        case .fuelTank: return "Fuel tank"
        }
    }

    /// Price of each level (index 0 = level 1).
    public var prices: [Int] {
        switch self {
        case .engine: return [2_000, 4_500, 8_000]
        case .brakes: return [1_200, 2_500, 5_000]
        case .tires: return [1_000, 2_200, 4_500]
        case .fuelTank: return [800, 1_800, 3_500]
        }
    }

    /// Price of the level after `current`, or nil if already maxed.
    public func price(after current: Int) -> Int? {
        current < UpgradeKind.maxLevel ? prices[current] : nil
    }

    /// What one level does, for the garage.
    public var effect: String {
        switch self {
        case .engine: return "12 percent more power per level, and a bigger, deeper engine sound with more turbo"
        case .brakes: return "10 percent stronger brakes per level, so you stop shorter, especially with heavy loads"
        case .tires: return "8 percent more grip in curves per level"
        case .fuelTank: return "25 percent bigger fuel tank per level"
        }
    }
}

/// Upgrade levels for one truck.
public struct UpgradeLevels: Codable, Equatable, Sendable {
    public var levels: [String: Int] = [:]

    public init() {}

    public subscript(kind: UpgradeKind) -> Int {
        get { levels[kind.rawValue] ?? 0 }
        set { levels[kind.rawValue] = min(UpgradeKind.maxLevel, max(0, newValue)) }
    }
}

public extension TruckSpec {
    /// This truck with upgrades applied.
    func upgraded(_ u: UpgradeLevels) -> TruckSpec {
        var t = self
        let engine = Double(u[.engine]), brakes = Double(u[.brakes])
        let tires = Double(u[.tires]), tank = Double(u[.fuelTank])
        let power = 1 + 0.12 * engine
        t.torqueCurve = torqueCurve.map { TorquePoint(rpm: $0.rpm, torque: $0.torque * power) }
        t.tractionLimitAccel = tractionLimitAccel * (1 + 0.05 * tires)
        t.maxBrakeDecel = maxBrakeDecel * (1 + 0.10 * brakes)
        t.steeringLatAccel = steeringLatAccel * (1 + 0.08 * tires)
        t.fuelCapacityLiters = fuelCapacityLiters * (1 + 0.25 * tank)
        // A bigger engine sounds bigger.
        t.sound.pitch = sound.pitch * (1 - 0.03 * engine)
        t.sound.turbo = min(1, sound.turbo + 0.15 * engine)
        t.sound.bark = min(1, sound.bark + 0.08 * engine)
        return t
    }
}
