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
    public let cargoMassKg: Double
    /// Seconds allowed for a delivery job, if it has a deadline.
    public let timeLimit: Double?
    public var assist: SteeringAssist
    public private(set) var truck: TruckState
    public private(set) var time: Double = 0
    public private(set) var stats = TripStats()
    /// Set when the trip is finished; the simulation stops changing after that.
    public private(set) var summary: TripSummary?

    /// How close (metres) to the drop-off the truck must stop to finish the trip.
    public static let arrivalTolerance = 60.0
    static let milestones: [Double] = [10_000, 5_000, 2_000, 1_000]
    static let destinationWarning = 400.0

    // Lane geometry relative to lane centre.
    public static let rumbleOffset = 0.9
    public static let offRoadOffset = 2.6
    /// Fuel burns this many times faster than a real truck, so a full tank lasts about two hours of driving.
    public static let fuelGameScale = 10.0
    /// Dollars per litre at truck stops.
    public static let truckStopFuelPrice = 2.5
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
    private var rng: SeededRandom
    /// Chance a police car is at each spot (tests set it to 0 or 1).
    public var policePresenceChance = DrivingSession.policeChance
    /// True while a police car is behind you with its siren on.
    public var sirenOn: Bool { chase != nil }
    private var navAnnounced: Set<Int> = []
    private var lastShoulderWarning: Double = -100

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
            return [.horn]
        case .speakDashboard:
            return [.dashboard(dashboard)]
        case .speakRoadAhead:
            var events: [SimEvent] = [.roadAhead(road.nextCurve(after: truck.position, within: 3_000), remaining: remaining,
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

    /// Typical litres per metre at highway speed with the game's fuel scale (used before a trip is measured).
    public static let typicalFuelPerMetre = 0.12 / 22 * fuelGameScale / 18

    /// How far the fuel left will go, metres.
    public var range: Double { truck.fuelLiters / fuelPerMetre }

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
        checkPolice(dt: dt, events: &events)
        checkTruckStops(dt: dt, input: input, events: &events)
        checkTow(dt: dt, events: &events)
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
            let governed = truck.speed >= spec.speedLimiter
            let throttle = governed ? 0 : input.throttle
            let torque = spec.torque(atRPM: max(truck.rpm, spec.idleRPM)) * throttle
            driveForce = torque * ratio * spec.drivetrainEfficiency / spec.wheelRadius
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
        let brakeDecel = min(spec.maxBrakeDecel, spec.maxBrakeDecel * spec.massKg * 1.5 / mass)
        let brake = input.brake * brakeDecel * mass

        var accel = (driveForce - aero - rolling) / mass
        let decelFromBrakes = brake / mass
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
        let speedLimitedAngle = v > 1 ? spec.steeringLatAccel * spec.wheelbase / (v * v) : spec.maxSteerAngle
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
        let grip = spec.steeringLatAccel
        let overGrip = abs(curveAccel) / grip - 0.9
        if overGrip > 0 { push *= 1 + 4 * overGrip }
        // Barely any sideways movement while crawling.
        let speedFactor = min(1, v / 4)
        let target = (input.steer * assist.maxLateralSpeed + push) * speedFactor
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
        let litersPerSecond = (0.0005 + powerKW * 0.252 / 3600) * DrivingSession.fuelGameScale
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
        guard let nav = navigator else { return }
        let position = truck.position

        // Towns: speed limit changes.
        let zone = road.speedZone(at: position)
        if zone?.name != currentZone {
            if let zone {
                events.append(.enteredTown(name: zone.name, speedLimit: zone.limit))
            } else if let old = currentZone {
                events.append(.leftTown(name: old, speedLimit: road.speedLimit(at: position)))
            }
            currentZone = zone?.name
        }

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
        currentZone = road.speedZone(at: truck.position)?.name
        events.append(.tookRoad(roadName: result.choice.roadName, toward: result.choice.toward,
                                length: road.totalLength, turn: result.choice.turn))
        if !result.onRoute, let remaining {
            events.append(.rerouted(remaining: remaining))
        }
    }

    // MARK: - Police

    private func checkPolice(dt: Double, events: inout [SimEvent]) {
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
            guard let next = road.nextTruckStop(after: truck.position) else { break }
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
        if abs(y) > DrivingSession.offRoadOffset {
            let side: Side = y > 0 ? .right : .left
            if truck.speed > DrivingSession.shoulderSafeSpeed || !assist.usesSimpleHandling {
                events.append(.crashed(.leftRoad(side)))
                recover()
                events.append(.rumbleStrip(nil))
                return
            }
            // Slow enough: the truck rolls onto the gravel shoulder instead of crashing.
            truck.lateralOffset = DrivingSession.offRoadOffset * (y > 0 ? 1 : -1)
            if truck.lateralVelocity * y > 0 { truck.lateralVelocity = 0 }
            truck.speed *= 0.995
            truck.headingError = 0
            if time - lastShoulderWarning > 4 {
                lastShoulderWarning = time
                events.append(.onShoulder(side))
            }
        }
        let side: Side? = abs(y) > DrivingSession.rumbleOffset ? (y > 0 ? .right : .left) : nil
        if side != rumbleSide {
            rumbleSide = side
            events.append(.rumbleStrip(side))
        }
    }

    private func checkCurves(events: inout [SimEvent]) {
        let lookahead = max(200, truck.speed * 10)
        if let curve = road.nextCurve(after: truck.position, within: lookahead),
           curve.segmentIndex != announcedCurveIndex, truck.speed > 2 {
            announcedCurveIndex = curve.segmentIndex
            events.append(.curveAhead(curve))
        }
        let k = abs(road.curvature(at: truck.position))
        let lateralNeeded = truck.speed * truck.speed * k
        if k > 0, lateralNeeded > spec.steeringLatAccel * 0.85, time - lastTooFastWarning > 4 {
            lastTooFastWarning = time
            events.append(.tooFastForCurve)
        }
    }
}
