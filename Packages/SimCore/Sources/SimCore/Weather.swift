import Foundation

/// The weather for one drive. Rain and storms make the road slippery: less grip in curves, longer braking,
/// and lower suggested curve speeds. Deliveries in bad weather pay a bonus.
public enum Weather: String, CaseIterable, Codable, Sendable {
    case clear, rain, storm, snow

    /// Tyre grip compared with a dry road (curves).
    public var grip: Double {
        switch self {
        case .clear: return 1
        case .rain: return 0.82
        case .storm: return 0.7
        case .snow: return 0.55
        }
    }

    /// Braking compared with a dry road.
    public var braking: Double {
        switch self {
        case .clear: return 1
        case .rain: return 0.85
        case .storm: return 0.75
        case .snow: return 0.6
        }
    }

    /// Extra pay for a delivery, as a fraction of the job's pay.
    public var payBonus: Double {
        switch self {
        case .clear: return 0
        case .rain: return 0.10
        case .storm: return 0.20
        case .snow: return 0.30
        }
    }

    /// Snow falls from November to February.
    public static func isWinter(month: Int) -> Bool { [11, 12, 1, 2].contains(month) }

    /// The weather for a drive in a given month: snow some days in winter.
    public static func random<R: RandomNumberGenerator>(using rng: inout R, month: Int) -> Weather {
        guard isWinter(month: month) else { return random(using: &rng) }
        let r = Double.random(in: 0...1, using: &rng)
        return r < 0.5 ? .clear : (r < 0.65 ? .rain : (r < 0.75 ? .storm : .snow))
    }

    /// Mostly clear, sometimes rain, now and then a storm.
    public static func random<R: RandomNumberGenerator>(using rng: inout R) -> Weather {
        let r = Double.random(in: 0...1, using: &rng)
        return r < 0.65 ? .clear : (r < 0.9 ? .rain : .storm)
    }

    /// Said at the start of a drive (nothing for clear weather).
    public var announcement: String? {
        switch self {
        case .clear: return nil
        case .rain: return "It's raining. The road is slippery: take curves slower and leave more room to brake. Deliveries pay 10 percent extra in the rain."
        case .storm: return "A storm is rolling in: heavy rain and thunder. The road is very slippery: take curves much slower and brake early. Deliveries pay 20 percent extra in a storm."
        case .snow: return "It's snowing, and the road is icy: the most slippery it gets. Take curves very slowly and brake long before you need to. Deliveries pay 30 percent extra in the snow."
        }
    }

    public var spokenName: String {
        switch self {
        case .clear: return "clear"
        case .rain: return "raining"
        case .storm: return "stormy"
        case .snow: return "snowing"
        }
    }
}
