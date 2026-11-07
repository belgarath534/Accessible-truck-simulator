import Foundation

/// Continuous controls, merged from whichever input sources are active (touch, tilt, controller, keyboard).
public struct DrivingInput: Equatable, Sendable {
    /// 0...1
    public var throttle: Double
    /// 0...1
    public var brake: Double
    /// -1 (full left) ... 1 (full right)
    public var steer: Double

    public init(throttle: Double = 0, brake: Double = 0, steer: Double = 0) {
        self.throttle = throttle
        self.brake = brake
        self.steer = steer
    }

    public static let idle = DrivingInput()

    /// Combine two sources: strongest pedal wins, steering adds (clamped).
    public func merged(with other: DrivingInput) -> DrivingInput {
        DrivingInput(
            throttle: max(throttle, other.throttle),
            brake: max(brake, other.brake),
            steer: min(1, max(-1, steer + other.steer))
        )
    }
}

/// One-shot commands.
public enum DrivingAction: Equatable, Sendable {
    case toggleEngine
    case signal(Side)
    case cancelSignal
    case horn
    case speakDashboard
    case speakRoadAhead
    case pause
    // Radio (handled by the app, not the simulation).
    case toggleRadio
    case nextSong
    case previousSong
}

public enum SignalState: Equatable, Sendable {
    case off
    case on(Side)
}

public enum EngineState: Equatable, Sendable {
    case off
    case starting(remaining: Double)
    case running
}

public enum CrashReason: Equatable, Sendable {
    case leftRoad(Side)
}

/// Things that happened during a simulation step. Audio, speech, haptics and visuals subscribe to these.
public enum SimEvent: Equatable, Sendable {
    case engineStarting
    case engineStarted
    case engineStopped
    case engineNotRunning
    case gearChanged(gear: Int, up: Bool)
    case signalChanged(SignalState)
    case horn
    case rumbleStrip(Side?) // nil = back in lane
    case curveAhead(UpcomingCurve)
    case tooFastForCurve
    /// Slow enough to roll onto the gravel shoulder instead of crashing; steer back to the other side.
    case onShoulder(Side)
    case crashed(CrashReason)
    case outOfFuel
    /// Fuel under a quarter (or under 10 percent when `urgent`), with the distance to the next truck stop.
    case fuelLow(fraction: Double, nextStop: Double?, urgent: Bool)
    case truckStopAhead(distance: Double)
    case pulledIntoTruckStop
    case missedTruckStop(tooFast: Bool)
    case refuelStarted
    case refueled(liters: Double, cost: Int)
    case leftTruckStop
    /// Out of fuel: towed to the next truck stop for a fee, with a little fuel put in.
    case towed(cost: Int, fuelCost: Int)
    // Map and GPS
    case enteredTown(name: String, speedLimit: Double)
    case leftTown(name: String, speedLimit: Double)
    /// "In 1 kilometer, turn right onto Highway 9 toward Cedar Falls."
    case navInstruction(NavInstruction)
    /// Free roaming: the ways you can go at the coming junction.
    case junctionAhead(choices: [JunctionChoice], distance: Double)
    /// Took a junction onto a new road.
    case tookRoad(roadName: String, toward: String, length: Double, turn: Turn)
    /// Left the planned route; the GPS found a new one.
    case rerouted(remaining: Double)
    case missedDropOff
    // Police
    /// Passed a parked police car (a radio crackle), whether or not you were speeding.
    case passedPolice
    /// Caught speeding: siren on, pull over. Speeds in m/s.
    case policeChase(speed: Double, limit: Double)
    case speedingTicket(speed: Double, limit: Double, fine: Int)
    case fledPolice(fine: Int)
    case dashboard(DashboardReading)
    case roadAhead(UpcomingCurve?, remaining: Double?, timeLeft: Double?, truckStop: Double?)
    /// Delivery deadline reminders (5 minutes and 1 minute left).
    case timeLeft(seconds: Double)
    case lateForDelivery
    /// Distance left to the drop-off at milestones (10 km, 5 km, 2 km, 1 km).
    case tripProgress(remaining: Double)
    /// The drop-off is close: slow down.
    case destinationAhead(distance: Double)
    /// The truck is at the drop-off and still moving.
    case atDestination
    /// The truck stopped, but before the drop-off.
    case stoppedShort(remaining: Double)
    case arrived(TripSummary)
}

/// Snapshot of the instruments, used by the spoken dashboard.
public struct DashboardReading: Equatable, Sendable {
    public var speed: Double      // m/s
    public var gear: Int          // 1-based, 0 = neutral
    public var rpm: Double
    public var fuelFraction: Double
    public var engineTempC: Double
    public var signal: SignalState
    public var engine: EngineState
    public var speedLimit: Double // m/s
    /// Roughly how far the fuel left will go, metres.
    public var range: Double = 0
}
