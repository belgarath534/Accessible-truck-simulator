import Foundation

/// What kind of load a job is. Raw values are saved: never change them.
public enum CargoKind: String, Codable, CaseIterable, Sendable {
    /// Ordinary freight.
    case standard
    /// Animals: they hate hard braking and fast curves. You hear them in the trailer.
    case livestock
    /// A refrigerated trailer: the cooling unit hums, and the load spoils if you're late.
    case refrigerated
    /// A wide load: keep under the oversize speed limit.
    case oversize
    /// Hazardous materials: the biggest pay, but one crash spills the load.
    case hazmat

    /// Said on the job board ("livestock").
    public var label: String? {
        switch self {
        case .standard: return nil
        case .livestock: return "livestock"
        case .refrigerated: return "refrigerated"
        case .oversize: return "oversize load"
        case .hazmat: return "hazmat"
        }
    }
}

public extension DrivingSession {
    /// Top speed for an oversize load, m/s (45 mph).
    static let oversizeSpeedLimit = 45 / 2.236_94
    /// Braking harder than this at speed scares livestock.
    static let livestockHardBrake = 0.75
    /// Cleanup bill when a hazmat load spills.
    static let hazmatCleanupCost = 1_000
}

public extension Payout {
    /// Each scare, oversize warning: this much of the base pay, up to `specialCargoMaxCut`.
    static let specialCargoCutPerEvent = 0.05
    static let specialCargoMaxCut = 0.30
    /// A refrigerated load that arrives late has spoiled: this much more off the pay.
    static let spoiledCut = 0.25

    /// The lines special cargo adds to a delivery (or nil, for a hazmat spill, which replaces the whole payout).
    static func specialCargoLines(_ job: DeliveryJob, stats: TripStats, late: Bool) -> [Line] {
        let base = Double(job.pay)
        func cut(_ n: Int) -> Int { -Int((base * min(specialCargoMaxCut, Double(n) * specialCargoCutPerEvent)).rounded()) }
        switch job.cargo.kind {
        case .livestock where stats.livestockScares > 0:
            return [Line(label: "Stressed animals, scared \(stats.livestockScares) time\(stats.livestockScares == 1 ? "" : "s")",
                         amount: cut(stats.livestockScares))]
        case .oversize where stats.oversizeWarnings > 0:
            return [Line(label: "Wide load driven too fast, \(stats.oversizeWarnings) warning\(stats.oversizeWarnings == 1 ? "" : "s")",
                         amount: cut(stats.oversizeWarnings))]
        case .refrigerated where late:
            return [Line(label: "Spoiled cargo", amount: -Int((base * spoiledCut).rounded()))]
        default:
            return []
        }
    }
}
