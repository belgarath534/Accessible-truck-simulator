import XCTest
@testable import FlightCore

/// Flies the plane with simple control laws, the way a careful pilot would.
struct RobotPilot {
    var targetPitch = 6.0
    var targetBank = 0.0
    var brake = false

    func input(_ s: FlightSession) -> FlightInput {
        if s.onGround {
            let steer = -(s.runwayOffset ?? 0) / 8 - Units.turn(from: World.runway(atX: s.x, y: s.y, margin: 30)?.runwayHeading ?? s.heading, to: s.heading) / 6
            let pull = s.airspeed >= s.spec.rotateSpeed ? max(0, min(1, (targetPitch - s.pitch) / 3)) : 0
            return FlightInput(pitch: pull, roll: max(-1, min(1, steer)), brake: brake)
        }
        return FlightInput(pitch: max(-1, min(1, (targetPitch - s.pitch) / 3)),
                           roll: max(-1, min(1, (targetBank - s.bank) / 10)))
    }
}

func fly(_ s: FlightSession, seconds: Double, _ control: (FlightSession) -> FlightInput) -> [FlightEvent] {
    var events: [FlightEvent] = []
    for _ in 0..<Int(seconds * 60) {
        events += s.step(dt: 1.0 / 60, input: control(s))
        if s.summary != nil { break }
    }
    return events
}

final class FlightModelTests: XCTestCase {
    func testTakeoffLesson() {
        let s = FlightSession(start: Lesson.all[0].start, goal: Lesson.all[0].goal)
        XCTAssertEqual(s.perform(.toggleEngine), [.engineStarting])
        var events = fly(s, seconds: 3) { _ in FlightInput() }
        XCTAssertTrue(events.contains(.engineStarted))
        _ = s.perform(.throttleFull)
        let pilot = RobotPilot(targetPitch: 8)
        events = fly(s, seconds: 240) { pilot.input($0) }
        XCTAssertTrue(events.contains(.liftoff), "lifted off")
        XCTAssertFalse(events.contains { if case .crashed = $0 { return true }; return false }, "\(events)")
        XCTAssertEqual(s.summary?.completed, true, "reached 1,000 feet: \(String(describing: s.summary))")
        XCTAssertLessThan(s.summary?.flightTime ?? 999, 200)
    }

    func testLiftoffHappensOnTheRunway() {
        let s = FlightSession(start: .runway("pine"), goal: .freeFlight)
        _ = s.perform(.toggleEngine)
        _ = fly(s, seconds: 3) { _ in FlightInput() }
        _ = s.perform(.throttleFull)
        let pilot = RobotPilot(targetPitch: 8)
        var liftoffAlong: Double?
        for _ in 0..<(60 * 60) {
            let e = s.step(dt: 1.0 / 60, input: pilot.input(s))
            if e.contains(.liftoff) { liftoffAlong = World.airport("pine")!.runwayCoordinates(x: s.x, y: s.y).along; break }
        }
        let along = try? XCTUnwrap(liftoffAlong)
        XCTAssertLessThan(along ?? 9_999, World.airport("pine")!.runwayLength * 0.8)
    }

    func testTurnLesson() {
        let lesson = Lesson.all[1]
        let s = FlightSession(start: lesson.start, goal: lesson.goal)
        var pilot = RobotPilot(targetPitch: 3)
        var events: [FlightEvent] = []
        for _ in 0..<(60 * 200) {
            let turn = Units.turn(from: s.heading, to: 270)
            pilot.targetBank = abs(turn) > 15 ? 25 : turn * 1.2
            events += s.step(dt: 1.0 / 60, input: pilot.input(s))
            if s.summary != nil { break }
        }
        XCTAssertEqual(s.summary?.completed, true, "\(events)")
        XCTAssertGreaterThan(s.altitude, 500, "didn't lose much height in the turn")
    }

    func testAutopilotHoldsAltitudeAndHeading() {
        let s = FlightSession(start: .air(x: 0, y: 5_000, altitude: 610, heading: 45, speed: 52, throttle: 0.65, flaps: 0),
                              goal: .freeFlight, assist: .off)
        guard case .autopilotOn = s.perform(.toggleAutopilot).first else { return XCTFail("autopilot didn't engage") }
        _ = fly(s, seconds: 120) { _ in FlightInput() }
        XCTAssertEqual(Double(Units.feet(s.altitude)), 2_000, accuracy: 80)
        XCTAssertEqual(Units.turn(from: s.heading, to: 45), 0, accuracy: 3)
        // Grabbing the controls turns it off.
        let events = s.step(dt: 1.0 / 60, input: FlightInput(pitch: 1))
        XCTAssertTrue(events.contains(.autopilotOff))
    }

