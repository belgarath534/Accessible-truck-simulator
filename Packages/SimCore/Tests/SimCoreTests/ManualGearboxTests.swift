import XCTest
@testable import SimCore

final class ManualGearboxTests: XCTestCase {
    func session() -> DrivingSession {
        let s = DrivingSession(road: Road(segments: [.straight(20_000)], loops: false), seed: 3)
        s.manualGearbox = true
        s.truck.engine = .running
        return s
    }
    let gas = DrivingInput(throttle: 1, brake: 0, steer: 0)

    func testStaysInGearAndHitsTheLimiter() {
        let s = session()
        var events: [SimEvent] = []
        for _ in 0..<(60 * 15) { events += s.step(dt: 1.0 / 60, input: gas) }
        XCTAssertEqual(s.truck.gearIndex, 0, "no automatic shifts")
        XCTAssertTrue(events.contains(.revLimiter))
        XCTAssertFalse(events.contains { if case .gearChanged = $0 { return true }; return false })
        let topInFirst = s.truck.speed
        XCTAssertLessThanOrEqual(s.truck.rpm, s.spec.maxRPM + 1)

        // Shift up through the gears and go faster.
        for _ in 0..<5 {
            XCTAssertEqual(s.perform(.shiftUp).first, .gearChanged(gear: s.truck.gearIndex + 1, up: true))
            for _ in 0..<(60 * 6) { _ = s.step(dt: 1.0 / 60, input: gas) }
        }
        XCTAssertEqual(s.truck.gearIndex, 5)
        XCTAssertGreaterThan(s.truck.speed, topInFirst * 2)
    }

    func testDownshiftThatWouldOverRevIsRefusedAndHighGearLugs() {
        let s = session()
        s.truck.speed = 12
        s.truck.gearIndex = 8
        XCTAssertEqual(s.perform(.shiftDown), [.gearChanged(gear: 8, up: false)], "a safe downshift")
        s.truck.shiftTimer = 0
        s.truck.speed = 20
        s.truck.gearIndex = 3
        XCTAssertEqual(s.perform(.shiftDown), [.gearRefused], "third gear at 72 km/h would over-rev")
        XCTAssertEqual(s.truck.gearIndex, 3)

        let slow = session()
        slow.truck.gearIndex = 8
        slow.truck.speed = 3
        var events: [SimEvent] = []
        for _ in 0..<(60 * 3) { events += slow.step(dt: 1.0 / 60, input: gas) }
        XCTAssertTrue(events.contains(.lugging))
    }

    func testAutomaticIsUnchangedAndShiftingDoesNothingThere() {
        let s = DrivingSession(road: Road(segments: [.straight(20_000)], loops: false), seed: 3)
        s.truck.engine = .running
        XCTAssertEqual(s.perform(.shiftUp), [])
        var events: [SimEvent] = []
        for _ in 0..<(60 * 20) { events += s.step(dt: 1.0 / 60, input: gas) }
        XCTAssertGreaterThan(s.truck.gearIndex, 2)
        XCTAssertFalse(events.contains(.revLimiter))
    }
}
