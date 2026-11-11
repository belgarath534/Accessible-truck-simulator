import BeatCore
import Foundation

/// Player choices and best scores, saved on the phone.
@MainActor
final class GameSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var difficulty: Difficulty { didSet { defaults.set(difficulty.rawValue, forKey: "difficulty") } }
    /// Extra delay between the sound and your touch, seconds (from calibration). Bluetooth headphones need more.
    @Published var calibration: Double { didSet { defaults.set(calibration, forKey: "calibration") } }
    @Published var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    /// Speak "Perfect", "Good" or "Miss" now and then (off: sounds and vibration only).
    @Published var hitSounds: Bool { didSet { defaults.set(hitSounds, forKey: "hitSounds") } }

    init() {
        difficulty = Difficulty(rawValue: defaults.string(forKey: "difficulty") ?? "") ?? .easy
        calibration = defaults.double(forKey: "calibration")
        haptics = defaults.object(forKey: "haptics") as? Bool ?? true
        hitSounds = defaults.object(forKey: "hitSounds") as? Bool ?? true
    }

    private func key(_ song: Song, _ d: Difficulty) -> String { "best.\(song.id).\(d.rawValue)" }

    func best(_ song: Song, _ d: Difficulty) -> Int { defaults.integer(forKey: key(song, d)) }

    /// Saves the score if it's a new best. Returns true when it is.
    @discardableResult
    func recordScore(_ score: Int, song: Song, difficulty d: Difficulty) -> Bool {
        guard score > best(song, d) else { return false }
        defaults.set(score, forKey: key(song, d))
        objectWillChange.send()
        return true
    }
}