    func testLandingLessonWithTheLandingGuidance() {
        let lesson = Lesson.all[2]
        let s = FlightSession(start: lesson.start, goal: lesson.goal, assist: .standard)
        var events: [FlightEvent] = []
        var idle = false
        for _ in 0..<(60 * 400) {
            var input = FlightInput()
            if s.onGround {
                if !idle { _ = s.perform(.throttleIdle); idle = true }
                input = RobotPilot(targetPitch: 0, brake: true).input(s)
            } else if let ap = s.approach {
                // Steer toward the centreline, follow the glide path, flare near the ground.
                let wantedBank = max(-15, min(15, -ap.lateral / 12 - Units.turn(from: 90, to: s.heading) * 1.5))
                var targetPitch = -1.4 - ap.aboveGlidePath / 4
                if Units.feet(s.altitude) < 25 { targetPitch = 4; if !idle { _ = s.perform(.throttleIdle); idle = true } }
                input = RobotPilot(targetPitch: max(-6, min(6, targetPitch)), targetBank: wantedBank).input(s)
                if !idle { // hold landing speed with the throttle, like a pilot would
                    if s.airspeed < FlightSession.approachSpeed - 1 { _ = s.perform(.throttleUp) }
                    else if s.airspeed > FlightSession.approachSpeed + 1, s.throttle > 0.05 { _ = s.perform(.throttleDown) }
                }
            } else {
                // Past the guidance window (very close in): hold the flare.
                if !idle { _ = s.perform(.throttleIdle); idle = true }
                input = RobotPilot(targetPitch: 4).input(s)
            }
            events += s.step(dt: 1.0 / 60, input: input)
            if s.summary != nil { break }
        }
        XCTAssertFalse(events.contains { if case .crashed = $0 { return true }; return false }, "\(events)")
        XCTAssertTrue(events.contains { if case .touchdown = $0 { return true }; return false })
        XCTAssertTrue(events.contains(.altitudeCallout(feet: 100)))
        XCTAssertTrue(events.contains { if case .approachCaptured = $0 { return true }; return false })
        XCTAssertEqual(s.summary?.completed, true, "\(String(describing: s.summary))")
        XCTAssertEqual(s.summary?.landedAt, "pine")
    }

    func testEasyLandingWithAutoThrottle() {
        // Easy mode: the player only steers and follows the glide tones; the throttle holds the speed.
        let s = FlightSession(start: Lesson.all[2].start, goal: Lesson.all[2].goal, assist: .easy)
        var events: [FlightEvent] = []
        for _ in 0..<(60 * 400) {
            var input: FlightInput
            if s.onGround {
                if s.throttle > 0 { _ = s.perform(.throttleIdle) }
                input = RobotPilot(targetPitch: 0, brake: true).input(s)
            } else if let ap = s.approach, Units.feet(s.altitude) >= 25 {
                let wantedBank = max(-15, min(15, -ap.lateral / 12 - Units.turn(from: 90, to: s.heading) * 1.5))
                input = RobotPilot(targetPitch: max(-6, min(6, -1.4 - ap.aboveGlidePath / 4)), targetBank: wantedBank).input(s)
            } else {
                if s.throttle > 0 { _ = s.perform(.throttleIdle) }
                input = RobotPilot(targetPitch: 4).input(s)
            }
            events += s.step(dt: 1.0 / 60, input: input)
            if s.summary != nil { break }
        }
        XCTAssertEqual(s.summary?.completed, true, "\(events) \(String(describing: s.summary))")
    }

