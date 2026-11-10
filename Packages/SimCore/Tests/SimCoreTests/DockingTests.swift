import XCTest
@testable import SimCore

final class DockingTests: XCTestCase {
    private let dt = 1.0 / 60

    /// Drives a short delivery to the drop-off and stops, with docking on.
    private func atTheDock(seed: UInt64 = 1) -> (DrivingSession, [SimEvent]) {
        let s = DrivingSession(road: Road(segments: [.straight(2_000)], loops: false), goal: .destination(name: "Dock", distance: 400), seed: seed)
        s.dockingEnabled = true
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        var events: [SimEvent] = []
        while (s.remaining ?? 0) > 30 { events += s.step(dt: dt, input: DrivingInput(throttle: s.truck.speed < 12 ? 0.6 : 0)) }
        for _ in 0..<(60 * 20) where s.docking == nil && s.summary == nil { events += s.step(dt: dt, input: DrivingInput(brake: 0.6)) }
        return (s, events)
    }

    /// Backs up, steering away from the side the trailer is off to, slowing near the end.
    private func backIn(_ s: DrivingSession, steer: Bool = true, fast: Bool = false) -> [SimEvent] {
        var events: [SimEvent] = []
        for _ in 0..<(60 * 60) where s.summary == nil {
            guard let d = s.docking else { break }
            let throttle = fast ? 1.0 : (d.distance > 4 ? 0.6 : 0.15)
            let steering = steer ? max(-1, min(1, -d.lateral * 1.5)) : 0
            events += s.step(dt: dt, input: DrivingInput(throttle: throttle, steer: steering))
        }
        return events
    }

    func testStoppingAtTheDropOffStartsDocking() {
        let (s, events) = atTheDock()
        XCTAssertTrue(events.contains(.dockingStarted(distance: DrivingSession.dockStartDistance)))
        XCTAssertNotNil(s.docking)
        XCTAssertNil(s.summary, "the delivery isn't finished until the trailer is docked")
    }

    func testCarefulBackingIsPerfect() {
        let (s, _) = atTheDock()
        let events = backIn(s)
        XCTAssertTrue(events.contains(.docked(.perfect)))
        XCTAssertEqual(s.summary?.dockRating, .perfect)
        XCTAssertTrue(events.contains { if case .arrived = $0 { return true }; return false })
        XCTAssertEqual(events.filter { if case .dockingProgress = $0 { return true }; return false }.count, 3)
    }

    func testTooFastIsABump() {
        let (s, _) = atTheDock()
        XCTAssertTrue(backIn(s, fast: true).contains(.docked(.bumped)))
    }

    func testNotSteeringIsCrooked() {
        let (s, _) = atTheDock()
        let rating = backIn(s, steer: false).compactMap { e -> DockRating? in if case let .docked(r) = e { return r }; return nil }.first
        XCTAssertEqual(rating, .crooked)
    }

    func testSkipping() {
        let (s, _) = atTheDock()
        let events = s.perform(.skipDocking)
        XCTAssertTrue(events.contains(.docked(.skipped)))
        XCTAssertEqual(s.summary?.dockRating, .skipped)
        XCTAssertTrue(s.perform(.skipDocking).isEmpty)
    }

    func testTheClockStopsWhileDocking() {
        let (s, _) = atTheDock()
        let time = s.stats.drivingTime
        _ = backIn(s)
        XCTAssertEqual(s.stats.drivingTime, time, accuracy: 0.01)
    }

    func testNoDockingWhenOff() {
        let s = DrivingSession(road: Road(segments: [.straight(2_000)], loops: false), goal: .destination(name: "Dock", distance: 400), seed: 1)
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        while (s.remaining ?? 0) > 30 { _ = s.step(dt: dt, input: DrivingInput(throttle: s.truck.speed < 12 ? 0.6 : 0)) }
        for _ in 0..<(60 * 20) where s.summary == nil { _ = s.step(dt: dt, input: DrivingInput(brake: 0.6)) }
        XCTAssertNotNil(s.summary)
        XCTAssertNil(s.summary?.dockRating)
    }

    func testPayAndReputation() {
        let job = CareerState(seed: 1).jobBoard[0]
        var stats = TripStats()
        stats.drivingTime = job.timeLimit / 2
        var sum = TripSummary(goalName: "x", stats: stats, stopError: -20)
        sum.dockRating = .perfect
        XCTAssertTrue(Payout.delivery(job, summary: sum).lines.contains { $0.label == "Perfect docking bonus" && $0.amount == Int((Double(job.pay) * 0.05).rounded()) })
        let perfectRep = CareerState.reputationChange(job: job, summary: sum)
        sum.dockRating = .bumped
        XCTAssertFalse(Payout.delivery(job, summary: sum).lines.contains { $0.label.contains("ocking bonus") })
        XCTAssertEqual(CareerState.reputationChange(job: job, summary: sum), perfectRep - 8)
    }

    func testPhrases() {
        let p = Phrases(units: .metric)
        XCTAssertEqual(p.dockingProgress(5, lateral: 0.8), "5 meters. A little left.")
        XCTAssertEqual(p.dockingProgress(2, lateral: -0.5), "2 meters. A little right.")
        XCTAssertTrue(p.docked(.bumped).contains("bumped"))
    }
}

final class DockingImperialTests: XCTestCase {
    func testFeet() {
        XCTAssertEqual(Phrases(units: .imperial).dockingProgress(5, lateral: 0), "16 feet. Straight.")
    }
}
