import Foundation

/// A built-in song: a drum and bass groove made by the game itself, so there's nothing to license.
public struct Song: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let style: String
    public let bpm: Double
    /// Total bars, including 2 intro bars and 2 outro bars.
    public let bars: Int
    /// 16 steps per bar: "x" = hit, "." = rest.
    public let kick: String
    public let snare: String
    public let hat: String
    /// Bass root notes (MIDI), one per bar, repeating.
    public let bassline: [Int]

    public static let introBars = 2
    public static let outroBars = 2

    public var beatLength: Double { 60 / bpm }
    public var stepLength: Double { beatLength / 4 }
    public var barLength: Double { beatLength * 4 }
    public var duration: Double { Double(bars) * barLength }

    /// "First Steps, 84 beats per minute, 1 minute 9 seconds."
    public var spokenSummary: String {
        let seconds = Int(duration.rounded())
        let time = seconds >= 60 ? "\(seconds / 60) minute\(seconds >= 120 ? "s" : "") \(seconds % 60) seconds" : "\(seconds) seconds"
        return "\(title). \(style), \(Int(bpm)) beats per minute, \(time)."
    }

    public static let all: [Song] = [
        Song(id: "first_steps", title: "First Steps", style: "Slow and easy", bpm: 84, bars: 22,
             kick: "x.......x.......", snare: "....x.......x...", hat: "x.x.x.x.x.x.x.x.",
             bassline: [36, 36, 41, 43]),
        Song(id: "midnight_bounce", title: "Midnight Bounce", style: "Hip hop", bpm: 94, bars: 26,
             kick: "x..x......x.....", snare: "....x.......x...", hat: "x.xxx.x.x.xxx.x.",
             bassline: [33, 33, 36, 31]),
        Song(id: "street_lights", title: "Street Lights", style: "Drill", bpm: 104, bars: 30,
             kick: "x.....x...x..x..", snare: "........x.......", hat: "x.x.xx.xx.x.x.xx",
             bassline: [37, 37, 40, 35]),
        Song(id: "overdrive", title: "Overdrive", style: "Dance", bpm: 124, bars: 34,
             kick: "x...x...x...x...", snare: "....x.......x...", hat: "..x...x...x...x.",
             bassline: [38, 38, 41, 36]),
    ]

    public static func withID(_ id: String) -> Song? { all.first { $0.id == id } }
}
