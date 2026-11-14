import Foundation

/// How much the game helps with steering. Steering through curves is always up to the player.
///
/// Off is realistic: steering turns the truck, and the angle carries it sideways, which is hard by ear.
/// Low, medium and high use simpler handling: steering moves the truck sideways directly, letting go
/// stops the drift, and curves push the truck toward the outside so you still have to steer through them.
public enum SteeringAssist: String, CaseIterable, Sendable {
    case off, low, medium, high

    var usesSimpleHandling: Bool { self != .off }

    /// Sideways speed at full steering, m/s.
    var maxLateralSpeed: Double {
        switch self {
        case .off: return 0
        case .low: return 2.2
        case .medium: return 1.8
        case .high: return 1.5
        }
    }

    /// How hard curves push the truck to the outside (seconds of curve force turned into drift speed).
    var curvePush: Double {
        switch self {
        case .off: return 0
        case .low: return 0.55
        case .medium: return 0.38
        case .high: return 0.25
        }
    }

    /// Lane keeping: when you aren't steering, how strongly the truck eases back to the centre of its lane
    /// (sideways m/s per metre off centre). Curves still push it out, so you still steer through them.
    var laneKeeping: Double {
        switch self {
        case .off: return 0
        case .low: return 0.15
        case .medium: return 0.3
        case .high: return 0.5
        }
    }

    /// How quickly the truck's heading settles back in line with the road when the player isn't steering (1/s).
    var alignRate: Double {
        switch self {
        case .off: return 0
        case .low: return 0.35
        case .medium: return 0.7
        case .high: return 1.3
        }
    }
}

/// Everything that changes from moment to moment while driving.
public struct TruckState: Equatable, Sendable {
    /// Metres along the road.
    public var position: Double = 0
    /// Metres from the centre of the lane; positive = right.
    public var lateralOffset: Double = 0
    /// Angle between the truck and the road, radians; positive = pointing right.
    public var headingError: Double = 0
    /// Forward speed, m/s.
    public var speed: Double = 0
    /// Road-wheel angle, radians; positive = right.
    public var steerAngle: Double = 0
    /// Sideways speed across the lane, m/s; positive = drifting right.
    public var lateralVelocity: Double = 0
    public var rpm: Double = 0
    /// 0-based index into `gearRatios`.
    public var gearIndex: Int = 0
    public var shiftTimer: Double = 0
    public var engine: EngineState = .off
    /// 0...1 how hard the engine is working — drives the engine sound.
    public var engineLoad: Double = 0
    public var fuelLiters: Double
    public var engineTempC: Double = 20
    /// Brake temperature, °C: rises with braking, falls in the air.
    public var brakeTempC: Double = 40
    /// The engine brake is holding the truck back on a descent (for its sound).
    public var engineBraking = false
    public var signal: SignalState = .off
    public var odometer: Double = 0

    public init(fuelLiters: Double) {
        self.fuelLiters = fuelLiters
    }
}

/// The driving simulation for one trip. Pure logic: feed it input every tick, get events back.
public final class DrivingSession {
    public let spec: TruckSpec
    public private(set) var road: Road
    /// Present when driving on the map (towns and highways) instead of a single road.
    public let navigator: Navigator?
    public let goal: TripGoal
    /// Cargo weight on the trailer; heavier loads accelerate and stop more slowly.
    public internal(set) var cargoMassKg: Double
    /// Seconds allowed for a delivery job, if it has a deadline.
    public let timeLimit: Double?
    public var assist: SteeringAssist
    /// Set before driving. Rain and storms reduce grip and braking.
    public var weather: Weather = .clear
    public internal(set) var truck: TruckState
    public private(set) var time: Double = 0
    public internal(set) var stats = TripStats()
    /// Set when the trip is finished; the simulation stops changing after that.
    public internal(set) var summary: TripSummary?

    /// How close (metres) to the drop-off the truck must stop to finish the trip.
    public static let arrivalTolerance = 60.0
    static let milestones: [Double] = [10_000, 5_000, 2_000, 1_000]
    static let destinationWarning = 400.0

    // Lane geometry, metres from the centre of your lane (positive = right).
    // Your lane is centred on 0; the left lane (oncoming, or the passing lane on interstates) on -3.7.
    public static let rumbleOffset = 0.9
    public static let offRoadOffset = 2.6
    public static let leftLaneCenter = -3.7
    public static let centerLine = -1.85
    /// Rumble strip and road edge on the far left (beyond the left lane).
    public static let leftRumbleOffset = -4.6
    public static let leftOffRoadOffset = -6.3
    /// Fuel burns this many times faster than a real truck, so a full tank lasts about two hours of driving.
    public static let fuelGameScale = 10.0
    /// Dollars per litre at truck stops.
    public static let truckStopFuelPrice = 2.5
    /// Stopped this close to a truck stop (metres, either side), a right signal still pulls in.
    public static let truckStopStopRange = 60.0
    /// Pumps fill this many litres per second.
    public static let pumpRate = 40.0
    /// Fastest you can take a truck stop exit, m/s.
    public static let truckStopExitSpeed = 50 / 3.6
    public static let towFee = 150
    /// The tow takes time: added to the driving time (matters for deadlines).
    public static let towSeconds = 120.0

    // Police
    /// Chance a police car is parked at a spot when you pass it.
    public static let policeChance = 0.5
    /// How close (metres) a police car must be to clock your speed.
    public static let policeRange = 120.0
    /// How far over the limit (m/s) before they pull you over: 8 km/h.
    public static let speedingTolerance = 8 / 3.6
    /// Seconds to stop after the siren starts.
    public static let pullOverTime = 25.0

    public static func speedingFine(speed: Double, limit: Double) -> Int {
        let over = max(0, (speed - limit) * 3.6)
        return 100 + Int((over * 25 / 10).rounded()) * 10
    }

    /// Below this speed (m/s), leaving the lane with an assist on means the shoulder, not a crash.
    public static let shoulderSafeSpeed = 25 / 3.6

    private var announcedCurveIndex: Int?
    private var lastTooFastWarning: Double = -100
    private var rumbleSide: Side?
    private var fuelWarned = false
    private var lastEngineOffHint: Double = -100
    private var announcedMilestones: Set<Double> = []
    private var warnedDestination = false
    private var announcedAtDestination = false
    private var wasStopped = true
    private var announcedTimeWarnings: Set<Double> = []
    private var currentZone: String?
    private var policeDecided: [Double: Bool] = [:]
    private var chase: (speed: Double, limit: Double, timer: Double)?
    var rng: SeededRandom
    /// Traffic on the road (off unless the app turns it on).
    public var trafficEnabled = false
    public internal(set) var traffic: [TrafficVehicle] = []
    /// Rest stops: tiredness on long drives, naps at truck stops.
    public var restEnabled = false
    /// Seconds of driving since the start or the last nap.
    public internal(set) var awakeTime = 0.0
    var warnedTired = false
    var nextDrowsy = 20.0
    /// Online Race: the other player's truck, updated by the app. Placed on your road when it's near.
    public var rival: RivalState?
    /// After bumping into the other truck it's left out for a few seconds, so one bump is one crash.
    var rivalGhostUntil = -1.0
    /// The other truck's id in `traffic`.
    public static let rivalID = -1
    var nextVehicleID = 0
    var oncomingTimer = 12.0
    var slowTimer = 40.0
    var warnedAhead: Set<Int> = []
    var honked: Set<Int> = []
    var lastTooClose: Double = -100
    /// Chance a police car is at each spot (tests set it to 0 or 1).
    public var policePresenceChance = DrivingSession.policeChance
    /// True while a police car is behind you with its siren on.
    public var sirenOn: Bool { chase != nil }
    private var navAnnounced: Set<Int> = []
    private var lastShoulderWarning: Double = -100
    /// The lane you mean to be in: 0 (yours) or leftLaneCenter after signalling left to pass.
    public private(set) var targetLane = 0.0
    private var inLeftLane = false
    var lastWrongSideWarning: Double = -100

