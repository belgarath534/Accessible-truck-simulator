import Foundation

/// Lines with a recorded voice (App/Voices/say_<id>.m4a). Anything not listed here, or whose recording is
/// missing, is spoken by VoiceOver or the game's own voice.
public struct VoiceLine: Equatable, Sendable {
    public enum Speaker: String, Sendable {
        /// The flight instructor: the tutorial and lesson briefings.
        case instructor
        /// The cockpit voice: callouts and warnings.
        case cockpit
    }
    public let id: String
    public let speaker: Speaker
    public let text: String
    public var fileName: String { "say_" + id }
}

public enum VoiceLines {
    public static let all: [VoiceLine] = {
        var lines: [VoiceLine] = []
        for step in Tutorial.Step.allCases where step != .done {
            lines.append(VoiceLine(id: "tutorial_\(step)", speaker: .instructor, text: Tutorial.instruction(step)))
            let hint = Tutorial.reminder(step)
            if !hint.isEmpty { lines.append(VoiceLine(id: "tutorial_\(step)_hint", speaker: .instructor, text: hint)) }
        }
        lines.append(VoiceLine(id: "tutorial_retry", speaker: .instructor, text: Tutorial.retryText))
        lines.append(VoiceLine(id: "tutorial_complete", speaker: .instructor, text: Tutorial.completionMessage))
        for lesson in Lesson.all {
            lines.append(VoiceLine(id: "lesson_\(lesson.id)", speaker: .instructor, text: lesson.briefing))
        }

        var events: [(String, FlightEvent)] = [
            ("engine_starting", .engineStarting), ("engine_running", .engineStarted), ("engine_off", .engineStopped),
            ("engine_not_running", .engineNotRunning), ("flaps_too_fast", .flapsTooFast),
            ("autopilot_off", .autopilotOff), ("autopilot_needs_air", .autopilotNeedsAir), ("liftoff", .liftoff),
            ("stall_warning", .stallWarning), ("stalled", .stalled), ("overspeed", .overspeed),
            ("steep_bank", .steepBank), ("runway_edge", .runwayEdge), ("off_runway", .stoppedOffRunway),
            ("crash_hard", .crashed(.hardLanding)), ("crash_off_airport", .crashed(.offAirport)),
            ("crash_ran_off", .crashed(.ranOffRunway)), ("crash_nose", .crashed(.nosedIn)),
        ]
        for p in stride(from: 0, through: 100, by: 10) { events.append(("throttle_\(p)", .throttle(percent: p))) }
        for f in 0...2 { events.append(("flaps_\(f)", .flaps(f))) }
        for feet in [1_000, 500, 200, 100, 50, 40, 30, 20, 10] { events.append(("callout_\(feet)", .altitudeCallout(feet: feet))) }
        for (id, event) in events {
            if let text = Phrases.event(event) { lines.append(VoiceLine(id: id, speaker: .cockpit, text: text)) }
        }
        return lines
    }()

    /// The recording for a sentence, if there is one.
    public static func line(for text: String) -> VoiceLine? { byText[text] }

    private static let byText: [String: VoiceLine] = Dictionary(all.map { ($0.text, $0) }, uniquingKeysWith: { a, _ in a })
}
