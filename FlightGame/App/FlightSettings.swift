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
    /// The instructor's and the cockpit's recorded voices (off: VoiceOver or the system voice says everything).
    @Published var recordedVoices: Bool { didSet { defaults.set(recordedVoices, forKey: "recordedVoices") } }
    @Published var tutorialDone: Bool { didSet { defaults.set(tutorialDone, forKey: "tutorialDone") } }
    @Published var menuMusic: Bool {
        didSet {
            defaults.set(menuMusic, forKey: "menuMusic")
            MenuMusic.shared.enabled = menuMusic
        }
    }
    @Published private(set) var logbook: Logbook
    /// The pilot career: money, rank, job board and the plane's condition.
    @Published private(set) var career: PilotCareer

    init() {
        controlMode = ControlMode(rawValue: defaults.string(forKey: "controlMode") ?? "") ?? .tilt
        assist = FlightAssist(rawValue: defaults.string(forKey: "assist") ?? "") ?? .easy
        invertPitch = defaults.bool(forKey: "invertPitch")
        tiltRange = defaults.object(forKey: "tiltRange") as? Double ?? 22
        varioTone = defaults.object(forKey: "varioTone") as? Bool ?? true
        bankTone = defaults.object(forKey: "bankTone") as? Bool ?? true
        useVoiceOver = defaults.object(forKey: "useVoiceOver") as? Bool ?? true
        seenHowToFly = defaults.bool(forKey: "seenHowToFly")
        tutorialDone = defaults.bool(forKey: "tutorialDone")
        recordedVoices = defaults.object(forKey: "recordedVoices") as? Bool ?? true
        menuMusic = defaults.object(forKey: "menuMusic") as? Bool ?? true
        if let data = defaults.data(forKey: "logbook"), let saved = try? JSONDecoder().decode(Logbook.self, from: data) {
            logbook = saved
        } else {
            logbook = Logbook()
        }
        if let data = defaults.data(forKey: "career"), let saved = try? JSONDecoder().decode(PilotCareer.self, from: data) {
            career = saved
        } else {
            career = PilotCareer()
        }
        if career.board.isEmpty { career.refreshBoard() }
    }

    private func saveCareer() {
        if let data = try? JSONEncoder().encode(career) { defaults.set(data, forKey: "career") }
    }

    /// Settles a paid flight and returns what it earned.
    func finishJob(_ job: FlightJob, summary: FlightSummary, comfort: Int) -> FlightPay {
        var rng = SystemRandomNumberGenerator()
        let pay = career.finish(job, summary: summary, comfort: comfort, using: &rng)
        saveCareer()
        return pay
    }

    /// Wear from a flight that wasn't a job.
    func wearPlane(_ summary: FlightSummary) {
        career.wear(summary)
        saveCareer()
    }

    /// Returns false if there's nothing to fix or not enough money.
    func repairPlane() -> Bool {
        let done = career.repair()
        saveCareer()
        return done
    }

    func emergencyRepair() -> Bool {
        let done = career.emergencyRepairIfStuck()
        saveCareer()
        return done
    }

    func record(_ summary: FlightSummary, lesson: Int?) {
        logbook.record(summary, lesson: lesson)
        if let data = try? JSONEncoder().encode(logbook) { defaults.set(data, forKey: "logbook") }
    }
}