    /// How far the truck is from the centre of the lane it should be in (lane guidance beeps use this).
    public var laneGuidanceOffset: Double { truck.lateralOffset - targetLane }

    private enum TruckStopState: Equatable {
        case driving
        case pulledIn(index: Int)
        case refueling(index: Int, liters: Double)
    }
    private var truckStopState = TruckStopState.driving
    private var announcedStop: Int?
    private var exitChecked: Int?
    private var warnedQuarter = false
    private var outOfFuelTimer: Double = 0

    /// True while the truck is parked at a pump, filling up.
    public var isRefueling: Bool { if case .refueling = truckStopState { return true }; return false }
    /// True after taking a truck stop exit, until leaving the truck stop.
    public var isAtTruckStop: Bool { truckStopState != .driving }
    private var announcedLate = false

    public init(spec: TruckSpec = .starter, road: Road = .practiceLoop, goal: TripGoal = .freeDrive,
                cargoMassKg: Double = 0, timeLimit: Double? = nil, startingFuel: Double? = nil,
                navigator: Navigator? = nil, assist: SteeringAssist = .medium,
                seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.rng = SeededRandom(seed: seed)
        self.spec = spec
        self.navigator = navigator
        self.road = navigator?.road ?? road
        self.goal = goal
        self.cargoMassKg = cargoMassKg
        self.timeLimit = timeLimit
        self.assist = assist
        self.truck = TruckState(fuelLiters: min(spec.fuelCapacityLiters, max(0, startingFuel ?? spec.fuelCapacityLiters)))
        // A tank already under the warning levels shouldn't be announced as if it just dropped.
        warnedQuarter = truck.fuelLiters / spec.fuelCapacityLiters < 0.25
        fuelWarned = truck.fuelLiters / spec.fuelCapacityLiters < 0.1
    }

    // MARK: - Save and continue later

    /// Where the drive is, to save it and pick it up later.
    public var snapshot: DriveSnapshot {
        let side: Side? = { if case let .on(s) = truck.signal { return s }; return nil }()
        return DriveSnapshot(truckID: spec.id, position: truck.position, lateralOffset: truck.lateralOffset,
                             odometer: truck.odometer, fuelLiters: truck.fuelLiters, engineTempC: truck.engineTempC,
                             time: time, signal: side, stats: stats, weather: weather,
                             edge: navigator?.edge, route: navigator?.route ?? [], lastTown: navigator?.lastTown,
                             targetLane: targetLane)
    }

    /// Picks up a saved drive: same place, fuel, trip so far and weather, with the truck stopped and the engine off.
    public func restore(_ s: DriveSnapshot) {
        if let navigator, let edge = s.edge {
            navigator.restore(edge: edge, route: s.route, lastTown: s.lastTown ?? navigator.lastTown)
            road = navigator.road
        }
        truck.position = s.position
        truck.lateralOffset = s.lateralOffset
        truck.odometer = s.odometer
        truck.fuelLiters = min(s.fuelLiters, spec.fuelCapacityLiters)
        truck.engineTempC = s.engineTempC
        truck.signal = s.signal.map { .on($0) } ?? .off
        truck.speed = 0
        truck.engine = .off
        truck.gearIndex = 0
        time = s.time
        stats = s.stats
        weather = s.weather
        targetLane = s.targetLane
        inLeftLane = truck.lateralOffset < DrivingSession.centerLine
        // Don't repeat announcements for what's already behind you.
        if let r = remaining {
            for m in DrivingSession.milestones where r <= m { announcedMilestones.insert(m) }
            warnedDestination = r <= DrivingSession.destinationWarning
            if navigator?.destination != nil {
                let toEnd = road.totalLength - truck.position
                for mark in [1_000, 300, 200] where toEnd < Double(mark) { navAnnounced.insert(mark) }
            }
        }
        if let t = timeLeft {
            for w in [300.0, 60.0] where t <= w { announcedTimeWarnings.insert(w) }
            announcedLate = t < 0
        }
        currentZone = road.speedZone(at: truck.position)?.name
        // Weigh stations already behind the truck were dealt with before the save.
        for (i, station) in road.weighStations.enumerated() where station <= truck.position {
            weighStationsHandled.insert(i)
            weighStationsAnnounced.insert(i)
        }
        let fraction = truck.fuelLiters / spec.fuelCapacityLiters
        warnedQuarter = fraction < 0.25
        fuelWarned = fraction < 0.1
    }

    // MARK: - Actions

    public func perform(_ action: DrivingAction) -> [SimEvent] {
        switch action {
        case .toggleEngine:
            switch truck.engine {
            case .off:
                guard truck.fuelLiters > 0 else { return [.outOfFuel] }
                truck.engine = .starting(remaining: spec.engineStartSeconds)
                return [.engineStarting]
            case .starting, .running:
                truck.engine = .off
                return [.engineStopped]
            }
        case let .signal(side):
            truck.signal = truck.signal == .on(side) ? .off : .on(side)
            return [.signalChanged(truck.signal)]
        case .cancelSignal:
            truck.signal = .off
            return [.signalChanged(.off)]
        case .horn:
            // A honk scares a nearby deer off the road.
            if let d = deer, d.position - truck.position < 300, !d.scared {
                deer?.leavesAt = min(d.leavesAt, time + 1.2)
                deer?.scared = true
            }
            return [.horn]
        case .speakDashboard:
            return [.dashboard(dashboard)]
        case .speakRoadAhead:
            var events: [SimEvent] = [.roadAhead(forWeather(road.nextCurve(after: truck.position, within: 3_000)), remaining: remaining,
                                                 timeLeft: timeLeft, truckStop: road.nextTruckStop(after: truck.position)?.distance)]
            if let navigator {
                if navigator.destination != nil, let next = navigator.nextInstruction(at: truck.position) {
                    events.append(.navInstruction(next))
                } else if navigator.destination == nil {
                    events.append(.junctionAhead(choices: navigator.junctionChoices,
                                                 distance: road.totalLength - truck.position))
                }
            }
            return events
        case .speakAroundMe:
            return [.aroundMe(surroundings)]
        case .skipDocking:
            guard docking != nil else { return [] }
            var events: [SimEvent] = []
            finishDocking(.skipped, events: &events)
            return events
        case .pause, .toggleRadio, .nextSong, .previousSong:
            return []
        }
    }

    public var dashboard: DashboardReading {
        DashboardReading(
            speed: truck.speed,
            gear: truck.engine == .running ? truck.gearIndex + 1 : 0,
            rpm: truck.engine == .running ? truck.rpm : 0,
            fuelFraction: truck.fuelLiters / spec.fuelCapacityLiters,
            engineTempC: truck.engineTempC,
            signal: truck.signal,
            engine: truck.engine,
            speedLimit: currentSpeedLimit,
            range: range
        )
    }

