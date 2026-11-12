import XCTest
@testable import FlightCore

final class TutorialTests: XCTestCase {
    /// A student who does what the teacher says, one step at a time, in Easy assist like the real tutorial.
    func testAStudentCanFinishTheWholeTutorial() {
        let s = FlightSession(start: .runway("pine"), goal: .tutorial, assist: .easy)
        var t = Tutorial()
        var spoken: [String] = []
        var seen: [Tutorial.Step] = []
        var acted: Set<Int> = []
        var pilot = RobotPilot(targetPitch: 0)
        var crashed = false

        for frame in 0..<(60 * 900) {
            var actions: [FlightAction] = []
            func once(_ a: FlightAction) {
                if acted.insert(t.step.rawValue * 100 + actions.count).inserted { actions.append(a); _ = s.perform(a) }
            }
            if seen.last != t.step { seen.append(t.step) }
            var input = FlightInput()
            switch t.step {
            case .engine: once(.toggleEngine)
            case .throttleUp: once(.throttleUp)
            case .throttleIdle: once(.throttleDown)
            case .instruments: once(.speakInstruments)
            case .takeoffRoll: once(.throttleFull); pilot.targetPitch = 0; input = pilot.input(s)
            case .rotate, .climb: pilot.targetPitch = 8; input = pilot.input(s)
            case .levelOff:
                if frame % 30 == 0, s.throttle > 0.72 { _ = s.perform(.throttleDown) }
                pilot.targetPitch = 1.5; pilot.targetBank = 0; input = pilot.input(s)
            case .turn: pilot.targetPitch = 3; pilot.targetBank = 25; input = pilot.input(s)
            case .levelWings: pilot.targetBank = 0; input = pilot.input(s)
            case .descend:
                if frame % 30 == 0, s.throttle > 0.32 { _ = s.perform(.throttleDown) }
                pilot.targetPitch = -2; input = pilot.input(s)
            case .flapsDown:
                pilot.targetPitch = 0; input = pilot.input(s)
                if s.airspeed < 44, s.flaps == 0, frame % 30 == 0 { _ = s.perform(.flapsDown) }
            case .flapsUp: once(.flapsUp); pilot.targetPitch = 1; input = pilot.input(s)
            case .stallTalk: pilot.targetPitch = 2; input = pilot.input(s)
            case .navigation: once(.speakNavigation); input = pilot.input(s)
            case .autopilot: once(.toggleAutopilot)
            case .done: break
            }
            let events = s.step(dt: 1.0 / 60, input: input)
            if events.contains(where: { if case .crashed = $0 { return true }; return false }) { crashed = true }
            spoken += t.update(session: s, actions: actions, dt: 1.0 / 60)
            if t.isComplete { break }
        }
        XCTAssertFalse(crashed)
        XCTAssertTrue(t.isComplete, "stuck at \(t.step) after \(Int(s.time)) seconds, at \(Units.feet(s.altitude)) feet, \(Units.knots(s.airspeed)) knots, throttle \(s.throttle), vs \(s.verticalSpeed)")
        XCTAssertEqual(seen, Array(Tutorial.Step.allCases.dropLast()), "every step, in order")
        XCTAssertTrue(spoken.first?.hasPrefix("Welcome to your first flight") ?? false)
        XCTAssertTrue(spoken.contains { $0.contains("Flaps are panels") })
        XCTAssertLessThan(s.time, 600, "about five to ten minutes")
        s.endFlight(message: Tutorial.completionMessage)
        XCTAssertEqual(s.summary?.completed, true)
    }

    func testRemindersAndRetryAfterACrash() {
        let s = FlightSession(start: .runway("pine"), goal: .tutorial, assist: .easy)
        var t = Tutorial()
        var lines: [String] = []
        for _ in 0..<(60 * 30) { lines += t.update(session: s, actions: [], dt: 1.0 / 60) }
        XCTAssertEqual(lines.count, 2, "the instruction, then one reminder")
        XCTAssertEqual(lines.last, "Tap twice with three fingers to start the engine.")

        // A crash on the takeoff: back to the runway with the engine already running.
        var ground = Tutorial()
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 4) { _ = s.step(dt: 1.0 / 60, input: FlightInput()); _ = ground.update(session: s, actions: [], dt: 1.0 / 60) }
        XCTAssertEqual(ground.step, .throttleUp)
        let r = ground.retry()
        XCTAssertEqual(r.start, .runway("pine"))
        XCTAssertTrue(ground.retryEngineRunning)
        let again = FlightSession(start: r.start, goal: .tutorial, assist: .easy)
        again.startEngineNow()
        XCTAssertEqual(again.engine, .running)
        XCTAssertEqual(ground.update(session: again, actions: [], dt: 1.0 / 60).first, Tutorial.instruction(.throttleUp))
    }

    func testGroundSchoolCoversTheParts() {
        let titles = GroundSchool.parts.map(\.title)
        for word in ["Flaps", "Throttle", "Elevator", "Ailerons", "Wings"] { XCTAssertTrue(titles.contains { $0.contains(word) }, word) }
        XCTAssertTrue(GroundSchool.ideas.contains { $0.title == "Stall" })
    }
}