    func testCrossCountryLesson() {
        let lesson = Lesson.all[3]
        let s = FlightSession(start: lesson.start, goal: lesson.goal, assist: .standard)
        let dest = World.airport("harbor")!
        _ = s.perform(.toggleEngine)
        _ = fly(s, seconds: 3) { _ in FlightInput() }
        _ = s.perform(.throttleFull)
        var events: [FlightEvent] = []
        var phase = "climb"
        for _ in 0..<(60 * 1_500) {
            var input = FlightInput()
            let c = dest.runwayCoordinates(x: s.x, y: s.y)
            if s.onGround && !s.hasFlown {
                input = RobotPilot(targetPitch: 8).input(s)
            } else if s.onGround {
                if s.throttle > 0 { _ = s.perform(.throttleIdle) }
                input = RobotPilot(targetPitch: 0, brake: true).input(s)
            } else if phase == "flare" || (s.approach != nil && -c.along < 9_000) {
                if phase == "climb" || phase == "cruise" { phase = "final"; _ = s.perform(.flapsDown) }
                if phase == "flare" || Units.feet(s.altitude) < 25 {
                    phase = "flare"
                    if s.throttle > 0 { _ = s.perform(.throttleIdle) }
                    input = RobotPilot(targetPitch: 4).input(s)
                } else if let ap = s.approach {
                    let wantedHeading = dest.runwayHeading + max(-30, min(30, -ap.lateral / 25))
                    let bank = max(-20, min(20, Units.turn(from: s.heading, to: wantedHeading) * 1.5))
                    input = RobotPilot(targetPitch: max(-6, min(6, -1.4 - ap.aboveGlidePath / 4)), targetBank: bank).input(s)
                    if s.airspeed < FlightSession.approachSpeed - 1 { _ = s.perform(.throttleUp) }
                    else if s.airspeed > FlightSession.approachSpeed + 1, s.throttle > 0.05 { _ = s.perform(.throttleDown) }
                }
            } else {
                // Fly to a point 8 km out on the runway's extended centreline, at 1,500 feet.
                let r = dest.runwayHeading * .pi / 180
                let t = dest.threshold
                let gx = t.x - sin(r) * 8_000, gy = t.y - cos(r) * 8_000
                let toGate = hypot(gx - s.x, gy - s.y)
                let course = toGate > 800 ? Units.heading(atan2(gx - s.x, gy - s.y) * 180 / .pi) : dest.runwayHeading
                let bank = max(-25, min(25, Units.turn(from: s.heading, to: course) * 1.5))
                let wantAlt = Units.metres(feet: 1_500)
                let pitch = max(-4, min(8, (wantAlt - s.altitude) / 20 + 1))
                input = RobotPilot(targetPitch: pitch, targetBank: bank).input(s)
                if s.altitude > wantAlt - 30, s.throttle > 0.6 { _ = s.perform(.throttleDown) }
                if s.airspeed > 45, phase == "climb", s.altitude > wantAlt - 30 { phase = "cruise" }
            }
            events += s.step(dt: 1.0 / 60, input: input)
            if ProcessInfo.processInfo.environment["FLIGHT_DEBUG"] != nil, phase != "climb", phase != "cruise", Int(s.time * 60) % 60 == 0 || s.summary != nil {
                let ap = s.approach
                print(String(format: "DBG ft=%d v=%.1f along=%.0f across=%.0f hdg=%.0f bank=%.0f above=%.0f thr=%.1f", Units.feet(s.altitude), s.airspeed, c.along, c.across, s.heading, s.bank, ap?.aboveGlidePath ?? -999, s.throttle))
            }
            if s.summary != nil { break }
        }
        XCTAssertEqual(s.summary?.landedAt, "harbor", "\(String(describing: s.summary)) \(events.suffix(12))")
        XCTAssertEqual(s.summary?.completed, true)
    }

    func testStallAndCrash() {
        let s = FlightSession(start: .air(x: 0, y: 8_000, altitude: 300, heading: 0, speed: 40, throttle: 0, flaps: 0),
                              goal: .freeFlight, assist: .off)
        _ = s.perform(.throttleIdle)
        let events = fly(s, seconds: 120) { _ in FlightInput(pitch: 1) }
        XCTAssertTrue(events.contains(.stallWarning))
        XCTAssertTrue(events.contains(.stalled))
        XCTAssertNotNil(s.summary?.crash)
        XCTAssertEqual(s.summary?.completed, false)
    }

    func testEasyAssistPreventsStall() {
        let s = FlightSession(start: .air(x: 0, y: 8_000, altitude: 600, heading: 0, speed: 40, throttle: 0.6, flaps: 0),
                              goal: .freeFlight, assist: .easy)
        let events = fly(s, seconds: 60) { _ in FlightInput(pitch: 1) }
        XCTAssertFalse(events.contains(.stalled), "\(events)")
    }

    func testFlapsAndThrottle() {
        let s = FlightSession(start: .runway("pine"), goal: .freeFlight)
        XCTAssertEqual(s.perform(.throttleUp), [.throttle(percent: 10), .engineNotRunning])
        XCTAssertEqual(s.perform(.flapsDown), [.flaps(1)])
        XCTAssertEqual(s.perform(.flapsDown), [.flaps(2)])
        XCTAssertEqual(s.perform(.flapsDown), [.flaps(2)])
        XCTAssertEqual(s.perform(.flapsUp), [.flaps(1)])
        let fast = FlightSession(start: .air(x: 0, y: 0, altitude: 600, heading: 0, speed: 60, throttle: 0.8, flaps: 0), goal: .freeFlight)
        XCTAssertEqual(fast.perform(.flapsDown), [.flapsTooFast])
    }
}