    /// Litres per metre the truck burns: measured this trip once it has gone a little way, else a typical cruise.
    public var fuelPerMetre: Double {
        if stats.distance > 1_000 && stats.fuelUsedLiters > 0 { return stats.fuelUsedLiters / stats.distance }
        return DrivingSession.typicalFuelPerMetre
    }

    /// Typical litres per metre on a map job with a light load (measured: about 3.4 L/km), used before a trip
    /// is measured and for the Job Board's fuel check.
    public static let typicalFuelPerMetre = 0.0035

    /// How far the fuel left will go, metres.
    public var range: Double { truck.fuelLiters / fuelPerMetre }

    /// Tyre grip in curves today: the truck's grip, less in the rain.
    public var grip: Double { spec.steeringLatAccel * roadGrip }
    /// Snow chains are on (snow only): better grip and braking, but a 50 km/h top speed. Set before driving.
    public var chainsOn = false
    var chainsWork: Bool { chainsOn && weather == .snow }
    /// Grip and braking for today's road, with chains.
    var roadGrip: Double { chainsWork ? DrivingSession.chainsGrip : weather.grip }
    var roadBraking: Double { chainsWork ? DrivingSession.chainsBraking : weather.braking }

    /// A curve with its suggested speed lowered for the weather.
    func forWeather(_ curve: UpcomingCurve?) -> UpcomingCurve? {
        guard var c = curve else { return nil }
        c.advisorySpeed *= roadGrip.squareRoot()
        return c
    }

    var nextThunder: Double = 25

    // Living world
    /// Set before driving, from the player's clock.
    public var timeOfDay: TimeOfDay = .day
    /// Deer can appear (on roads with wildlife). Off for the tutorial and practice.
    public var wildlifeEnabled = false
    /// The deer on the road now, if any.
    public internal(set) var deer: Deer?
    var deerTimer: Double = 120
    var tollsHandled: Set<Int> = []
    var tollsAnnounced: Set<Int> = []
    var weighStationsHandled: Set<Int> = []
    var lastBrakeDecel = 0.0
    var hintedStop: Int?
    /// The truck's condition, percent (blowouts are likelier on a worn truck). Set before driving.
    public var condition = 100.0
    /// Tires can blow out (map drives). Set before driving.
    public var blowoutsEnabled = false
    /// A blown tire on this side, until the truck stops for a tire change.
    public internal(set) var blowout: Side?
    var warnedBrakeHot = false
    var warnedBrakeFade = false
    var announcedHills: Set<Int> = []
    var announcedRamps: Set<Int> = []
    var usedRamps: Set<Int> = []
    /// Other truckers talk on the CB now and then (map drives). Set before driving.
    public var cbRadioEnabled = false
    var nextCB = 90.0
    /// Back into the loading dock after stopping at the drop-off (deliveries). Set before driving.
    public var dockingEnabled = false
    /// Backing into the dock right now.
    public internal(set) var docking: DockingState?
    public internal(set) var dockRating: DockRating?
    var pendingStopError = 0.0
    /// A tow call: metres along the route to the stranded car (nil for other drives). Set before driving.
    public var towPickupAt: Double?
    public internal(set) var towHooked = false
    public internal(set) var towFailed = false
    var towAnnounced = false
    var towHookTimer = 0.0
    /// The load's kind (special cargo rules). Set before driving.
    public var cargoKind: CargoKind = .standard
    var lastLivestockScare = -100.0
    var nextLivestockSound = 30.0
    var oversizeOverSince: Double?
    var lastOversizeWarning = -100.0
    var announcedSpoiling = false
    /// Turbo Mode: no governor, a big power boost, no police. Set before driving.
    public var turbo = false {
        didSet { stats.turbo = turbo }
    }
    var turboMilestone = 0
    var weighStationsAnnounced: Set<Int> = []
    /// Inside a construction zone (for its sounds).
    public var inConstructionZone: Bool { road.speedZone(at: truck.position)?.kind == .construction }

    /// Seconds left before the delivery is late (negative once late), or nil without a deadline.
    public var timeLeft: Double? {
        timeLimit.map { $0 - stats.drivingTime }
    }

    public var totalMassKg: Double { spec.massKg + cargoMassKg }

    /// Metres left to the drop-off (negative once past it), or nil on a free drive.
    public var remaining: Double? {
        if let navigator { return navigator.remaining(at: truck.position) }
        return goal.distance.map { $0 - truck.odometer }
    }

    /// Speed limit where the truck is now (towns are slower).
    public var currentSpeedLimit: Double { road.speedLimit(at: truck.position) }

    /// Puts the truck back in the centre of its lane, stopped. Used after a crash.
    public func recover() {
        truck.lateralOffset = 0
        truck.headingError = 0
        truck.lateralVelocity = 0
        truck.speed = 0
        truck.steerAngle = 0
        targetLane = 0
        inLeftLane = false
        truck.gearIndex = 0
        rumbleSide = nil
    }

    // MARK: - Simulation step

    public func step(dt: Double, input rawInput: DrivingInput) -> [SimEvent] {
        guard summary == nil else { return [] }
        var events: [SimEvent] = []
        time += dt
        let input = DrivingInput(
            throttle: min(max(rawInput.throttle, 0), 1),
            brake: min(max(rawInput.brake, 0), 1),
            steer: min(max(rawInput.steer, -1), 1)
        )

        stepEngineState(dt: dt, events: &events)
        // Backing into the dock: its own slow, careful steps; the delivery clock has stopped.
        if docking != nil {
            stepDocking(dt: dt, input: input, events: &events)
            return events
        }
        if truck.engine == .off, input.throttle > 0.5, time - lastEngineOffHint > 6 {
            lastEngineOffHint = time
            events.append(.engineNotRunning)
        }
        stepLongitudinal(dt: dt, input: input, events: &events)
        stepLateral(dt: dt, input: input)
        stepTemperatureAndFuel(dt: dt, events: &events)
        checkLane(events: &events)
        checkCurves(events: &events)
        checkMap(events: &events)
        checkTolls(events: &events)
        checkWeighStations(events: &events)
        checkTurboSpeed(events: &events)
        checkSpecialCargo(input: input, events: &events)
        checkTowCall(dt: dt, events: &events)
        stepBrakes(dt: dt, input: input, events: &events)
        checkBlowout(dt: dt, events: &events)
        checkHills(events: &events)
        if cbRadioEnabled && time >= nextCB {
            nextCB = time + Double.random(in: DrivingSession.cbInterval, using: &rng)
            if truck.speed > 5 && chase == nil { events.append(.cbChatter) }
        }
        stepDeer(dt: dt, events: &events)
        stepTiredness(dt: dt, events: &events)
        placeRival()
        stepTraffic(dt: dt, events: &events)
        checkPolice(dt: dt, events: &events)
        checkTruckStops(dt: dt, input: input, events: &events)
        checkTow(dt: dt, events: &events)
        if weather == .storm {
            nextThunder -= dt
            if nextThunder <= 0 {
                nextThunder = Double.random(in: 20...60, using: &rng)
                events.append(.thunder)
            }
        }
        updateStats(dt: dt, events: events)
        checkTrip(events: &events)
        return events
    }

