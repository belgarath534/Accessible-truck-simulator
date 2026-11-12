import FlightCore
import Foundation

enum ControlMode: String, CaseIterable {
    /// Hold the phone like a yoke: tilt back to climb, forward to dive, turn it like a wheel to bank.
    case tilt
    /// No tilting: a finger on the left half of the screen is the control stick.
    case touchStick

    var name: String { self == .tilt ? "Tilt the phone" : "Touch stick" }
}

/// Player choices and the logbook, saved on the phone.
final class FlightSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var controlMode: ControlMode { didSet { defaults.set(controlMode.rawValue, forKey: "controlMode") } }
    @Published var assist: FlightAssist { didSet { defaults.set(assist.rawValue, forKey: "assist") } }
    @Published var invertPitch: Bool { didSet { defaults.set(invertPitch, forKey: "invertPitch") } }
    /// Degrees of tilt for full control.
    @Published var tiltRange: Double { didSet { defaults.set(tiltRange, forKey: "tiltRange") } }
    /// Climb and descent tone (variometer).
    @Published var varioTone: Bool { didSet { defaults.set(varioTone, forKey: "varioTone") } }
    /// A tone from the low wing when banked.
    @Published var bankTone: Bool { didSet { defaults.set(bankTone, forKey: "bankTone") } }
    /// Speak through VoiceOver when it's on (otherwise the game's own voice).
    @Published var useVoiceOver: Bool { didSet { defaults.set(useVoiceOver, forKey: "useVoiceOver") } }
    @Published var seenHowToFly: Bool { didSet { defaults.set(seenHowToFly, forKey: "seenHowToFly") } }
    @Published private(set) var logbook: Logbook

    init() {
        controlMode = ControlMode(rawValue: defaults.string(forKey: "controlMode") ?? "") ?? .tilt
        assist = FlightAssist(rawValue: defaults.string(forKey: "assist") ?? "") ?? .easy
        invertPitch = defaults.bool(forKey: "invertPitch")
        tiltRange = defaults.object(forKey: "tiltRange") as? Double ?? 22
        varioTone = defaults.object(forKey: "varioTone") as? Bool ?? true
        bankTone = defaults.object(forKey: "bankTone") as? Bool ?? true
        useVoiceOver = defaults.object(forKey: "useVoiceOver") as? Bool ?? true
        seenHowToFly = defaults.bool(forKey: "seenHowToFly")
        if let data = defaults.data(forKey: "logbook"), let saved = try? JSONDecoder().decode(Logbook.self, from: data) {
            logbook = saved
        } else {
            logbook = Logbook()
        }
    }

    func record(_ summary: FlightSummary, lesson: Int?) {
        logbook.record(summary, lesson: lesson)
        if let data = try? JSONEncoder().encode(logbook) { defaults.set(data, forKey: "logbook") }
    }
}
