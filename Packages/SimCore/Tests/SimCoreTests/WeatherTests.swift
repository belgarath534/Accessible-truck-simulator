import XCTest
@testable import SimCore

final class WeatherTests: XCTestCase {
    private let dt = 1.0 / 60

    func testRainSlowsSuggestedCurveSpeeds() {
        func advisory(_ w: Weather) -> Double {
            let s = DrivingSession(seed: 1)
            s.weather = w
            guard case let .roadAhead(curve?, _, _, _) = s.perform(.speakRoadAhead)[0] else { XCTFail(); return 0 }
            return curve.advisorySpeed
        }
        XCTAssertLessThan(advisory(.rain), advisory(.clear))
        XCTAssertLessThan(advisory(.storm), advisory(.rain))
    }

    func testWetRoadsTakeLongerToStop() {
        func stopping(_ w: Weather) -> Double {
            let s = DrivingSession(road: Road(segments: [.straight(50_000)]), seed: 1)
            s.weather = w
            _ = s.perform(.toggleEngine)
            for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
            while s.truck.speed < 70 / 3.6 { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
            let start = s.truck.odometer
            while s.truck.speed > 0 { _ = s.step(dt: dt, input: DrivingInput(brake: 1)) }
            return s.truck.odometer - start
        }
        let dry = stopping(.clear), wet = stopping(.rain), storm = stopping(.storm)
        XCTAssertGreaterThan(wet, dry * 1.1)
        XCTAssertGreaterThan(storm, wet)
    }

    func testStormsHaveThunderAndClearDaysDont() {
        func thunder(_ w: Weather) -> Int {
            let s = DrivingSession(seed: 2)
            s.weather = w
            var n = 0
            for _ in 0..<(60 * 180) { n += s.step(dt: dt, input: .idle).filter { $0 == .thunder }.count }
            return n
        }
        XCTAssertGreaterThanOrEqual(thunder(.storm), 3)
        XCTAssertEqual(thunder(.clear), 0)
        XCTAssertEqual(thunder(.rain), 0)
    }

    func testBadWeatherPaysMore() {
        let c = CareerState(seed: 3)
        let job = c.jobBoard[0]
        var stats = TripStats()
        stats.drivingTime = job.timeLimit / 2
        let summary = TripSummary(goalName: "x", stats: stats, stopError: 5)
        let dry = Payout.delivery(job, summary: summary)
        let rain = Payout.delivery(job, summary: summary, weather: .rain)
        let storm = Payout.delivery(job, summary: summary, weather: .storm)
        XCTAssertEqual(rain.total - dry.total, Int((Double(job.pay) * 0.1).rounded()))
        XCTAssertEqual(storm.total - dry.total, Int((Double(job.pay) * 0.2).rounded()))
        XCTAssertTrue(rain.lines.contains { $0.label == "Rain bonus" })
        XCTAssertFalse(dry.lines.contains { $0.label.contains("bonus") && $0.label.contains("Rain") })
    }

    func testMostlyClear() {
        var rng = SeededRandom(seed: 4)
        let days = (0..<2_000).map { _ in Weather.random(using: &rng) }
        let clear = days.filter { $0 == .clear }.count
        XCTAssertGreaterThan(clear, 1_150)
        XCTAssertGreaterThan(days.filter { $0 == .storm }.count, 100)
    }

    /// The by-ear driver from the handling tests, in a storm: following the (slower) curve calls keeps it on the road.
    func testDrivableByEarInAStorm() {
        let s = DrivingSession(road: .practiceLoop, goal: .practice(on: .practiceLoop), assist: .medium, seed: 5)
        s.weather = .storm
        _ = s.perform(.toggleEngine)
        var heard = [Double](repeating: 0, count: 30)
        var target = 22.0, t = 0.0, announced: Double?
        while s.summary == nil && t < 3_000 {
            let y = s.truck.lateralOffset
            heard.append(abs(y) > 0.25 ? (y > 0 ? 1 : -1) : 0)
            let beep = heard.removeFirst()
            let events = s.step(dt: dt, input: DrivingInput(
                throttle: s.truck.speed < target - 1 ? 0.6 : 0,
                brake: s.truck.speed > target + 1 || (s.remaining ?? 1) <= 0 ? 0.6 : 0,
                steer: -beep * 0.8))
            for case let .curveAhead(c) in events { announced = c.advisorySpeed }
            if let a = announced { target = a }
            if s.road.curvature(at: s.truck.position) == 0, s.road.nextCurve(after: s.truck.position, within: 250) == nil {
                announced = nil
                target = 22
            }
            if let r = s.remaining { target = min(target, (3 * max(0, r)).squareRoot()) }
            t += dt
        }
        XCTAssertNotNil(s.summary)
        XCTAssertLessThanOrEqual(s.stats.crashes, 2)
    }
}

final class LaneKeepingTests: XCTestCase {
    private let dt = 1.0 / 60

    private func driftAfter(_ assist: SteeringAssist, startOffset: Double, seconds: Double) -> Double {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]), assist: assist, seed: 1)
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        while s.truck.speed < 15 { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
        // Nudge the truck off centre, then let go of the wheel.
        for _ in 0..<60 where s.truck.lateralOffset < startOffset {
            _ = s.step(dt: dt, input: DrivingInput(throttle: 0.4, steer: 1))
        }
        for _ in 0..<Int(seconds * 60) { _ = s.step(dt: dt, input: DrivingInput(throttle: s.truck.speed < 15 ? 0.4 : 0)) }
        return abs(s.truck.lateralOffset)
    }

    func testHandsOffTheTruckEasesBackToTheMiddle() {
        XCTAssertLessThan(driftAfter(.medium, startOffset: 0.7, seconds: 8), 0.2)
        XCTAssertLessThan(driftAfter(.high, startOffset: 0.7, seconds: 8), 0.1)
    }

    func testSteeringStillWinsOverLaneKeeping() {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]), assist: .high, seed: 1)
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        while s.truck.speed < 15 { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
        for _ in 0..<(60 * 2) { _ = s.step(dt: dt, input: DrivingInput(throttle: 0.4, steer: -0.6)) }
        XCTAssertLessThan(s.truck.lateralOffset, -1, "steering moves you across, e.g. to pass")
    }
}