    private func updateStats(dt: Double, events: [SimEvent]) {
        if stats.drivingTime > 0 || truck.speed > 0.1 { stats.drivingTime += dt }
        stats.distance = truck.odometer
        stats.topSpeed = max(stats.topSpeed, truck.speed)
        for event in events {
            switch event {
            case .crashed: stats.crashes += 1
            case .tooFastForCurve: stats.tooFastWarnings += 1
            default: break
            }
        }
    }

    private func checkTrip(events: inout [SimEvent]) {
        if let timeLeft {
            for warning in [300.0, 60.0] where timeLeft <= warning && !announcedTimeWarnings.contains(warning) {
                announcedTimeWarnings.insert(warning)
                if (timeLimit ?? 0) - warning > 60 { events.append(.timeLeft(seconds: warning)) }
            }
            if timeLeft < 0 && !announcedLate {
                announcedLate = true
                events.append(.lateForDelivery)
            }
        }
        guard let total = goal.distance, let remaining else { return }
        for m in DrivingSession.milestones where remaining <= m && !announcedMilestones.contains(m) {
            announcedMilestones.insert(m)
            // Only milestones the player actually drives toward (not ones that are already passed at the start).
            if total - m > 500 { events.append(.tripProgress(remaining: m)) }
        }
        if !warnedDestination && remaining <= DrivingSession.destinationWarning {
            warnedDestination = true
            events.append(.destinationAhead(distance: max(0, remaining)))
        }
        if !announcedAtDestination && remaining <= 0 && truck.speed > 2 {
            announcedAtDestination = true
            events.append(.atDestination)
        }

        let stopped = truck.speed < 0.3
        defer { wasStopped = stopped }
        guard stopped else { return }
        if remaining <= DrivingSession.arrivalTolerance && stats.drivingTime > 0 {
            if startDocking(stopError: -remaining, events: &events) { return }
            let result = TripSummary(goalName: goal.name, stats: stats, stopError: -remaining)
            summary = result
            events.append(.arrived(result))
        } else if !wasStopped && remaining <= 1_000 && stats.drivingTime > 0
                    && !events.contains(where: { if case .crashed = $0 { return true }; return false }) {
            events.append(.stoppedShort(remaining: remaining))
        }
    }

    private func stepEngineState(dt: Double, events: inout [SimEvent]) {
        if case let .starting(remaining) = truck.engine {
            let r = remaining - dt
            if r <= 0 {
                truck.engine = .running
                truck.rpm = spec.idleRPM
                events.append(.engineStarted)
            } else {
                truck.engine = .starting(remaining: r)
                // Cranking: the starter motor spins the engine slowly.
                truck.rpm = 150 + 100 * sin(time * 40)
            }
        }
    }

    private func overallRatio(_ gearIndex: Int) -> Double {
        spec.gearRatios[gearIndex] * spec.finalDrive
    }

    private func wheelRPM(speed: Double) -> Double {
        speed / (2 * .pi * spec.wheelRadius) * 60
    }

    private func stepLongitudinal(dt: Double, input: DrivingInput, events: inout [SimEvent]) {
        let mass = totalMassKg
        let g = 9.81
        let running = truck.engine == .running
        let wheelRPM = wheelRPM(speed: truck.speed)

        // Automatic gearbox.
        if running && truck.shiftTimer <= 0 {
            let rpmInGear = wheelRPM * overallRatio(truck.gearIndex)
            if rpmInGear > spec.shiftUpRPM && truck.gearIndex < spec.gearRatios.count - 1 {
                truck.gearIndex += 1
                truck.shiftTimer = spec.shiftSeconds
                events.append(.gearChanged(gear: truck.gearIndex + 1, up: true))
            } else if rpmInGear < spec.shiftDownRPM && truck.gearIndex > 0 {
                // Skip-shift down to a sensible gear when slowing hard.
                var target = truck.gearIndex - 1
                while target > 0 && wheelRPM * overallRatio(target) < spec.shiftDownRPM { target -= 1 }
                truck.gearIndex = target
                truck.shiftTimer = spec.shiftSeconds
                events.append(.gearChanged(gear: truck.gearIndex + 1, up: false))
            }
        }
        let shifting = truck.shiftTimer > 0
        truck.shiftTimer = max(0, truck.shiftTimer - dt)

        // Engine RPM: locked to the wheels once the clutch is engaged, otherwise slipping above idle.
        let ratio = overallRatio(truck.gearIndex)
        let lockedRPM = wheelRPM * ratio
        var targetRPM: Double
        if running {
            let slipRPM = spec.idleRPM + input.throttle * 700
            targetRPM = shifting ? max(spec.idleRPM, lockedRPM * 0.8) : max(lockedRPM, truck.gearIndex == 0 ? slipRPM : spec.idleRPM)
            targetRPM = min(targetRPM, spec.maxRPM)
        } else if case .starting = truck.engine {
            targetRPM = truck.rpm
        } else {
            targetRPM = 0
        }
        // Engines have inertia; smooth RPM so the sound doesn't jump.
        truck.rpm += (targetRPM - truck.rpm) * min(1, dt * 8)

        // Drive force.
        var driveForce = 0.0
        if running && !shifting {
            let governed = (!turbo && truck.speed >= spec.speedLimiter) || (chainsWork && truck.speed >= DrivingSession.chainsSpeed)
            let throttle = governed ? 0 : input.throttle
            let torque = spec.torque(atRPM: max(truck.rpm, spec.idleRPM)) * throttle
            driveForce = torque * ratio * spec.drivetrainEfficiency / spec.wheelRadius
            if turbo { driveForce = max(driveForce, DrivingSession.turboPowerW * throttle / max(truck.speed, 4)) }
            driveForce = min(driveForce, mass * spec.tractionLimitAccel)
            if throttle < 0.05 && truck.speed > 1 {
                let engineBrake = spec.peakTorque * spec.engineBrakeFraction * (truck.rpm / spec.maxRPM)
                driveForce -= engineBrake * ratio / spec.wheelRadius
            }
            truck.engineLoad = throttle
        } else {
            truck.engineLoad = 0
        }

        // Resistances.
        let aero = 0.5 * 1.2 * spec.dragArea * truck.speed * truck.speed
        let rolling = truck.speed > 0.01 ? spec.rollingResistance * mass * g : 0
        // Brake force is sized for the truck with a light load, so heavy cargo takes longer to stop.
        let brakeDecel = min(spec.maxBrakeDecel, spec.maxBrakeDecel * spec.massKg * 1.5 / mass) * roadBraking * brakeFade
        let brake = input.brake * brakeDecel * mass

        // Hills: gravity along the road (sin of the slope is close enough to the grade).
        let grade = road.grade(at: truck.position)
        // Off the gas going downhill, the engine brake holds the truck back on grades up to about 4.5%.
        let engineBrakeHold = running && input.throttle < 0.05 && grade < 0 && truck.speed > 3
            ? g * min(-grade, DrivingSession.engineBrakeGrade) : 0
        truck.engineBraking = engineBrakeHold > 0.05
        var accel = (driveForce - aero - rolling) / mass - g * grade - engineBrakeHold
        let decelFromBrakes = brake / mass
        lastBrakeDecel = truck.speed > 0.1 ? decelFromBrakes : 0
        accel -= truck.speed > 0 ? decelFromBrakes : 0

        truck.speed = max(0, truck.speed + accel * dt)
        if truck.speed < 0.05 && input.throttle < 0.05 { truck.speed = 0 }

        // Looping roads wrap; map roads run past their end into the next junction (see checkMap).
        let advanced = truck.position + truck.speed * dt
        truck.position = road.loops ? road.normalized(advanced) : advanced
        truck.odometer += truck.speed * dt
    }

