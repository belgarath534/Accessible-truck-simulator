import Foundation

/// How much the game helps keep the truck straight. Steering through curves is always up to the player.
public enum SteeringAssist: String, CaseIterable, Sendable {
    case off, low, medium, high

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
    public let road: Road
    public let goal: TripGoal
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

    private var announcedCurveIndex: Int?
    private var lastTooFastWarning: Double = -100
    private var rumbleSide: Side?
    private var fuelWarned = false
    private var lastEngineOffHint: Double = -100
    private var announcedMilestones: Set<Double> = []
    private var warnedDestination = false
    private var announcedAtDestination = false
    private var wasStopped = true

    public init(spec: TruckSpec = .starter, road: Road = .practiceLoop, goal: TripGoal = .freeDrive,
                assist: SteeringAssist = .medium) {
        self.spec = spec
        self.road = road
        self.goal = goal
        self.assist = assist
        self.truck = TruckState(fuelLiters: spec.fuelCapacityLiters)
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
            return [.roadAhead(road.nextCurve(after: truck.position, within: 3_000), remaining: remaining)]
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
            speedLimit: road.speedLimit
        )
    }

    /// Metres left to the drop-off (negative once past it), or nil on a free drive.
    public var remaining: Double? {
        goal.distance.map { $0 - truck.odometer }
    }

    /// Puts the truck back in the centre of its lane, stopped. Used after a crash.
    public func recover() {
        truck.lateralOffset = 0
        truck.headingError = 0
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
        updateStats(dt: dt, events: events)
        checkTrip(events: &events)
        return events
    }

    private func updateStats(dt: Double, events: [SimEvent]) {
        if stats.drivingTime > 0 || truck.speed > 0.1 { stats.drivingTime += dt }
        stats.distance = truck.odometer
        stats.topSpeed = max(stats.topSpeed, truck.speed)
        stats.fuelUsedLiters = spec.fuelCapacityLiters - truck.fuelLiters
        for event in events {
            switch event {
            case .crashed: stats.crashes += 1
            case .tooFastForCurve: stats.tooFastWarnings += 1
            default: break
            }
        }
    }

    private func checkTrip(events: inout [SimEvent]) {
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
        let mass = spec.massKg
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
        let brake = input.brake * spec.maxBrakeDecel * mass

        var accel = (driveForce - aero - rolling) / mass
        let decelFromBrakes = brake / mass
        accel -= truck.speed > 0 ? decelFromBrakes : 0

        truck.speed = max(0, truck.speed + accel * dt)
        if truck.speed < 0.05 && input.throttle < 0.05 { truck.speed = 0 }

        truck.position = road.normalized(truck.position + truck.speed * dt)
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

        // Kinematic bicycle model in road-relative coordinates.
        let kRoad = road.curvature(at: truck.position)
        var headingRate = v * tan(truck.steerAngle) / spec.wheelbase - v * kRoad
        if abs(input.steer) < 0.1 && v > 0.5 {
            headingRate -= assist.alignRate * truck.headingError
        }
        truck.headingError += headingRate * dt
        truck.headingError = min(max(truck.headingError, -0.6), 0.6)
        truck.lateralOffset += v * sin(truck.headingError) * dt
    }

    private func stepTemperatureAndFuel(dt: Double, events: inout [SimEvent]) {
        let running = truck.engine == .running
        let targetTemp = running ? 82 + 10 * truck.engineLoad : 20
        let rate = running ? 0.01 : 0.003
        truck.engineTempC += (targetTemp - truck.engineTempC) * min(1, dt * rate)

        guard running else { return }
        let powerKW = spec.torque(atRPM: truck.rpm) * truck.engineLoad * truck.rpm * 2 * .pi / 60 / 1000
        let litersPerSecond = 0.0005 + powerKW * 0.252 / 3600
        truck.fuelLiters = max(0, truck.fuelLiters - litersPerSecond * dt)
        if truck.fuelLiters <= 0 {
            truck.engine = .off
            events.append(.outOfFuel)
            events.append(.engineStopped)
        } else if !fuelWarned && truck.fuelLiters / spec.fuelCapacityLiters < 0.1 {
            fuelWarned = true
            events.append(.lowFuel)
        }
    }

    private func checkLane(events: inout [SimEvent]) {
        let y = truck.lateralOffset
        if abs(y) > DrivingSession.offRoadOffset {
            let side: Side = y > 0 ? .right : .left
            events.append(.crashed(.leftRoad(side)))
            recover()
            events.append(.rumbleStrip(nil))
            return
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
