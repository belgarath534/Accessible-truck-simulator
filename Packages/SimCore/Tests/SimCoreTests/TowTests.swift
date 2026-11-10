import XCTest
@testable import SimCore

final class TowTests: XCTestCase {
    private let dt = 1.0 / 60

    func testTheTowTruckGetsTowCallsAndFreightTrucksDont() {
        var c = CareerState(seed: 1)
        c.money = 50_000
        XCTAssertFalse(c.jobBoard.contains { $0.tow != nil })
        XCTAssertEqual(c.buy(.towTruck), .bought)
        XCTAssertTrue(c.jobBoard.allSatisfy { $0.tow != nil }, "buying it switches to tow calls")
        for job in c.jobBoard {
            let tow = job.tow!
            XCTAssertGreaterThan(tow.pickupAt, job.distance * 0.25)
            XCTAssertLessThan(tow.pickupAt, job.distance * 0.65)
            XCTAssertTrue(Phrases(units: .imperial).job(job).hasPrefix("Tow call:"))
        }
        c.select(.starter)
        XCTAssertFalse(c.jobBoard.contains { $0.tow != nil }, "back to freight")
        XCTAssertFalse(TruckSpec.catalog.contains { $0.isTowTruck }, "not part of the freight lineup")
        XCTAssertEqual(TruckSpec.withID("tow_truck"), .towTruck)
    }

    /// Drives to `stopAt` metres along a straight road and stops there.
    private func session(pickupAt: Double) -> DrivingSession {
        let s = DrivingSession(spec: .towTruck, road: Road(segments: [.straight(10_000)], loops: false),
                               goal: .destination(name: "Bayview", distance: 3_000), seed: 1)
        s.towPickupAt = pickupAt
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        return s
    }

    private func driveTo(_ s: DrivingSession, _ x: Double) -> [SimEvent] {
        var events: [SimEvent] = []
        while s.truck.position < x - 30 { events += s.step(dt: dt, input: DrivingInput(throttle: s.truck.speed < 12 ? 0.6 : 0)) }
        while s.truck.speed > 0.05 { events += s.step(dt: dt, input: DrivingInput(brake: 0.8)) }
        return events
    }

    func testStoppingAtTheCarHooksItUp() {
        let s = session(pickupAt: 1_200)
        var events = driveTo(s, 1_200)
        XCTAssertTrue(events.contains { if case .towCarAhead = $0 { return true }; return false })
        let mass = s.cargoMassKg
        for _ in 0..<(60 * 5) { events += s.step(dt: dt, input: .idle) }
        XCTAssertTrue(events.contains(.towHookingUp))
        XCTAssertTrue(events.contains(.towHooked))
        XCTAssertTrue(s.towHooked)
        XCTAssertEqual(s.cargoMassKg, mass + Cargo.towedCar.massKg)
        XCTAssertTrue(s.stats.towCompleted)
        XCTAssertNil(s.towCarDistance)
    }

    func testDrivingPastTheCarCancelsTheCall() {
        let s = session(pickupAt: 1_200)
        let events = driveTo(s, 1_500)
        XCTAssertTrue(events.contains(.towMissedCar))
        XCTAssertTrue(s.towFailed)
        XCTAssertFalse(s.stats.towCompleted)
    }

    func testPay() {
        var c = CareerState(seed: 2)
        c.money = 50_000
        c.buy(.towTruck)
        let job = c.jobBoard[0]
        var stats = TripStats()
        stats.drivingTime = job.timeLimit / 2
        let missed = c.deliveryPayout(job, summary: TripSummary(goalName: "x", stats: stats, stopError: -20))
        XCTAssertEqual(missed.total, 0)
        XCTAssertTrue(missed.lines[0].label.hasPrefix("Tow call canceled"))
        stats.towCompleted = true
        let done = c.deliveryPayout(job, summary: TripSummary(goalName: "x", stats: stats, stopError: -20))
        XCTAssertGreaterThan(done.total, job.pay)
        stats.crashes = 1
        let crashed = c.deliveryPayout(job, summary: TripSummary(goalName: "x", stats: stats, stopError: -20))
        XCTAssertTrue(crashed.lines.contains { $0.label.hasPrefix("Cargo damage") && $0.amount == -Int((Double(job.pay) * 0.1).rounded()) },
                      "the customer's car is fragile")
    }
}