    private func stepLateral(dt: Double, input: DrivingInput) {
        let v = truck.speed
        // Speed-sensitive steering: full lock always produces roughly the same sideways force,
        // so steering feels consistent at any speed and the truck can't be flicked around on the highway.
        let speedLimitedAngle = v > 1 ? grip * spec.wheelbase / (v * v) : spec.maxSteerAngle
        let maxAngle = min(spec.maxSteerAngle, speedLimitedAngle)
        let target = input.steer * maxAngle
        let maxDelta = spec.steerRate * dt
        truck.steerAngle += min(max(target - truck.steerAngle, -maxDelta), maxDelta)
        if abs(truck.steerAngle) > maxAngle { truck.steerAngle = maxAngle * (truck.steerAngle > 0 ? 1 : -1) }

        let kRoad = road.curvature(at: truck.position)
        if assist.usesSimpleHandling {
            stepSimpleLateral(dt: dt, input: input, curvature: kRoad)
            return
        }

        // Realistic: kinematic bicycle model in road-relative coordinates.
        var headingRate = v * tan(truck.steerAngle) / spec.wheelbase - v * kRoad
        if abs(input.steer) < 0.1 && v > 0.5 {
            headingRate -= assist.alignRate * truck.headingError
        }
        truck.headingError += headingRate * dt
        truck.headingError = min(max(truck.headingError, -0.6), 0.6)
        truck.lateralOffset += v * sin(truck.headingError) * dt
    }

    /// Simple handling: steering sets how fast the truck moves across the lane.
    private func stepSimpleLateral(dt: Double, input: DrivingInput, curvature k: Double) {
        let v = truck.speed
        // Sideways force the curve asks for at this speed; positive curvature (right bend) pushes left.
        let curveAccel = v * v * k
        var push = -curveAccel * assist.curvePush
        // Too fast for the curve: past the tyres' grip the truck slides out much harder.
        let grip = self.grip
        let overGrip = abs(curveAccel) / grip - 0.9
        if overGrip > 0 { push *= 1 + 4 * overGrip }
        // Barely any sideways movement while crawling.
        let speedFactor = min(1, v / 4)
        // Lane keeping: hands off the wheel, the truck eases back to the middle of the lane it's meant to be in.
        let keep = abs(input.steer) < 0.05 ? -laneGuidanceOffset * assist.laneKeeping : 0
        let target = (input.steer * assist.maxLateralSpeed + push + keep) * speedFactor
        // The truck's weight: sideways speed changes smoothly, not instantly.
        truck.lateralVelocity += (target - truck.lateralVelocity) * min(1, dt / 0.35)
        truck.lateralOffset += truck.lateralVelocity * dt
        truck.headingError = v > 0.5 ? atan2(truck.lateralVelocity, v) : 0
        truck.steerAngle = input.steer * min(spec.maxSteerAngle, v > 1 ? grip * spec.wheelbase / (v * v) : spec.maxSteerAngle)
    }

    private func stepTemperatureAndFuel(dt: Double, events: inout [SimEvent]) {
        let running = truck.engine == .running
        let targetTemp = running ? 82 + 10 * truck.engineLoad : 20
        let rate = running ? 0.01 : 0.003
        truck.engineTempC += (targetTemp - truck.engineTempC) * min(1, dt * rate)

        guard running else { return }
        let powerKW = spec.torque(atRPM: truck.rpm) * truck.engineLoad * truck.rpm * 2 * .pi / 60 / 1000
        let litersPerSecond = (0.0005 + powerKW * 0.252 / 3600) * DrivingSession.fuelGameScale * spec.fuelEfficiency
            * (turbo ? DrivingSession.turboFuelMultiplier : 1)
        let burned = min(truck.fuelLiters, litersPerSecond * dt)
        truck.fuelLiters -= burned
        stats.fuelUsedLiters += burned
        let fraction = truck.fuelLiters / spec.fuelCapacityLiters
        if truck.fuelLiters <= 0 {
            truck.engine = .off
            events.append(.outOfFuel)
            events.append(.engineStopped)
        } else if !fuelWarned && fraction < 0.1 {
            fuelWarned = true
            warnedQuarter = true
            events.append(.fuelLow(fraction: fraction, nextStop: road.nextTruckStop(after: truck.position)?.distance, urgent: true))
        } else if !warnedQuarter && fraction < 0.25 {
            warnedQuarter = true
            events.append(.fuelLow(fraction: fraction, nextStop: road.nextTruckStop(after: truck.position)?.distance, urgent: false))
        }
    }

    // MARK: - Map

    private func checkMap(events: inout [SimEvent]) {
        let position = truck.position

        // Towns: speed limit changes.
        let zone = road.speedZone(at: position)
        if zone?.name != currentZone {
            if let old = currentZone, old == "Construction zone" {
                events.append(.leftConstruction(speedLimit: road.speedLimit(at: position)))
            } else if let old = currentZone, zone == nil {
                events.append(.leftTown(name: old, speedLimit: road.speedLimit(at: position)))
            }
            if let zone {
                if zone.kind == .construction {
                    events.append(.enteredConstruction(speedLimit: zone.limit))
                } else {
                    events.append(.enteredTown(name: zone.name, speedLimit: zone.limit))
                }
            }
            currentZone = zone?.name
        }
        guard let nav = navigator else { return }

        // GPS: the next junction at 1 km and 300 m (free roaming: the choices at 800 m).
        let toEnd = road.totalLength - position
        if truck.speed > 1 {
            if nav.destination != nil {
                for mark in [1_000, 300] where toEnd <= Double(mark) && !navAnnounced.contains(mark) {
                    navAnnounced.insert(mark)
                    if road.totalLength > Double(mark) + 200, let instruction = nav.nextInstruction(at: position) {
                        events.append(.navInstruction(instruction))
                    }
                }
                // Last chance: about 200 m before the junction, check the signal matches the route.
                if toEnd <= 200 && toEnd > 30 && !navAnnounced.contains(200) {
                    navAnnounced.insert(200)
                    if let instruction = nav.nextInstruction(at: position) {
                        let wanted: SignalState = instruction.turn == .left ? .on(.left)
                            : instruction.turn == .right ? .on(.right) : .off
                        if instruction.turn != .uTurn && truck.signal != wanted {
                            events.append(.signalMismatch(instruction, signal: truck.signal))
                        }
                    }
                }
            } else if toEnd <= 800 && !navAnnounced.contains(800) {
                navAnnounced.insert(800)
                events.append(.junctionAhead(choices: nav.junctionChoices, distance: toEnd))
            }
        }

        // End of the road: take the junction (or, at the destination, allow a little room to stop).
        guard position >= road.totalLength else { return }
        if nav.onFinalRoad {
            guard position > road.totalLength + 150 else { return }
            events.append(.missedDropOff)
        }
        let oldLength = road.totalLength
        let signal = truck.signal
        let result = nav.takeJunction(signal: signal)
        road = nav.road
        truck.position = position - oldLength
        if result.choice.turn != .straight { truck.signal = .off }
        announcedCurveIndex = nil
        announcedStop = nil
        exitChecked = nil
        truckStopState = .driving
        navAnnounced = []
        policeDecided = [:]
        tollsHandled = []
        tollsAnnounced = []
        announcedHills = []
        announcedRamps = []
        usedRamps = []
        weighStationsHandled = []
        weighStationsAnnounced = []
        deer = nil
        clearTraffic()
        currentZone = road.speedZone(at: truck.position)?.name
        events.append(.tookRoad(roadName: result.choice.roadName, toward: result.choice.toward,
                                length: road.totalLength, turn: result.choice.turn))
        if !result.onRoute, let remaining {
            events.append(.rerouted(remaining: remaining))
        }
    }