final class WorldAndSpeechTests: XCTestCase {
    func testRunwayGeometry() {
        let a = World.airport("pine")!
        XCTAssertEqual(a.runwayName, "runway 9")
        XCTAssertTrue(a.isOnRunway(x: a.x, y: a.y))
        XCTAssertFalse(a.isOnRunway(x: a.x, y: a.y + 100))
        let c = a.runwayCoordinates(x: a.x, y: a.y - 10)   // 10 m south of centre on an east runway = right of it
        XCTAssertEqual(c.across, 10, accuracy: 1e-6)
        XCTAssertEqual(c.along, a.runwayLength / 2, accuracy: 1e-6)
        XCTAssertEqual(World.airport("summit")!.runwayName, "runway 1")
    }

    func testUnitsAndPhrases() {
        XCTAssertEqual(Units.headingWords(90), "zero niner zero")
        XCTAssertEqual(Units.headingWords(0), "three six zero")
        XCTAssertEqual(Units.turn(from: 350, to: 10), 20)
        XCTAssertEqual(Units.distance(9_260), "5 miles")
        XCTAssertEqual(Units.knots(25.72), 50)
        let s = FlightSession(start: .runway("pine"), goal: .flyTo("harbor"))
        let text = Phrases.instruments(s.instruments)
        XCTAssertTrue(text.hasPrefix("Engine off. Airspeed 0 knots. On the ground. Heading zero niner zero, east."), text)
        let nav = Phrases.navigation(s.navigation)
        XCTAssertTrue(nav.hasPrefix("Harbor City, your destination"), nav)
        XCTAssertTrue(nav.contains("turn left"), nav)
        for e in [FlightEvent.liftoff, .stalled, .altitudeCallout(feet: 50)] { XCTAssertNotNil(Phrases.event(e)) }
    }

    func testLogbook() {
        var log = Logbook()
        log.record(FlightSummary(completed: true, crash: nil, landing: .butter, touchdownFPM: -90, centrelineOffset: 2,
                                 landedAt: "pine", flightTime: 600, distance: 9_000, message: ""), lesson: 3)
        log.record(FlightSummary(completed: false, crash: .hardLanding, landing: nil, touchdownFPM: nil, centrelineOffset: nil,
                                 landedAt: nil, flightTime: 60, distance: 100, message: ""), lesson: nil)
        XCTAssertEqual(log.flights, 2)
        XCTAssertEqual(log.landings, 1)
        XCTAssertEqual(log.butterLandings, 1)
        XCTAssertEqual(log.crashes, 1)
        XCTAssertEqual(log.bestLandingFPM, 90)
        XCTAssertEqual(log.lessonsPassed, [3])
    }
}

final class GestureTests: XCTestCase {
    func testSwipesTapsDoubleTapsAndHold() {
        var g = GestureReader()
        _ = g.began(id: 1, x: 100, y: 200, time: 0)
        g.moved(id: 1, x: 100, y: 120, time: 0.1)
        XCTAssertEqual(g.ended(id: 1, x: 100, y: 120, time: 0.15), [.swipe(fingers: 1, .up)])
        XCTAssertEqual(GestureMap.command(for: .swipe(fingers: 1, .up)), .action(.throttleUp))

        // Three-finger double tap.
        for t in [1.0, 1.2] {
            for id in 1...3 { _ = g.began(id: id, x: Double(id) * 50, y: 100, time: t) }
            var out: [GestureReader.Gesture] = []
            for id in 1...3 { out += g.ended(id: id, x: Double(id) * 50, y: 100, time: t + 0.08) }
            if t == 1.2 { XCTAssertEqual(out, [.tap(fingers: 3, count: 2)]) } else { XCTAssertEqual(out, []) }
        }
        // A single two-finger tap is confirmed after the double-tap gap.
        _ = g.began(id: 1, x: 0, y: 0, time: 3); _ = g.began(id: 2, x: 50, y: 0, time: 3)
        _ = g.ended(id: 1, x: 0, y: 0, time: 3.1); _ = g.ended(id: 2, x: 50, y: 0, time: 3.1)
        XCTAssertEqual(g.update(time: 3.2), [])
        XCTAssertEqual(g.update(time: 3.5), [.tap(fingers: 2, count: 1)])
        // Hold.
        _ = g.began(id: 1, x: 0, y: 0, time: 5)
        XCTAssertEqual(g.update(time: 5.6), [.holdBegan])
        XCTAssertEqual(g.ended(id: 1, x: 0, y: 0, time: 6), [.holdEnded])
        XCTAssertEqual(GestureMap.command(for: .holdBegan), .brakes(true))
    }
}
