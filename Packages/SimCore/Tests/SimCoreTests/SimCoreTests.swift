import XCTest
@testable import SimCore

final class DrivingSessionTests: XCTestCase {
    private func drive(_ session: DrivingSession, seconds: Double, input: DrivingInput) -> [SimEvent] {
        var events: [SimEvent] = []
        let dt = 1.0 / 60
        for _ in 0..<Int(seconds / dt) { events += session.step(dt: dt, input: input) }
        return events
    }

    private func startEngine(_ s: DrivingSession) {
        XCTAssertEqual(s.perform(.toggleEngine), [.engineStarting])
        let events = drive(s, seconds: 2, input: .idle)
        XCTAssertTrue(events.contains(.engineStarted))
        XCTAssertEqual(s.truck.engine, .running)
    }

    func testEngineOffMeansNoMovement() {
        let s = DrivingSession(road: Road(segments: [.straight(5_000)]))
        _ = drive(s, seconds: 5, input: DrivingInput(throttle: 1))
        XCTAssertEqual(s.truck.speed, 0)
    }

    func testAcceleratesShiftsAndRespectsLimiter() {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]))
        startEngine(s)
        let events = drive(s, seconds: 10, input: DrivingInput(throttle: 1))
        XCTAssertGreaterThan(s.truck.speed, 5, "should be moving after 10 s")
        XCTAssertTrue(events.contains { if case .gearChanged(_, true) = $0 { return true }; return false })

        _ = drive(s, seconds: 120, input: DrivingInput(throttle: 1))
        XCTAssertLessThanOrEqual(s.truck.speed, s.spec.speedLimiter + 0.5)
        XCTAssertGreaterThan(s.truck.speed, s.spec.speedLimiter - 2, "should reach the governor on a long straight")
        XCTAssertLessThanOrEqual(s.truck.rpm, s.spec.maxRPM)
    }

    func testZeroToEightyTakesTruckLikeTime() {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]))
        startEngine(s)
        var t = 0.0
        while s.truck.speed < 80 / 3.6 && t < 120 {
            _ = s.step(dt: 1.0 / 60, input: DrivingInput(throttle: 1))
            t += 1.0 / 60
        }
        XCTAssertGreaterThan(t, 15, "a truck should not be a sports car")
        XCTAssertLessThan(t, 70, "but it should not be painfully slow either")
    }

    func testBrakingStops() {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]))
        startEngine(s)
        _ = drive(s, seconds: 30, input: DrivingInput(throttle: 1))
        _ = drive(s, seconds: 15, input: DrivingInput(brake: 1))
        XCTAssertEqual(s.truck.speed, 0)
    }

    func testStraightRoadStaysInLaneWithoutSteering() {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]))
        startEngine(s)
        _ = drive(s, seconds: 30, input: DrivingInput(throttle: 1))
        XCTAssertLessThan(abs(s.truck.lateralOffset), 0.01)
    }

    func testCurveWithoutSteeringRunsOffTheOutside() {
        // Right-hand curve: doing nothing should drift to the LEFT (outside) and crash.
        let s = DrivingSession(road: Road(segments: [.straight(600), .right(radius: 300, length: 2_000)], loops: false))
        startEngine(s)
        let events = drive(s, seconds: 90, input: DrivingInput(throttle: 0.7))
        XCTAssertTrue(events.contains(.crashed(.leftRoad(.left))), "events: \(events)")
        XCTAssertTrue(events.contains { if case .curveAhead(let c) = $0 { return c.direction == .right }; return false })
        XCTAssertTrue(events.contains(.rumbleStrip(.left)))
    }

    func testSteeringIntoCurveKeepsTruckInLane() {
        let s = DrivingSession(road: Road(segments: [.straight(400), .left(radius: 400, length: 1_500)], loops: false))
        startEngine(s)
        // Simple proportional "driver" using only information a blind player gets from audio:
        // lateral offset (lane audio) and heading (how fast that offset changes).
        var crashed = false
        for _ in 0..<(60 * 80) {
            let y = s.truck.lateralOffset, h = s.truck.headingError
            let steer = -(1.2 * y + 6 * h)
            let throttle = s.truck.speed < 15 ? 0.6 : 0.0
            let ev = s.step(dt: 1.0 / 60, input: DrivingInput(throttle: throttle, steer: steer))
            if ev.contains(where: { if case .crashed = $0 { return true }; return false }) { crashed = true }
        }
        XCTAssertFalse(crashed)
        XCTAssertLessThan(abs(s.truck.lateralOffset), DrivingSession.rumbleOffset)
    }

    func testSignalsToggle() {
        let s = DrivingSession()
        XCTAssertEqual(s.perform(.signal(.left)), [.signalChanged(.on(.left))])
        XCTAssertEqual(s.perform(.signal(.left)), [.signalChanged(.off)])
        XCTAssertEqual(s.perform(.signal(.right)), [.signalChanged(.on(.right))])
        XCTAssertEqual(s.perform(.cancelSignal), [.signalChanged(.off)])
    }

    func testFuelIsConsumed() {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]))
        startEngine(s)
        _ = drive(s, seconds: 60, input: DrivingInput(throttle: 1))
        XCTAssertLessThan(s.truck.fuelLiters, s.spec.fuelCapacityLiters)
        XCTAssertGreaterThan(s.truck.fuelLiters, s.spec.fuelCapacityLiters - 5)
    }
}

final class RoadTests: XCTestCase {
    func testCurvatureRampsAndSign() {
        let road = Road(segments: [.straight(100), .right(radius: 200, length: 300)], loops: false)
        XCTAssertEqual(road.curvature(at: 50), 0)
        XCTAssertEqual(road.curvature(at: 250), 1.0 / 200, accuracy: 1e-9)
        XCTAssertLessThan(road.curvature(at: 110), 1.0 / 200)
        XCTAssertGreaterThan(road.curvature(at: 110), 0)
    }