    // MARK: - Tolls and deer

    private func checkTolls(events: inout [SimEvent]) {
        for (i, booth) in road.tollBooths.enumerated() {
            let ahead = booth - truck.position
            if ahead > 0 && ahead < 800 && !tollsAnnounced.contains(i) && truck.speed > 2 {
                tollsAnnounced.insert(i)
                events.append(.tollBoothAhead(distance: ahead))
            }
            if ahead <= 0 && ahead > -50 && !tollsHandled.contains(i) {
                tollsHandled.insert(i)
                if truck.speed <= DrivingSession.tollSpeed {
                    stats.tollCost += DrivingSession.tollCost
                    events.append(.tollPaid(cost: DrivingSession.tollCost))
                } else {
                    stats.tickets += 1
                    stats.ticketCost += DrivingSession.tollFine
                    events.append(.ranToll(fine: DrivingSession.tollFine))
                }
            }
        }
    }

    // MARK: - Special cargo

    private func checkSpecialCargo(input: DrivingInput, events: inout [SimEvent]) {
        switch cargoKind {
        case .livestock:
            let curveScare = events.contains(.tooFastForCurve)
            let brakeScare = input.brake > DrivingSession.livestockHardBrake && truck.speed > 8
            if (curveScare || brakeScare) && time - lastLivestockScare > 6 {
                lastLivestockScare = time
                stats.livestockScares += 1
                events.append(.livestockScared)
            } else if time >= nextLivestockSound {
                nextLivestockSound = time + Double.random(in: 40...90, using: &rng)
                if truck.engine == .running { events.append(.livestockSound) }
            }
        case .oversize:
            if truck.speed > DrivingSession.oversizeSpeedLimit + 1.5 {
                if oversizeOverSince == nil { oversizeOverSince = time }
                if let since = oversizeOverSince, time - since > 3, time - lastOversizeWarning > 10 {
                    lastOversizeWarning = time
                    stats.oversizeWarnings += 1
                    events.append(.oversizeTooFast(limit: DrivingSession.oversizeSpeedLimit))
                }
            } else {
                oversizeOverSince = nil
            }
        case .refrigerated:
            if !announcedSpoiling, let left = timeLeft, left < 0 {
                announcedSpoiling = true
                events.append(.cargoSpoiling)
            }
        case .hazmat:
            if !stats.hazmatSpilled, events.contains(where: { if case .crashed = $0 { return true }; return false }) {
                stats.hazmatSpilled = true
                events.append(.hazmatSpill(cost: DrivingSession.hazmatCleanupCost))
            }
        case .standard:
            break
        }
    }

    // MARK: - Turbo Mode

    private func checkTurboSpeed(events: inout [SimEvent]) {
        guard turbo else { return }
        let step = DrivingSession.turboCalloutStep, start = DrivingSession.turboCalloutStart
        guard truck.speed >= start else { return }
        let milestone = Int(((truck.speed - start) / step).rounded(.down)) + 1
        if milestone > turboMilestone {
            turboMilestone = milestone
            events.append(.turboSpeed(start + Double(milestone - 1) * step))
        }
    }

    // MARK: - Weigh stations

    /// Announced about half a mile ahead. Pull in like a truck stop: right signal on and slow enough as you reach it.
    /// A heavy load on a truck that crashed this trip is fined at the scale; driving past is a ticket.
    private func checkWeighStations(events: inout [SimEvent]) {
        for (i, station) in road.weighStations.enumerated() {
            let ahead = station - truck.position
            if ahead > 0 && ahead < DrivingSession.weighStationWarning && !weighStationsAnnounced.contains(i) && truck.speed > 2 {
                weighStationsAnnounced.insert(i)
                events.append(.weighStationAhead(distance: ahead))
            }
            guard ahead <= 0 && ahead > -50 && !weighStationsHandled.contains(i) else { continue }
            weighStationsHandled.insert(i)
            let signalledRight = truck.signal == .on(.right)
            if signalledRight && truck.speed <= DrivingSession.truckStopExitSpeed {
                truck.signal = .off
                var fine = 0
                if cargoMassKg > DrivingSession.heavyLoadKg && stats.crashes > 0 {
                    fine = DrivingSession.unsafeLoadFine
                    stats.weighStationFines += fine
                }
                events.append(.weighedIn(cargoKg: cargoMassKg, fine: fine))
            } else {
                stats.tickets += 1
                stats.ticketCost += DrivingSession.weighStationSkipFine
                events.append(.skippedWeighStation(fine: DrivingSession.weighStationSkipFine, tooFast: signalledRight))
            }
        }
    }

    private func stepDeer(dt: Double, events: inout [SimEvent]) {
        if let d = deer {
            if time >= d.leavesAt {
                deer = nil
                if d.scared { stats.deerScared += 1 }
                events.append(.deerGone(scared: d.scared))
                return
            }
            // Reaching it: fast is a crash; slow, it jumps out of the way.
            if truck.position >= d.position - 2 {
                deer = nil
                if truck.speed > DrivingSession.deerSafeSpeed {
                    events.append(.crashed(.animal))
                    recover()
                    events.append(.rumbleStrip(nil))
                } else {
                    events.append(.deerGone(scared: false))
                }
            }
            return
        }
        guard wildlifeEnabled, road.hasWildlife else { return }
        deerTimer -= dt
        guard deerTimer <= 0 else { return }
        deerTimer = Double.random(in: timeOfDay.deerInterval, using: &rng)
        let spot = truck.position + 220
        // Not in towns or work zones, and not right before the end of the road.
        guard truck.speed > 8, road.loops || spot < road.totalLength - 300, road.speedZone(at: spot) == nil else { return }
        deer = Deer(position: spot, leavesAt: time + Double.random(in: 8...14, using: &rng))
        events.append(.deerAhead(distance: 220))
    }

    // MARK: - Police

