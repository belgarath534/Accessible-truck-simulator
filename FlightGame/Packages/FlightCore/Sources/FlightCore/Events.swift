import Foundation

/// The pilot's controls this frame. Pitch: -1 nose down ... 1 nose up. Roll: -1 left ... 1 right.
public struct FlightInput: Equatable, Sendable {
    public var pitch: Double
    public var roll: Double
    /// Wheel brakes (on the ground).
    public var brake: Bool
    public init(pitch: Double = 0, roll: Double = 0, brake: Bool = false) {
        self.pitch = pitch; self.roll = roll; self.brake = brake
    }
}

public enum FlightAction: Equatable, Sendable {
    case toggleEngine
    case throttleUp, throttleDown, throttleFull, throttleIdle
    case flapsDown, flapsUp
    case toggleAutopilot
    case speakInstruments
    case speakNavigation
}

/// How much the plane helps you.
public enum FlightAssist: String, CaseIterable, Codable, Sendable {
    /// You fly it all.
    case off
    /// Let go and the wings level themselves.
    case standard
    /// Wings level themselves, the nose eases back to level, and the plane won't let you pull into a stall.
    case easy

    public var name: String {
        switch self {
        case .off: return "Off"
        case .standard: return "Standard"
        case .easy: return "Easy"
        }
    }
}

public enum EngineState: Equatable, Sendable {
    case off
    case starting(remaining: Double)
    case running
}

public enum CrashReason: Equatable, Sendable {
    case hardLanding
    case offAirport
    case ranOffRunway
    case nosedIn

    public var spoken: String {
        switch self {
        case .hardLanding: return "Crashed! The landing was too hard, or the wings weren't level."
        case .offAirport: return "Crashed! You came down away from a runway."
        case .ranOffRunway: return "Crashed! You ran off the runway too fast."
        case .nosedIn: return "Crashed! The nose hit the ground first."
        }
    }
}

public enum LandingRating: String, Equatable, Sendable {
    case butter, smooth, firm, hard

    public var spoken: String {
        switch self {
        case .butter: return "Butter landing!"
        case .smooth: return "Smooth landing."
        case .firm: return "Firm landing."
        case .hard: return "Hard landing, but you're down."
        }
    }

    public static func from(feetPerMinute fpm: Int) -> LandingRating {
        let f = abs(fpm)
        return f < 150 ? .butter : f < 350 ? .smooth : f < 600 ? .firm : .hard
    }
}

/// What the instruments say, for the spoken readout.
public struct InstrumentReading: Equatable, Sendable {
    public var airspeedKnots: Int
    public var altitudeFeet: Int
    public var verticalSpeedFPM: Int
    public var heading: Double
    public var bank: Double
    public var pitch: Double
    public var throttlePercent: Int
    public var flaps: Int
    public var engine: EngineState
    public var onGround: Bool
    public var autopilot: Bool
}

public struct NavigationReading: Equatable, Sendable {
    public var airport: String
    public var runway: String
    public var distance: Double
    public var bearing: Double
    /// Positive = turn right.
    public var turn: Double
    public var isDestination: Bool
}

public enum FlightEvent: Equatable, Sendable {
    case engineStarting
    case engineStarted
    case engineStopped
    case engineNotRunning
    case throttle(percent: Int)
    case flaps(Int)
    case flapsTooFast
    case autopilotOn(altitudeFeet: Int, heading: Double)
    case autopilotOff
    case autopilotNeedsAir
    case liftoff
    case stallWarning
    case stalled
    case overspeed
    case steepBank
    case altitudeCallout(feet: Int)
    case approachCaptured(airport: String, runway: String)
    case runwayEdge
    case touchdown(LandingRating, feetPerMinute: Int)
    case crashed(CrashReason)
    case stoppedOffRunway
    case instruments(InstrumentReading)
    case navigation(NavigationReading?)
    case goalComplete(String)
    case passengersUneasy
}
