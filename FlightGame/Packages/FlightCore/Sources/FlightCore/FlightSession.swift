import Foundation

/// What a flight is for.
public enum FlightGoal: Equatable, Sendable {
    /// Fly anywhere; land wherever you like.
    case freeFlight
    /// Fly to an airport, land and stop on its runway.
    case flyTo(String)
    /// Climb to this altitude (feet).
    case reachAltitude(feet: Double)
    /// Turn onto this heading and hold it.
    case turnTo(heading: Double)
}

/// Where a flight starts.
public enum FlightStart: Equatable, Sendable {
    /// Lined up at the start of an airport's runway, engine off.
    case runway(String)
    /// Already flying: position, altitude (m), heading, speed (m/s), throttle and flaps.
    case air(x: Double, y: Double, altitude: Double, heading: Double, speed: Double, throttle: Double, flaps: Int)

    /// Lined up on final approach to an airport, this many metres before the runway, on the glide path.
    public static func finalApproach(to id: String, metres: Double) -> FlightStart {
        let a = World.airport(id)!
        let r = a.runwayHeading * .pi / 180
        let t = a.threshold
        return .air(x: t.x - sin(r) * metres, y: t.y - cos(r) * metres,
                    altitude: (metres + FlightSession.aimPoint) * tan(FlightSession.glidePathDegrees * .pi / 180),
                    heading: a.runwayHeading, speed: 33, throttle: 0.35, flaps: 1)
    }
}

public struct FlightSummary: Equatable, Sendable {
    public var completed: Bool
    public var crash: CrashReason?
    public var landing: LandingRating?
    public var touchdownFPM: Int?
    /// Metres from the centreline at touchdown.
    public var centrelineOffset: Double?
    public var landedAt: String?
    public var flightTime: Double
    public var distance: Double
    public var message: String

    public init(completed: Bool, crash: CrashReason?, landing: LandingRating?, touchdownFPM: Int?, centrelineOffset: Double?,
                landedAt: String?, flightTime: Double, distance: Double, message: String) {
        self.completed = completed; self.crash = crash; self.landing = landing; self.touchdownFPM = touchdownFPM
        self.centrelineOffset = centrelineOffset; self.landedAt = landedAt; self.flightTime = flightTime
        self.distance = distance; self.message = message
    }
}

/// The flight model. Simple on purpose: it should feel like flying and be fair to fly by ear.
public final class FlightSession {
    public let spec: AircraftSpec
    public let goal: FlightGoal
    public var assist: FlightAssist

    // MARK: State
    public private(set) var x: Double
    public private(set) var y: Double
    /// Metres above the ground (the world is flat).
    public private(set) var altitude: Double
    public private(set) var heading: Double
    /// Degrees, nose up positive.
    public private(set) var pitch: Double = 0
    /// Degrees, right wing down positive.
    public private(set) var bank: Double = 0
    public private(set) var airspeed: Double
    public private(set) var verticalSpeed: Double = 0
    public private(set) var throttle: Double
    public private(set) var rpm: Double = 0
    public private(set) var flaps: Int
    public private(set) var engine: EngineState
    public private(set) var onGround: Bool
    public private(set) var stalled = false
    public private(set) var time: Double = 0
    public private(set) var distanceFlown: Double = 0
    public private(set) var summary: FlightSummary?
    /// Autopilot targets: altitude (m) and heading.
    public private(set) var autopilot: (altitude: Double, heading: Double)?
    /// Has been in the air this flight.
    public private(set) var hasFlown = false

    private var touchdown: (rating: LandingRating, fpm: Int, offset: Double, airport: String)?
    private var warned: Set<String> = []
    private var lastCallout = Int.max
    private var approachAnnounced = false
    private var headingHeld: Double = 0

    public static let glidePathDegrees = 3.0
    /// Where the glide path meets the runway: this far past its start, metres.
    public static let aimPoint = 300.0
    /// Landing speed with flaps, about 65 knots.
    public static let approachSpeed = 33.0
    static let gravity = 9.81
    static let calloutFeet = [1_000, 500, 200, 100, 50, 40, 30, 20, 10]