    private func checkPolice(dt: Double, events: inout [SimEvent]) {
        // Turbo Mode: the police leave you alone.
        guard !turbo else { return }
        if var c = chase {
            c.timer += dt
            if truck.speed < 0.3 {
                let fine = DrivingSession.speedingFine(speed: c.speed, limit: c.limit)
                stats.tickets += 1
                stats.ticketCost += fine
                chase = nil
                events.append(.speedingTicket(speed: c.speed, limit: c.limit, fine: fine))
            } else if c.timer > DrivingSession.pullOverTime {
                let fine = DrivingSession.speedingFine(speed: c.speed, limit: c.limit) * 3 + 500
                stats.tickets += 1
                stats.ticketCost += fine
                chase = nil
                events.append(.fledPolice(fine: fine))
            } else {
                chase = c
            }
            return
        }
        for spot in road.policeSpots where abs(truck.position - spot) < DrivingSession.policeRange {
            let present: Bool
            if let decided = policeDecided[spot] {
                present = decided
            } else {
                present = Double.random(in: 0...1, using: &rng) < policePresenceChance
                policeDecided[spot] = present
                if present && truck.speed > 1 { events.append(.passedPolice) }
            }
            guard present else { continue }
            let limit = currentSpeedLimit
            if truck.speed > limit + DrivingSession.speedingTolerance {
                chase = (truck.speed, limit, 0)
                policeDecided[spot] = false // one stop per police car
                events.append(.policeChase(speed: truck.speed, limit: limit))
                return
            }
        }
    }

    // MARK: - Truck stops

    private func checkTruckStops(dt: Double, input: DrivingInput, events: inout [SimEvent]) {
        let fraction = truck.fuelLiters / spec.fuelCapacityLiters
        switch truckStopState {
        case .driving:
            // Stopped at a truck stop (just before or a little past it): say how to pull in, and let a right
            // signal pull in from there.
            if truck.speed < 0.3, let near = road.truckStopNear(truck.position, within: DrivingSession.truckStopStopRange) {
                if truck.signal == .on(.right) && truckStopState == .driving {
                    truckStopState = .pulledIn(index: near)
                    exitChecked = near
                    truck.signal = .off
                    events.append(.pulledIntoTruckStop)
                } else if hintedStop != near {
                    hintedStop = near
                    events.append(.atTruckStop)
                }
            } else if truck.speed > 5 {
                hintedStop = nil
            }
            guard truckStopState == .driving, let next = road.nextTruckStop(after: truck.position) else { break }
            // Heads-up when fuel is under half.
            if next.distance < 1_500 && announcedStop != next.index && fraction < 0.5 && truck.speed > 2 {
                announcedStop = next.index
                events.append(.truckStopAhead(distance: next.distance))
            }
            // Taking the exit: right signal on while passing the truck stop, slowly enough.
            if next.distance < 40 && exitChecked != next.index && truck.signal == .on(.right) {
                exitChecked = next.index
                if truck.speed <= DrivingSession.truckStopExitSpeed {
                    truckStopState = .pulledIn(index: next.index)
                    truck.signal = .off
                    events.append(.pulledIntoTruckStop)
                } else {
                    events.append(.missedTruckStop(tooFast: true))
                }
            }
            if next.distance > 200 && exitChecked == next.index { exitChecked = nil }
            if next.distance > 2_000 && announcedStop == next.index { announcedStop = nil }

        case let .pulledIn(index):
            // Signed distance past the pump (negative = still before it), wrapped for looping roads.
            var past = truck.position - road.truckStops[index]
            if road.loops {
                if past > road.totalLength / 2 { past -= road.totalLength }
                if past < -road.totalLength / 2 { past += road.totalLength }
            }
            if truck.speed < 0.3 && past > -150 && past < 300 {
                truckStopState = .refueling(index: index, liters: 0)
                // A quick nap while the tank fills, if the driver has been at the wheel a while.
                if restEnabled && awakeTime >= Rest.napWorthwhile {
                    awakeTime = 0
                    stats.naps = (stats.naps ?? 0) + 1
                    events.append(.napped)
                }
                events.append(.refuelStarted)
            } else if past >= 300 {
                truckStopState = .driving
                events.append(.leftTruckStop)
            }

        case let .refueling(index, liters):
            let room = spec.fuelCapacityLiters - truck.fuelLiters
            let add = min(room, DrivingSession.pumpRate * dt)
            truck.fuelLiters += add
            let total = liters + add
            // Done when full, or when the driver drives off early.
            if truck.fuelLiters >= spec.fuelCapacityLiters - 0.01 || input.throttle > 0.3 {
                let cost = Int((total * DrivingSession.truckStopFuelPrice).rounded())
                stats.fuelBoughtLiters += total
                stats.fuelCost += cost
                truckStopState = .pulledIn(index: index)
                fuelWarned = truck.fuelLiters / spec.fuelCapacityLiters < 0.1
                warnedQuarter = truck.fuelLiters / spec.fuelCapacityLiters < 0.25
                events.append(.refueled(liters: total, cost: cost))
                // Parked at the pump: count as moving on so the next stop isn't another refuel.
                truckStopState = .driving
                exitChecked = index
            } else {
                truckStopState = .refueling(index: index, liters: total)
            }
        }
    }

    /// Out of fuel and stopped: a tow truck takes you to the next truck stop and puts in a quarter tank.
    private func checkTow(dt: Double, events: inout [SimEvent]) {
        guard truck.fuelLiters <= 0, truck.speed < 0.3 else { outOfFuelTimer = 0; return }
        outOfFuelTimer += dt
        guard outOfFuelTimer > 3 else { return }
        outOfFuelTimer = 0
        if let next = road.nextTruckStop(after: truck.position) {
            truck.position = road.normalized(truck.position + next.distance)
            truck.odometer += next.distance
        }
        recover()
        let liters = spec.fuelCapacityLiters * 0.25
        truck.fuelLiters = liters
        let fuelCost = Int((liters * DrivingSession.truckStopFuelPrice).rounded())
        stats.tows += 1
        stats.towCost += DrivingSession.towFee
        stats.fuelBoughtLiters += liters
        stats.fuelCost += fuelCost
        stats.drivingTime += DrivingSession.towSeconds
        fuelWarned = false
        warnedQuarter = true
        events.append(.towed(cost: DrivingSession.towFee, fuelCost: fuelCost))
    }

    private func checkLane(events: inout [SimEvent]) {
        let y = truck.lateralOffset
        // Lane changes: signalling left while crossing the center line means you meant to (passing).
        let leftNow = y < DrivingSession.centerLine
        if leftNow != inLeftLane {
            inLeftLane = leftNow
            if leftNow {
                if truck.signal == .on(.left) { targetLane = DrivingSession.leftLaneCenter }
            } else {
                targetLane = 0
            }
            events.append(.changedLane(toLeft: leftNow, oncoming: !road.leftLaneSameDirection))
        }
        let offRoad = y > DrivingSession.offRoadOffset || y < DrivingSession.leftOffRoadOffset
        if offRoad {
            let side: Side = y > 0 ? .right : .left
            if truck.speed > DrivingSession.shoulderSafeSpeed || !assist.usesSimpleHandling {
                events.append(.crashed(.leftRoad(side)))
                recover()
                events.append(.rumbleStrip(nil))
                return
            }
            // Slow enough: the truck rolls onto the gravel shoulder instead of crashing.
            truck.lateralOffset = y > 0 ? DrivingSession.offRoadOffset : DrivingSession.leftOffRoadOffset
            if truck.lateralVelocity * y > 0 { truck.lateralVelocity = 0 }
            truck.speed *= 0.995
            truck.headingError = 0
            if time - lastShoulderWarning > 4 {
                lastShoulderWarning = time
                events.append(.onShoulder(side))
            }
        }
        let side: Side? = y > DrivingSession.rumbleOffset ? .right : (y < DrivingSession.leftRumbleOffset ? .left : nil)
        if side != rumbleSide {
            rumbleSide = side
            events.append(.rumbleStrip(side))
        }
    }

