import Foundation

/// Turbo Mode: a switch before a drive. No speed governor, a huge power boost (toward 200 mph), speed called out
/// as you climb, no police, much faster fuel burn, and a bonus for top speed on top of the normal pay.
public extension DrivingSession {
    /// Extra power in Turbo Mode, watts. With a truck's drag this tops out a little under 200 mph.
    static let turboPowerW = 2_400_000.0
    /// Fuel burns this many times faster in Turbo Mode.
    static let turboFuelMultiplier = 3.0
    /// Speed is called out every 25 mph from 75 mph up.
    static let turboCalloutStep = 25 / 2.236_94
    static let turboCalloutStart = 75 / 2.236_94
}

public extension Payout {
    /// Dollars for each mph of top speed above 75 mph in Turbo Mode.
    static let turboBonusPerMph = 12.0
    /// Each crash cuts the speed bonus by a quarter.
    static let turboCrashCut = 0.25

    /// The Turbo Mode speed bonus for a drive, if it earned one.
    static func turboBonus(_ stats: TripStats) -> Line? {
        guard stats.turbo else { return nil }
        let mph = stats.topSpeed * 2.236_94
        guard mph > 75 else { return nil }
        let keep = max(0, 1 - turboCrashCut * Double(stats.crashes))
        let amount = Int(((mph - 75) * turboBonusPerMph * keep).rounded())
        guard amount > 0 else { return nil }
        return Line(label: "Turbo speed bonus, top speed \(Int(mph.rounded())) mph", amount: amount)
    }
}