    public init(spec: AircraftSpec = .trainer, start: FlightStart, goal: FlightGoal, assist: FlightAssist = .standard) {
        self.spec = spec
        self.goal = goal
        self.assist = assist
        switch start {
        case let .runway(id):
            let a = World.airport(id) ?? World.airports[0]
            let r = a.runwayHeading * .pi / 180
            let t = a.threshold
            x = t.x + sin(r) * 60
            y = t.y + cos(r) * 60
            altitude = 0
            heading = a.runwayHeading
            airspeed = 0
            throttle = 0
            flaps = 0
            engine = .off
            onGround = true
        case let .air(px, py, alt, hdg, speed, thr, fl):
            x = px; y = py; altitude = alt; heading = hdg; airspeed = speed; throttle = thr; flaps = fl
            engine = .running
            rpm = spec.idleRPM + (spec.maxRPM - spec.idleRPM) * thr
            onGround = false
            hasFlown = true
            // Trimmed for level flight (or the glide path on final).
            pitch = 2
        }
        lastCallout = Units.feet(altitude) + 1
    }

    // MARK: Readings

    public var destination: Airport? {
        if case let .flyTo(id) = goal { return World.airport(id) }
        return nil
    }

    /// The airport to guide toward: the destination, or the nearest one.
    public var guideAirport: Airport {
        destination ?? World.airports.min { World.distance(fromX: x, y: y, to: $0) < World.distance(fromX: x, y: y, to: $1) }!
    }

    public var stallSpeedNow: Double {
        // Ground effect: within a wingspan of the runway the wing gets extra lift.
        let groundEffect = altitude < 6 ? 0.88 + 0.02 * altitude : 1
        return spec.stallSpeed(flaps: flaps) * groundEffect / sqrt(max(0.3, cos(bank * .pi / 180)))
    }

    public var instruments: InstrumentReading {
        InstrumentReading(airspeedKnots: Units.knots(airspeed), altitudeFeet: Units.feet(altitude),
                          verticalSpeedFPM: Units.feetPerMinute(verticalSpeed), heading: heading, bank: bank, pitch: pitch,
                          throttlePercent: Int((throttle * 100).rounded()), flaps: flaps, engine: engine,
                          onGround: onGround, autopilot: autopilot != nil)
    }

    public var navigation: NavigationReading {
        let a = guideAirport
        let b = World.bearing(fromX: x, y: y, to: a)
        return NavigationReading(airport: a.name, runway: a.runwayName, distance: World.distance(fromX: x, y: y, to: a),
                                 bearing: b, turn: Units.turn(from: heading, to: b), isDestination: destination != nil)
    }

    /// Landing guidance once lined up with the guide airport's runway: how far right of the centreline (m) and
    /// how far above the glide path (m) you are. Nil when not on an approach.
    public var approach: (lateral: Double, aboveGlidePath: Double, distance: Double)? {
        guard !onGround else { return nil }
        let a = guideAirport
        let c = a.runwayCoordinates(x: x, y: y)
        let before = -c.along
        // From 18 km out until the far half of the runway; the glide path aims at a touchdown point past the threshold.
        guard before > -a.runwayLength / 2, before < 18_000, abs(Units.turn(from: heading, to: a.runwayHeading)) < 45,
              abs(c.across) < max(0, before) * tan(20 * .pi / 180) + 300 else { return nil }
        let toAim = before + Self.aimPoint
        let pathAltitude = max(0, toAim * tan(Self.glidePathDegrees * .pi / 180))
        return (c.across, altitude - pathAltitude, before)
    }

    /// Metres right of the runway centreline while on the ground (nil off any runway).
    public var runwayOffset: Double? {
        guard onGround, let a = World.runway(atX: x, y: y, margin: 30) else { return nil }
        return a.runwayCoordinates(x: x, y: y).across
    }

    // MARK: Actions