    private func checkCurves(events: inout [SimEvent]) {
        let lookahead = max(200, truck.speed * (turbo ? 15 : 10)) // more warning when braking from Turbo speeds
        if let curve = forWeather(road.nextCurve(after: truck.position, within: lookahead)),
           curve.segmentIndex != announcedCurveIndex, truck.speed > 2 {
            announcedCurveIndex = curve.segmentIndex
            events.append(.curveAhead(curve))
        }
        let k = abs(road.curvature(at: truck.position))
        let lateralNeeded = truck.speed * truck.speed * k
        if k > 0, lateralNeeded > grip * 0.85, time - lastTooFastWarning > 4 {
            lastTooFastWarning = time
            events.append(.tooFastForCurve)
        }
    }
}

// MARK: - Traffic

/// Another vehicle on the road.
public struct TrafficVehicle: Equatable, Sendable {
    public let id: Int
    public let kind: VehicleKind
    /// Driving toward you in the left lane.
    public let oncoming: Bool
    /// Lateral centre of its lane, metres (0 = your lane).
    public var lane: Double
    /// Metres along the road.
    public var position: Double
    public var speed: Double

    public var length: Double { kind == .truck ? 14 : (kind == .pickup ? 5.5 : 4.5) }
    public var halfWidth: Double { kind == .truck ? 1.25 : 0.95 }
}

/// Where a vehicle is relative to you, for 3D sound.
public struct TrafficSound: Equatable, Sendable {
    public var id: Int
    public var kind: VehicleKind
    /// Metres ahead (negative = behind).
    public var distance: Double
    /// Metres to the right (negative = left).
    public var lateral: Double
    /// How fast the gap is closing, m/s (negative = moving apart). Used for Doppler.
    public var closingSpeed: Double
}

public extension DrivingSession {
    /// Vehicles within earshot, nearest first (at most four), for the 3D traffic sound.
    var trafficSounds: [TrafficSound] {
        traffic.map { v -> TrafficSound in
            let rel = v.position - truck.position
            let approach = v.oncoming ? truck.speed + v.speed : truck.speed - v.speed
            return TrafficSound(id: v.id, kind: v.kind, distance: rel, lateral: v.lane - truck.lateralOffset,
                                closingSpeed: rel >= 0 ? approach : -approach)
        }
        .filter { abs($0.distance) < 500 }
        .sorted { abs($0.distance) < abs($1.distance) }
        .prefix(4)
        .map { $0 }
    }
}

extension DrivingSession {
    static let truckLength = 16.0

    func stepTraffic(dt: Double, events: inout [SimEvent]) {
        guard trafficEnabled || rival != nil else { return }
        let pos = truck.position
        let roadAhead = road.loops ? Double.infinity : road.totalLength - pos
        let limit = road.speedLimit

        // Spawning: oncoming traffic on two-way roads, and now and then a slower vehicle ahead.
        oncomingTimer -= dt
        if trafficEnabled, oncomingTimer <= 0 {
            oncomingTimer = Double.random(in: 25...70, using: &rng) * timeOfDay.trafficFactor
            if !road.leftLaneSameDirection && roadAhead > 800 {
                nextVehicleID += 1
                traffic.append(TrafficVehicle(id: nextVehicleID, kind: randomKind(), oncoming: true,
                                              lane: DrivingSession.leftLaneCenter, position: pos + 700,
                                              speed: limit * Double.random(in: 0.85...1, using: &rng)))
            }
        }
        slowTimer -= dt
        if trafficEnabled, slowTimer <= 0 {
            let hasSlowAhead = traffic.contains { !$0.oncoming && $0.position > pos }
            if !hasSlowAhead && roadAhead > 900 && truck.speed > 5 {
                nextVehicleID += 1
                traffic.append(TrafficVehicle(id: nextVehicleID, kind: randomKind(), oncoming: false, lane: 0,
                                              position: pos + 500,
                                              speed: limit * Double.random(in: 0.55...0.75, using: &rng)))
                slowTimer = Double.random(in: 70...160, using: &rng) * timeOfDay.trafficFactor
            } else {
                slowTimer = 10
            }
        }

        // Moving, leaving, colliding and warning.
        var remove: Set<Int> = []
        let y = truck.lateralOffset
        for i in traffic.indices {
            let v = traffic[i]
            traffic[i].position += (v.oncoming ? -v.speed : v.speed) * dt
            let rel = traffic[i].position - pos
            if rel < -300 || rel > 1_200 || (!road.loops && !v.oncoming && traffic[i].position > road.totalLength - 80) {
                remove.insert(v.id)
                continue
            }
            let lateralOverlap = abs(y - v.lane) < 1.25 + v.halfWidth
            let front = traffic[i].position - v.length / 2, back = traffic[i].position + v.length / 2
            if lateralOverlap && front < pos && back > pos - DrivingSession.truckLength {
                if v.id == DrivingSession.rivalID {
                    rivalGhostUntil = time + 6
                    events.append(.bumpedRival)
                }
                events.append(.crashed(.collision(headOn: v.oncoming, vehicle: v.kind)))
                remove.insert(v.id)
                recover()
                events.append(.rumbleStrip(nil))
                continue
            }
            if v.oncoming {
                if rel > 0 && rel < 250 && y < -1.2 && !honked.contains(v.id) {
                    honked.insert(v.id)
                    events.append(.oncomingHorn)
                    if time - lastWrongSideWarning > 4 {
                        lastWrongSideWarning = time
                        events.append(.wrongSideOfRoad)
                    }
                }
            } else if abs(y - v.lane) < 2 && rel > 0 {
                let closing = truck.speed - v.speed
                if rel < 160 && closing > 1.5 && !warnedAhead.contains(v.id) {
                    warnedAhead.insert(v.id)
                    events.append(.vehicleAhead(distance: rel, speed: v.speed, kind: v.kind))
                }
                let gap = rel - v.length / 2
                if closing > 0.5 && gap < max(15, closing * 2.5) && time - lastTooClose > 3 {
                    lastTooClose = time
                    events.append(.tooClose)
                }
            }
        }
        if !remove.isEmpty { traffic.removeAll { remove.contains($0.id) } }
    }

    /// Puts the other player's truck on your road, where it is along the route, when it's within earshot.
    func placeRival() {
        traffic.removeAll { $0.id == DrivingSession.rivalID }
        guard trafficEnabled || rival != nil, let r = rival, !r.finished, !r.quit, time >= rivalGhostUntil,
              let mine = remaining else { return }
        let gap = mine - r.remaining
        guard abs(gap) < 900 else { return }
        traffic.append(TrafficVehicle(id: DrivingSession.rivalID, kind: .truck, oncoming: false, lane: r.lateral,
                                      position: truck.position + gap, speed: r.speed))
    }

    private func randomKind() -> VehicleKind {
        let r = Double.random(in: 0...1, using: &rng)
        return r < 0.55 ? .car : (r < 0.8 ? .pickup : .truck)
    }

    /// Clears traffic when the road changes (taking a junction).
    func clearTraffic() {
        traffic = []
        warnedAhead = []
        honked = []
    }
}