    func testNextCurve() {
        let road = Road.practiceLoop
        let c = road.nextCurve(after: 0, within: 1_000)
        XCTAssertEqual(c?.direction, .right)
        XCTAssertEqual(c?.distance ?? 0, 800, accuracy: 0.001)
        XCTAssertNil(road.nextCurve(after: 0, within: 500))
    }

    func testLoopWraps() {
        let road = Road.practiceLoop
        XCTAssertEqual(road.normalized(road.totalLength + 10), 10, accuracy: 1e-9)
        // Near the end of the loop, the next curve is found after wrapping around.
        XCTAssertNotNil(road.nextCurve(after: road.totalLength - 100, within: 2_000))
    }
}

final class PhrasesTests: XCTestCase {
    func testCurvePhrase() {
        let c = UpcomingCurve(segmentIndex: 1, direction: .left, radius: 200, severity: .sharp, distance: 312, advisorySpeed: 19)
        XCTAssertEqual(Phrases(units: .metric).curve(c), "Sharp left curve in 300 meters, slow to 68.")
    }

    func testDistances() {
        XCTAssertEqual(UnitSystem.metric.distance(1_250), "1.3 kilometers")
        XCTAssertEqual(UnitSystem.metric.distance(2_000), "2 kilometers")
        XCTAssertEqual(UnitSystem.metric.distance(84), "80 meters")
        XCTAssertEqual(UnitSystem.imperial.distance(100), "350 feet")
    }
}

final class TouchInterpreterTests: XCTestCase {
    func testTwoFingerSwipeRight() {
        let t = TouchInterpreter(mode: .tilt, areaWidth: 800)
        t.began(id: 1, at: .init(x: 100, y: 100), time: 0)
        t.began(id: 2, at: .init(x: 100, y: 200), time: 0.03)
        t.ended(id: 1, at: .init(x: 220, y: 105), time: 0.2)
        t.ended(id: 2, at: .init(x: 215, y: 195), time: 0.21)
        XCTAssertEqual(t.update(time: 0.25), [.swipe(fingers: 2, direction: .right)])
    }

    func testTwoFingerDoubleTap() {
        let t = TouchInterpreter(mode: .tilt, areaWidth: 800)
        for (start, id) in [(0.0, 1), (0.25, 3)] {
            t.began(id: id, at: .init(x: 100, y: 100), time: start)
            t.began(id: id + 1, at: .init(x: 150, y: 100), time: start + 0.02)
            t.ended(id: id, at: .init(x: 101, y: 100), time: start + 0.1)
            t.ended(id: id + 1, at: .init(x: 151, y: 100), time: start + 0.11)
            XCTAssertEqual(t.update(time: start + 0.12), [])
        }
        XCTAssertEqual(t.update(time: 1.0), [.tap(fingers: 2, count: 2)])
    }

    func testSingleHeldFingerBecomesPedal() {
        let t = TouchInterpreter(mode: .tilt, areaWidth: 800)
        t.began(id: 1, at: .init(x: 700, y: 100), time: 0)
        _ = t.update(time: 0.1)
        XCTAssertEqual(t.input(at: 0.1).throttle, 0, "not a pedal yet")
        _ = t.update(time: 0.2)
        XCTAssertGreaterThan(t.input(at: 0.2).throttle, 0)
        XCTAssertEqual(t.input(at: 2).throttle, 1)

        // A second finger on the left half brakes while the first still holds the gas.
        t.began(id: 2, at: .init(x: 100, y: 100), time: 2)
        _ = t.update(time: 2.3)
        XCTAssertGreaterThan(t.input(at: 2.3).brake, 0)

        t.ended(id: 1, at: .init(x: 700, y: 100), time: 3)
        XCTAssertEqual(t.input(at: 3).throttle, 0)
        XCTAssertEqual(t.update(time: 3.5), [], "releasing a pedal is not a gesture")
    }

    func testGestureWhileHoldingPedal() {
        let t = TouchInterpreter(mode: .tilt, areaWidth: 800)
        t.began(id: 1, at: .init(x: 700, y: 100), time: 0)
        _ = t.update(time: 0.5)
        t.began(id: 2, at: .init(x: 100, y: 100), time: 1)
        t.began(id: 3, at: .init(x: 100, y: 200), time: 1.02)
        t.ended(id: 2, at: .init(x: 100, y: 40), time: 1.2)
        t.ended(id: 3, at: .init(x: 100, y: 130), time: 1.2)
        XCTAssertEqual(t.update(time: 1.25), [.swipe(fingers: 2, direction: .up)])
        XCTAssertEqual(t.input(at: 1.25).throttle, 1, "gas still held")
    }

    func testJoystick() {
        let t = TouchInterpreter(mode: .joystick, areaWidth: 800)
        t.began(id: 1, at: .init(x: 400, y: 300), time: 0)
        _ = t.update(time: 0.3)
        t.moved(id: 1, to: .init(x: 455, y: 176), time: 0.4)
        let i = t.input(at: 0.4)
        XCTAssertEqual(i.steer, 0.5, accuracy: 0.001)
        XCTAssertEqual(i.throttle, 1, accuracy: 0.001)
        XCTAssertEqual(i.brake, 0)
    }

    func testGestureMap() {
        XCTAssertEqual(GestureMap.action(for: .tap(fingers: 3, count: 2)), .toggleEngine)
        XCTAssertEqual(GestureMap.action(for: .swipe(fingers: 2, direction: .left)), .signal(.left))
        XCTAssertNil(GestureMap.action(for: .tap(fingers: 1, count: 1)))
    }
}
