import Foundation

/// Flight School: short lessons, one skill each.
public struct Lesson: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    /// Spoken at the start.
    public let briefing: String
    public let start: FlightStart
    public let goal: FlightGoal

    public static let all: [Lesson] = [
        Lesson(id: 1, title: "Takeoff",
               briefing: "Lesson 1, takeoff. You're lined up on Pine Valley's runway. Three-finger double tap starts the engine. Swipe up with two fingers for full throttle. Keep the centerline tone quiet by steering: turn the phone like a wheel. At 55 knots, tilt the top of the phone gently back toward you to lift the nose. Climb to 1,000 feet.",
               start: .runway("pine"), goal: .reachAltitude(feet: 1_000)),
        Lesson(id: 2, title: "Turns",
               briefing: "Lesson 2, turns. You're flying east at 2,500 feet. Turn the phone like a wheel to bank, and the plane turns. The bank tone tells you which wing is low. Turn around to heading two seven zero, west, then level the wings and hold it for a few seconds.",
               start: .air(x: 3_000, y: 2_000, altitude: 762, heading: 90, speed: 52, throttle: 0.65, flaps: 0),
               goal: .turnTo(heading: 270)),
        Lesson(id: 3, title: "Landing",
               briefing: "Lesson 3, landing. You're lined up for Pine Valley's runway, 3 miles out. Follow the landing tones: steer toward the side the beeps come from, a higher pitch means you're too low, a lower pitch means too high. Listen for the height callouts. Just before touchdown, around 20 feet, raise the nose a little to land softly. Then throttle idle and hold a finger on the screen to brake.",
               start: .finalApproach(to: "pine", metres: 5_500), goal: .flyTo("pine")),
        Lesson(id: 4, title: "First Cross-Country Flight",
               briefing: "Lesson 4, your first cross-country flight, from Pine Valley to Harbor City. Take off, climb to about 2,000 feet, then follow the beacon: its beeps come from the side of the airport. Three-finger tap for directions. Line up, follow the landing tones, and land.",
               start: .runway("pine"), goal: .flyTo("harbor")),
    ]
}

/// The pilot's logbook, saved on the phone.
public struct Logbook: Codable, Equatable, Sendable {
    public var flights = 0
    public var landings = 0
    public var butterLandings = 0
    public var crashes = 0
    public var hours: Double = 0
    public var bestLandingFPM: Int?
    public var lessonsPassed: Set<Int> = []
    public var airportsVisited: Set<String> = []

    public init() {}

    public mutating func record(_ s: FlightSummary, lesson: Int?) {
        flights += 1
        hours += s.flightTime / 3_600
        if s.crash != nil { crashes += 1 }
        if let fpm = s.touchdownFPM, s.crash == nil {
            landings += 1
            if s.landing == .butter { butterLandings += 1 }
            bestLandingFPM = min(bestLandingFPM ?? Int.max, abs(fpm))
        }
        if let a = s.landedAt, s.crash == nil { airportsVisited.insert(a) }
        if let lesson, s.completed { lessonsPassed.insert(lesson) }
    }

    public var lines: [String] {
        var l = ["Flights: \(flights).", "Landings: \(landings), \(butterLandings) of them butter.",
                 "Crashes: \(crashes).", String(format: "Flying time: %.1f hours.", hours),
                 "Flight School lessons passed: \(lessonsPassed.count) of \(Lesson.all.count).",
                 "Airports landed at: \(airportsVisited.count) of \(World.airports.count)."]
        if let best = bestLandingFPM { l.append("Softest landing: \(best) feet per minute.") }
        return l
    }
}
