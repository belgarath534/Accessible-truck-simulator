import XCTest
@testable import SimCore

final class HillTests: XCTestCase {
    private let dt = 1.0 / 60

    private func session(grade: Double, cargo: Double = 25_000, spec: TruckSpec = .starter) -> DrivingSession {
        var road = Road(segments: [.straight(40_000)], loops: false)
        road.hills = [Hill(start: 0, end: 40_000, grade: grade)]
        let s = DrivingSession(spec: spec, road: road, cargoMassKg: cargo, seed: 1)
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        return s
    }

    func testMapRoadsHaveHillsAndTheMountainIsSteepest() {
        let map = WorldMap.standard
        var steepest: [RoadStyle: Double] = [:]
        for e in map.edges {
            let r = e.road
            steepest[e.style] = max(steepest[e.style] ?? 0, r.hills.map { abs($0.grade) }.max() ?? 0)
            for h in r.hills {
                XCTAssertGreaterThanOrEqual(h.start, 1_000, "no hills in towns or at junctions")
                XCTAssertLessThanOrEqual(h.end, r.totalLength - 1_000)
            }
        }
        XCTAssertGreaterThan(steepest[.mountain] ?? 0, steepest[.country] ?? 0)
        XCTAssertGreaterThan(steepest[.country] ?? 0, steepest[.interstate] ?? 0)
        XCTAssertLessThanOrEqual(steepest[.mountain] ?? 1, 0.07)
    }

    func testAClimbOneWayIsADescentTheOther() {
        var road = Road(segments: [.straight(10_000)], loops: false)
        road.hills = [Hill(start: 2_000, end: 4_000, grade: 0.06)]
        let back = road.reversed()
        XCTAssertEqual(back.grade(at: 7_000), -0.06, accuracy: 0.0001)
        XCTAssertEqual(back.grade(at: 1_000), 0)
        XCTAssertEqual(road.grade(at: 2_000), 0, accuracy: 0.0001, "grades ease in")
    }

    func testLoadedTrucksCrawlUpButNeverStall() {
        let s = session(grade: 0.07)
        for _ in 0..<(60 * 90) { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
        XCTAssertGreaterThan(s.truck.speed * 3.6, 20)
        XCTAssertLessThan(s.truck.speed * 3.6, 45)
        let flat = session(grade: 0)
        for _ in 0..<(60 * 90) { _ = flat.step(dt: dt, input: DrivingInput(throttle: 1)) }
        XCTAssertGreaterThan(flat.truck.speed, s.truck.speed + 10)
    }

    func testTheEngineBrakeHoldsGentleDescents() {
        let s = session(grade: -0.03)
        while s.truck.speed < 60 / 3.6 { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
        for _ in 0..<(60 * 60) { _ = s.step(dt: dt, input: .idle) }
        XCTAssertLessThan(s.truck.speed * 3.6, 62, "doesn't run away on a 3% grade")
        XCTAssertTrue(s.truck.engineBraking)
    }

    func testSteepDescentsRunAwayWithoutBrakes() {
        let s = session(grade: -0.07)
        while s.truck.speed < 60 / 3.6 { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
        for _ in 0..<(60 * 60) { _ = s.step(dt: dt, input: .idle) }
        XCTAssertGreaterThan(s.truck.speed * 3.6, 90)
    }

    private func ride(_ s: DrivingSession, at kmh: Double, seconds: Double) -> [SimEvent] {
        while s.truck.speed < kmh / 3.6 { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
        var events: [SimEvent] = []
        for _ in 0..<Int(seconds * 60) {
            events += s.step(dt: dt, input: DrivingInput(brake: s.truck.speed > kmh / 3.6 ? 0.6 : 0))
        }
        return events
    }

    func testRidingTheBrakesTooFastFadesThem() {
        let fast = session(grade: -0.07)
        let events = ride(fast, at: 80, seconds: 240)
        XCTAssertTrue(events.contains(.brakesHot))
        XCTAssertTrue(events.contains(.brakesFading))
        XCTAssertLessThan(fast.brakeFade, 1)

        let careful = session(grade: -0.07)
        let calm = ride(careful, at: 40, seconds: 240)
        XCTAssertFalse(calm.contains(.brakesFading))
    }

    func testBrakesCoolDown() {
        let s = session(grade: -0.07)
        _ = ride(s, at: 80, seconds: 200)
        let hot = s.truck.brakeTempC
        var road = Road(segments: [.straight(40_000)], loops: false)
        road.hills = []
        for _ in 0..<(60 * 120) { _ = s.step(dt: dt, input: DrivingInput(throttle: s.truck.speed < 15 ? 0.3 : 0)) }
        XCTAssertLessThan(s.truck.brakeTempC, hot - 100)
    }

    func testHillsAreAnnounced() {
        var road = Road(segments: [.straight(10_000)], loops: false)
        road.hills = [Hill(start: 1_500, end: 3_000, grade: -0.06), Hill(start: 4_000, end: 5_000, grade: 0.02)]
        let s = DrivingSession(road: road, seed: 1)
        _ = s.perform(.toggleEngine)
        var events: [SimEvent] = []
        for _ in 0..<(60 * 200) { events += s.step(dt: dt, input: DrivingInput(throttle: s.truck.speed < 15 ? 0.6 : 0)) }
        XCTAssertTrue(events.contains(.hillAhead(grade: -0.06, length: 1_500)))
        XCTAssertFalse(events.contains { if case let .hillAhead(g, _) = $0 { return g == 0.02 }; return false }, "gentle hills aren't announced")
        XCTAssertTrue(Phrases(units: .imperial).hillAhead(grade: -0.06, length: 1_500).hasPrefix("Steep grade ahead: 6 percent downhill"))
    }

    func testRunawayRampStopsAFadingTruck() {
        var road = Road(segments: [.straight(20_000)], loops: false)
        road.hills = [Hill(start: 500, end: 15_000, grade: -0.07, runawayRamp: 9_000)]
        let s = DrivingSession(road: road, cargoMassKg: 25_000, seed: 1)
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        var events: [SimEvent] = []
        var signalled = false
        for _ in 0..<(60 * 600) where s.truck.position < 9_100 {
            let e = s.step(dt: dt, input: DrivingInput(throttle: s.truck.speed < 22 ? 1 : 0, brake: s.truck.speed > 23 ? 0.7 : 0))
            events += e
            if e.contains(where: { if case .tookRunawayRamp = $0 { return true }; return false }) { break }
            if !signalled, e.contains(where: { if case .runawayRampAhead = $0 { return true }; return false }) {
                signalled = true
                _ = s.perform(.signal(.right))
            }
        }
        XCTAssertTrue(signalled, "the ramp is announced when the brakes are hot")
        XCTAssertTrue(events.contains(.tookRunawayRamp(cost: DrivingSession.runawayRampTow)))
        XCTAssertEqual(s.truck.speed, 0, accuracy: 0.5)
        XCTAssertLessThanOrEqual(s.truck.brakeTempC, 150)
    }
}
