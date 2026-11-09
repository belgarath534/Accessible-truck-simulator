import UIKit
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
    @Published var wildlife: Bool { didSet { defaults.set(wildlife, forKey: "wildlife") } }
    /// Show what the game says as text while driving (for deaf and hard-of-hearing players).
    @Published var captions: Bool { didSet { defaults.set(captions, forKey: "captions") } }
    /// On-screen buttons for every driving action (Voice Control, Switch Control, or anyone who prefers buttons).
    @Published var drivingButtons: Bool { didSet { defaults.set(drivingButtons, forKey: "drivingButtons") } }
    /// Which way the menus face (driving is always sideways).
    @Published var menuOrientation: MenuOrientation {
        didSet { defaults.set(menuOrientation.rawValue, forKey: "menuOrientation") }
    }
    /// The first-launch setup has been done.
    @Published var setupDone: Bool { didSet { defaults.set(setupDone, forKey: "setupDone") } }
    /// The app version a rating was last asked for (at most once per version).
    @Published var ratingAskedVersion: String { didSet { defaults.set(ratingAskedVersion, forKey: "ratingAskedVersion") } }
    /// The version whose What's New the player has seen (it shows once by itself after an update).
    @Published var whatsNewSeen: String { didSet { defaults.set(whatsNewSeen, forKey: "whatsNewSeen") } }
    @Published var weather: Bool { didSet { defaults.set(weather, forKey: "weather") } }
    @Published var tutorialDone: Bool { didSet { defaults.set(tutorialDone, forKey: "tutorialDone") } }

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
        traffic = d.object(forKey: "traffic") as? Bool ?? false
        wildlife = d.object(forKey: "wildlife") as? Bool ?? true
        tutorialDone = d.object(forKey: "tutorialDone") as? Bool ?? false
        weather = d.object(forKey: "weather") as? Bool ?? true
        menuOrientation = MenuOrientation(rawValue: d.string(forKey: "menuOrientation") ?? "") ?? .portrait
        setupDone = d.bool(forKey: "setupDone")
        whatsNewSeen = d.string(forKey: "whatsNewSeen") ?? ""
        ratingAskedVersion = d.string(forKey: "ratingAskedVersion") ?? ""
        // Follow the iPhone's own settings the first time.
        captions = d.object(forKey: "captions") as? Bool ?? UIAccessibility.isClosedCaptioningEnabled
        drivingButtons = d.object(forKey: "drivingButtons") as? Bool ?? UIAccessibility.isSwitchControlRunning
        MusicPlayer.shared.volume = Float(musicVolume)
    }
}