    public func perform(_ action: FlightAction) -> [FlightEvent] {
        switch action {
        case .toggleEngine:
            switch engine {
            case .off:
                engine = .starting(remaining: 2.5)
                return [.engineStarting]
            case .starting, .running:
                engine = .off
                autopilot = nil
                return [.engineStopped]
            }
        case .throttleUp: return setThrottle(throttle + 0.1)
        case .throttleDown: return setThrottle(throttle - 0.1)
        case .throttleFull: return setThrottle(1)
        case .throttleIdle: return setThrottle(0)
        case .flapsDown:
            guard flaps < 2 else { return [.flaps(flaps)] }
            if airspeed > 45 && !onGround { return [.flapsTooFast] }
            flaps += 1
            return [.flaps(flaps)]
        case .flapsUp:
            flaps = max(0, flaps - 1)
            return [.flaps(flaps)]
        case .toggleAutopilot:
            if autopilot != nil {
                autopilot = nil
                return [.autopilotOff]
            }
            guard !onGround, engine == .running else { return [.autopilotNeedsAir] }
            // Hold the current heading, and the current altitude rounded to 100 feet.
            let feet = (Double(Units.feet(altitude)) / 100).rounded() * 100
            autopilot = (Units.metres(feet: max(500, feet)), Units.heading((heading / 5).rounded() * 5))
            return [.autopilotOn(altitudeFeet: Int(max(500, feet)), heading: autopilot!.heading)]
        case .speakInstruments:
            return [.instruments(instruments)]
        case .speakNavigation:
            return [.navigation(navigation)]
        }
    }

    private func setThrottle(_ value: Double) -> [FlightEvent] {
        throttle = (min(1, max(0, value)) * 10).rounded() / 10
        var events: [FlightEvent] = [.throttle(percent: Int((throttle * 100).rounded()))]
        if engine == .off && throttle > 0 { events.append(.engineNotRunning) }
        return events
    }

    // MARK: Simulation

    public func step(dt: Double, input raw: FlightInput) -> [FlightEvent] {
        guard summary == nil else { return [] }
        var events: [FlightEvent] = []
        time += dt

        // Engine.
        if case let .starting(remaining) = engine {
            if remaining - dt <= 0 { engine = .running; events.append(.engineStarted) }
            else { engine = .starting(remaining: remaining - dt) }
        }
        let running = engine == .running
        let power = running ? throttle : 0
        let targetRPM = running ? spec.idleRPM + (spec.maxRPM - spec.idleRPM) * throttle
                                : (onGround ? 0 : min(spec.idleRPM, airspeed * 15)) // windmilling in the air
        rpm += (targetRPM - rpm) * min(1, dt * 2.5)

        var input = raw
        events += applyAutopilot(&input)
        // Easy: on a landing approach the throttle holds landing speed for you, until it's time to flare.
        if assist == .easy, autopilot == nil, approach != nil, Units.feet(altitude) > 40 {
            let wanted = max(0, min(0.8, throttle + (Self.approachSpeed - airspeed) * 0.02 * dt * 10))
            throttle = wanted
        }

        if onGround { groundStep(dt: dt, input: input, power: power, events: &events) }
        else { airStep(dt: dt, input: input, power: power, events: &events) }

        let h = heading * .pi / 180
        let horizontal = sqrt(max(0, airspeed * airspeed - verticalSpeed * verticalSpeed))
        x += sin(h) * horizontal * dt
        y += cos(h) * horizontal * dt
        distanceFlown += horizontal * dt

        checkGoal(events: &events)
        return events
    }

    private func applyAutopilot(_ input: inout FlightInput) -> [FlightEvent] {
        guard let ap = autopilot else { return [] }
        // Grabbing the controls hands the plane back to you.
        if abs(input.pitch) > 0.4 || abs(input.roll) > 0.4 || onGround || engine != .running {
            autopilot = nil
            return [.autopilotOff]
        }
        let turn = Units.turn(from: heading, to: ap.heading)
        let targetBank = max(-25, min(25, turn * 1.5))
        input.roll = max(-1, min(1, (targetBank - bank) / 12))
        let targetVS = max(-4, min(4, (ap.altitude - altitude) / 15))
        let targetPitch = asin(max(-0.3, min(0.3, targetVS / max(airspeed, 20)))) * 180 / .pi + 1.5
        input.pitch = max(-1, min(1, (targetPitch - pitch) / 4))
        return []
    }

