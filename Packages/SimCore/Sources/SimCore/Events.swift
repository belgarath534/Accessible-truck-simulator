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
    /// Hit another vehicle: head-on (oncoming) or from behind.
    case collision(headOn: Bool, vehicle: VehicleKind)
    /// Hit a deer.
    case animal
}

public enum VehicleKind: String, Equatable, Sendable { case car, pickup, truck }

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
    /// Close to a junction with a signal that doesn't match the route (or no signal where the route turns).
    case signalMismatch(NavInstruction, signal: SignalState)
    /// Left the planned route; the GPS found a new one.
    case rerouted(remaining: Double)
    case missedDropOff
    // Lanes and traffic
    /// Moved into the left lane (passing lane on interstates, oncoming lane elsewhere) or back.
    case changedLane(toLeft: Bool, oncoming: Bool)
    /// In the oncoming lane with traffic coming.
    case wrongSideOfRoad
    /// A slower vehicle ahead in your lane. Distance in metres, its speed in m/s.
    case vehicleAhead(distance: Double, speed: Double, kind: VehicleKind)
    case tooClose
    /// An oncoming driver honking at you for being over the center line.
    case oncomingHorn
    // Police
    /// Passed a parked police car (a radio crackle), whether or not you were speeding.
    case passedPolice
    /// Caught speeding: siren on, pull over. Speeds in m/s.
    case policeChase(speed: Double, limit: Double)
    case speedingTicket(speed: Double, limit: Double, fine: Int)
    case fledPolice(fine: Int)
    /// A thunderclap (storms).
    case thunder
    // Living world
    /// A deer on the road ahead (metres). Honk to scare it off, or slow down.
    case deerAhead(distance: Double)
    /// The deer left the road (`scared`: because of the horn).
    case deerGone(scared: Bool)
    case enteredConstruction(speedLimit: Double)
    case leftConstruction(speedLimit: Double)
    case tollBoothAhead(distance: Double)
    case tollPaid(cost: Int)
    /// Drove through a toll booth too fast to pay.
    case ranToll(fine: Int)
    /// A weigh station ahead (metres): signal right and slow down to pull in.
    case weighStationAhead(distance: Double)
    /// Pulled in and weighed. `fine` is 0 when the truck passes, or the unsafe load fine.
    case weighedIn(cargoKg: Double, fine: Int)
    /// Drove past a weigh station without pulling in (`tooFast`: signalled, but too fast to take the exit).
    case skippedWeighStation(fine: Int, tooFast: Bool)
    /// Turbo Mode: a new speed milestone (every 25 mph from 75 mph), m/s.
    case turboSpeed(Double)
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
