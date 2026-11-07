import Foundation
import SimCore

/// Player preferences, saved to UserDefaults.
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var steeringMode: TouchSteeringMode { didSet { defaults.set(steeringMode.rawValue, forKey: "steeringMode") } }
    @Published var invertTilt: Bool { didSet { defaults.set(invertTilt, forKey: "invertTilt") } }
    /// How far (degrees) you tilt the phone for full steering lock.
    @Published var tiltRange: Double { didSet { defaults.set(tiltRange, forKey: "tiltRange") } }
    @Published var assist: SteeringAssist { didSet { defaults.set(assist.rawValue, forKey: "assist") } }
    @Published var units: UnitSystem { didSet { defaults.set(units.rawValue, forKey: "units") } }
    @Published var laneGuidanceTone: Bool { didSet { defaults.set(laneGuidanceTone, forKey: "laneGuidanceTone") } }
    @Published var announceSpeed: Bool { didSet { defaults.set(announceSpeed, forKey: "announceSpeed") } }
    @Published var announceGears: Bool { didSet { defaults.set(announceGears, forKey: "announceGears") } }
    @Published var speechOutput: SpeechOutput { didSet { defaults.set(speechOutput.rawValue, forKey: "speechOutput") } }
    @Published var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    @Published var volume: Double { didSet { defaults.set(volume, forKey: "volume") } }
    @Published var musicVolume: Double {
        didSet { defaults.set(musicVolume, forKey: "musicVolume"); MusicPlayer.shared.volume = Float(musicVolume) }
    }
    @Published var menuMusic: Bool { didSet { defaults.set(menuMusic, forKey: "menuMusic") } }
    @Published var radioOnStart: Bool { didSet { defaults.set(radioOnStart, forKey: "radioOnStart") } }
    @Published var traffic: Bool { didSet { defaults.set(traffic, forKey: "traffic") } }

    init() {
        let d = UserDefaults.standard
        steeringMode = TouchSteeringMode(rawValue: d.string(forKey: "steeringMode") ?? "") ?? .tilt
        invertTilt = d.bool(forKey: "invertTilt")
        tiltRange = d.object(forKey: "tiltRange") as? Double ?? 25
        assist = SteeringAssist(rawValue: d.string(forKey: "assist") ?? "") ?? .medium
        let defaultUnits: UnitSystem = Locale.current.measurementSystem == .metric ? .metric : .imperial
        units = UnitSystem(rawValue: d.string(forKey: "units") ?? "") ?? defaultUnits
        laneGuidanceTone = d.object(forKey: "laneGuidanceTone") as? Bool ?? true
        announceSpeed = d.object(forKey: "announceSpeed") as? Bool ?? true
        announceGears = d.bool(forKey: "announceGears")
        speechOutput = SpeechOutput(rawValue: d.string(forKey: "speechOutput") ?? "") ?? .gameVoice
        haptics = d.object(forKey: "haptics") as? Bool ?? true
        volume = d.object(forKey: "volume") as? Double ?? 0.8
        musicVolume = d.object(forKey: "musicVolume") as? Double ?? 0.45
        menuMusic = d.object(forKey: "menuMusic") as? Bool ?? true
        radioOnStart = d.object(forKey: "radioOnStart") as? Bool ?? true
        traffic = d.object(forKey: "traffic") as? Bool ?? true
        MusicPlayer.shared.volume = Float(musicVolume)
    }
}
