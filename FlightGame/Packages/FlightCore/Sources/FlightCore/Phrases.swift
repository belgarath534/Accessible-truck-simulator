import Foundation

/// Everything the game says, in one place.
public enum Phrases {
    public static func instruments(_ r: InstrumentReading) -> String {
        var parts: [String] = []
        switch r.engine {
        case .off: parts.append("Engine off.")
        case .starting: parts.append("Engine starting.")
        case .running: break
        }
        parts.append("Airspeed \(r.airspeedKnots) knots.")
        if r.onGround {
            parts.append("On the ground.")
        } else {
            parts.append("Altitude \(roundFeet(r.altitudeFeet)) feet, \(vertical(r.verticalSpeedFPM)).")
        }
        parts.append("Heading \(Units.headingWords(r.heading)), \(Units.compassPoint(r.heading)).")
        if !r.onGround {
            let b = Int(abs(r.bank).rounded())
            parts.append(b < 3 ? "Wings level." : "Bank \(b) \(r.bank > 0 ? "right" : "left").")
            let p = Int(r.pitch.rounded())
            if abs(p) >= 3 { parts.append("Nose \(abs(p)) degrees \(p > 0 ? "up" : "down").") }
        }
        parts.append("Throttle \(r.throttlePercent) percent.")
        parts.append(r.flaps == 0 ? "Flaps up." : "Flaps \(r.flaps).")
        if r.autopilot { parts.append("Autopilot on.") }
        return parts.joined(separator: " ")
    }

    static func roundFeet(_ f: Int) -> Int {
        let step = f >= 1_000 ? 100 : f >= 100 ? 50 : 10
        return Int((Double(f) / Double(step)).rounded()) * step
    }

    static func vertical(_ fpm: Int) -> String {
        let v = Int((Double(abs(fpm)) / 50).rounded()) * 50
        if v < 100 { return "level" }
        return fpm > 0 ? "climbing \(v) feet per minute" : "descending \(v) feet per minute"
    }

    public static func navigation(_ n: NavigationReading?) -> String {
        guard let n else { return "No airport nearby." }
        let label = n.isDestination ? "\(n.airport), your destination" : "Nearest airport: \(n.airport)"
        let t = Int(abs(n.turn).rounded())
        let turn = t < 5 ? "straight ahead" : "turn \(n.turn > 0 ? "right" : "left") \(t) degrees to heading \(Units.headingWords(n.bearing))"
        return "\(label), \(Units.distance(n.distance)), \(turn). Landing on \(n.runway), heading \(Units.headingWords(World.airports.first { $0.name == n.airport }?.runwayHeading ?? 0))."
    }

    public static func event(_ e: FlightEvent) -> String? {
        switch e {
        case .engineStarting: return "Starting engine."
        case .engineStarted: return "Engine running."
        case .engineStopped: return "Engine off."
        case .engineNotRunning: return "The engine is off. Three-finger double tap to start it."
        case let .throttle(p): return p == 0 ? "Throttle idle." : p == 100 ? "Full throttle." : "Throttle \(p)."
        case let .flaps(f): return f == 0 ? "Flaps up." : "Flaps \(f)."
        case .flapsTooFast: return "Too fast for flaps. Slow below 85 knots first."
        case let .autopilotOn(feet, hdg): return "Autopilot on. Holding \(feet) feet, heading \(Units.headingWords(hdg))."
        case .autopilotOff: return "Autopilot off. You have the controls."
        case .autopilotNeedsAir: return "Autopilot works in the air with the engine running."
        case .liftoff: return "Liftoff! Keep climbing."
        case .stallWarning: return "Stall warning! Nose down a little and add power."
        case .stalled: return "Stall! Push the nose down and add full power."
        case .overspeed: return "Too fast! Raise the nose or reduce power."
        case .steepBank: return "Steep bank! Level the wings."
        case let .altitudeCallout(f): return "\(f)"
        case let .approachCaptured(airport, runway):
            return "Lined up for \(runway) at \(airport). Follow the landing tones: the beeps come from the side to turn toward, and a higher pitch means climb, a lower pitch means descend. Flaps and about 65 knots for landing."
        case .runwayEdge: return "Runway edge!"
        case let .touchdown(rating, fpm): return "\(rating.spoken) \(abs(fpm)) feet per minute. Throttle idle and hold to brake."
        case let .crashed(reason): return reason.spoken
        case .stoppedOffRunway: return "Off the runway, in the grass. Stop and steer back."
        case let .instruments(r): return instruments(r)
        case let .navigation(n): return navigation(n)
        case let .goalComplete(message): return message
        case .passengersUneasy: return "Your passengers are getting uneasy. Gentle turns, and easy on the climbs and descents."
        }
    }

    // MARK: Control tower

    public static func towerTakeoff(_ a: Airport) -> String {
        "\(a.name) tower. \(a.runwayName.capitalized), cleared for takeoff. Have a good flight."
    }

    public static func towerLanding(_ a: Airport) -> String {
        "\(a.name) tower. \(a.runwayName.capitalized), cleared to land."
    }

    public static func money(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return (amount < 0 ? "minus $" : "$") + (f.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))")
    }
}