    private func groundStep(dt: Double, input: FlightInput, power: Double, events: inout [FlightEvent]) {
        // Steering with the nose wheel: strong when slow, gentle at takeoff speed.
        let steerRate = 14 * min(1, airspeed / 6 + 0.15) * max(0.25, 1 - airspeed / 45)
        if airspeed > 0.3 { heading = Units.heading(heading + input.roll * steerRate * dt) }
        bank += (0 - bank) * min(1, dt * 4)

        let rolling = airspeed > 0.1 ? 0.25 : 0
        let braking = input.brake ? 3.5 : 0
        var accel = spec.thrust * power - spec.dragK * airspeed * airspeed - rolling - braking
        if airspeed <= 0.1 && accel < 0 { accel = 0 }
        airspeed = max(0, airspeed + accel * dt)
        verticalSpeed = 0
        altitude = 0

        // Lift the nose at rotation speed, then the plane flies.
        if airspeed >= spec.rotateSpeed * 0.95, input.pitch > 0.1 {
            pitch = min(12, pitch + input.pitch * 6 * dt)
        } else {
            pitch += (0 - pitch) * min(1, dt * 3)
        }
        if pitch > 4, airspeed > spec.stallSpeed(flaps: flaps) * 1.1 {
            onGround = false
            hasFlown = true
            altitude = 0.2
            events.append(.liftoff)
            return
        }

        // Staying on the runway.
        if airspeed > 1 {
            if let a = World.runway(atX: x, y: y) {
                let across = abs(a.runwayCoordinates(x: x, y: y).across)
                if across > Airport.runwayHalfWidth - 6, once("edge\(Int(time / 3))") { events.append(.runwayEdge) }
            } else if airspeed > 18 {
                crash(.ranOffRunway, events: &events)
            } else if once("grass") {
                airspeed = min(airspeed, 3)
                events.append(.stoppedOffRunway)
            }
        }
    }

    private func airStep(dt: Double, input: FlightInput, power: Double, events: inout [FlightEvent]) {
        var pitchIn = input.pitch, rollIn = input.roll
        let vStall = stallSpeedNow

        // Assists.
        // Easy: no pulling into a stall. Near the ground (the flare) it only stops you pulling further.
        if assist == .easy, airspeed < vStall * 1.15, pitchIn > 0 {
            pitchIn = 0
            if Units.feet(altitude) > 60 { pitch -= 3 * dt }
        }
        if assist != .off, abs(rollIn) < 0.05, autopilot == nil {
            bank += (0 - bank) * min(1, dt * (assist == .easy ? 1.2 : 0.7))
        }
        if assist == .easy, abs(pitchIn) < 0.05, autopilot == nil {
            pitch += (1.5 - pitch) * min(1, dt * 0.6)
        }

        // In a stall the elevator barely works, so the nose drops whatever you do.
        if stalled { pitchIn = min(pitchIn, 0.3) }
        bank = max(-65, min(65, bank + rollIn * 35 * dt))
        pitch = max(-25, min(25, pitch + pitchIn * 10 * dt))

        // Lift: the flight path follows the nose, less so near the stall; banking costs lift.
        // A stall lasts until the nose is down and the speed is back.
        let wasStalled = stalled
        if stalled { stalled = !(pitch < 3 && airspeed > vStall * 1.05) }
        else { stalled = airspeed < vStall }
        var targetVS: Double
        if stalled {
            // Close to the runway a stall just lets the plane settle; higher up the nose drops hard.
            let low = altitude < 5
            targetVS = low ? -2.2 : -9
            pitch -= (low ? 1.5 : 9) * dt
            if Int(time * 2) % 2 == 0 { bank += (bank >= 0 ? 4 : -4) * dt } // a wing drops a little
            if !wasStalled { events.append(.stalled) }
        } else {
            let liftEfficiency = min(1, (airspeed - vStall) / 8 + 0.2)
            var gamma = pitch * liftEfficiency - 1.0
            gamma -= (1 - cos(bank * .pi / 180)) * 14
            gamma -= Double(flaps) * 0.6
            targetVS = airspeed * sin(gamma * .pi / 180)
        }
        verticalSpeed += (targetVS - verticalSpeed) * min(1, dt * 1.5)

        let flapDrag = Double(flaps) * 0.00035 * airspeed * airspeed
        let accel = spec.thrust * power - spec.dragK * airspeed * airspeed - flapDrag
            - Self.gravity * verticalSpeed / max(airspeed, 10)
        airspeed = max(0, airspeed + accel * dt)

        let turnRate = Self.gravity * tan(bank * .pi / 180) / max(airspeed, 15) * 180 / .pi
        heading = Units.heading(heading + turnRate * dt)
        altitude += verticalSpeed * dt

        // Warnings.
        if !stalled, airspeed < vStall * 1.12, altitude > 10 {
            if once("stall\(Int(time / 4))") { events.append(.stallWarning) }
        }
        if airspeed > spec.maxSpeed, once("overspeed\(Int(time / 5))") { events.append(.overspeed) }
        if abs(bank) > 45, once("bank\(Int(time / 5))") { events.append(.steepBank) }

        // Height callouts near an airport while coming down.
        let feet = Units.feet(altitude)
        if verticalSpeed < -0.5, World.distance(fromX: x, y: y, to: guideAirport) < 9_000 {
            for c in Self.calloutFeet where feet <= c && lastCallout > c {
                events.append(.altitudeCallout(feet: c))
            }
        }
        lastCallout = feet

        if !approachAnnounced, let ap = approach, ap.distance < 15_000 {
            approachAnnounced = true
            events.append(.approachCaptured(airport: guideAirport.name, runway: guideAirport.runwayName))
        }

        if altitude <= 0 { land(events: &events) }
    }

    private func land(events: inout [FlightEvent]) {
        altitude = 0
        let fpm = Units.feetPerMinute(verticalSpeed)
        guard let a = World.runway(atX: x, y: y, margin: 8) else {
            crash(.offAirport, events: &events)
            return
        }
        if pitch < -5 { crash(.nosedIn, events: &events); return }
        if verticalSpeed < -4.2 || abs(bank) > 12 { crash(.hardLanding, events: &events); return }
        let rating = LandingRating.from(feetPerMinute: fpm)
        let offset = a.runwayCoordinates(x: x, y: y).across
        touchdown = (rating, fpm, offset, a.id)
        onGround = true
        stalled = false
        verticalSpeed = 0
        bank = 0
        autopilot = nil
        events.append(.touchdown(rating, feetPerMinute: fpm))
    }

    private func crash(_ reason: CrashReason, events: inout [FlightEvent]) {
        airspeed = 0
        verticalSpeed = 0
        engine = .off
        autopilot = nil
        events.append(.crashed(reason))
        finish(completed: false, crash: reason, message: reason.spoken)
    }

    private func checkGoal(events: inout [FlightEvent]) {
        guard summary == nil else { return }
        switch goal {
        case .freeFlight:
            if let t = touchdown, onGround, airspeed < 2 {
                let name = World.airport(t.airport)?.name ?? "the airport"
                complete("Landed and stopped at \(name). \(t.rating.spoken)", events: &events)
            }
        case let .flyTo(id):
            if let t = touchdown, onGround, airspeed < 2 {
                let name = World.airport(t.airport)?.name ?? "the airport"
                if t.airport == id {
                    complete("Welcome to \(name)! Flight complete. \(t.rating.spoken)", events: &events)
                } else {
                    complete("You landed at \(name) instead of \(World.airport(id)?.name ?? "your destination"). A safe landing still counts.", events: &events)
                }
            }
        case let .reachAltitude(feet):
            if !onGround, Double(Units.feet(altitude)) >= feet - 30 {
                complete("You've reached \(Int(feet)) feet. Takeoff lesson complete!", events: &events)
            }
        case let .turnTo(target):
            if !onGround, abs(Units.turn(from: heading, to: target)) < 6, abs(bank) < 8 {
                headingHeld += 1.0 / 60
                if headingHeld > 3 { complete("Steady on heading \(Units.headingWords(target)). Turn lesson complete!", events: &events) }
            } else {
                headingHeld = 0
            }
        }
    }

    private func complete(_ message: String, events: inout [FlightEvent]) {
        events.append(.goalComplete(message))
        finish(completed: true, crash: nil, message: message)
    }

    private func finish(completed: Bool, crash: CrashReason?, message: String) {
        summary = FlightSummary(completed: completed, crash: crash, landing: touchdown?.rating, touchdownFPM: touchdown?.fpm,
                                centrelineOffset: touchdown?.offset, landedAt: touchdown?.airport,
                                flightTime: time, distance: distanceFlown, message: message)
    }

    private func once(_ key: String) -> Bool { warned.insert(key).inserted }
}
