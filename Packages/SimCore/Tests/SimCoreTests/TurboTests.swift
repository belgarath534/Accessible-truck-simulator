import XCTest
@testable import SimCore

final class TurboTests: XCTestCase {
    private let dt = 1.0 / 60
    private let mph = 2.236_94

    private func flatOut(_ s: DrivingSession, seconds: Double) -> [SimEvent] {
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        var events: [SimEvent] = []
        for _ in 0..<Int(seconds * 60) { events += s.step(dt: dt, input: DrivingInput(throttle: 1)) }
        return events
    }

    private func straight() -> Road { Road(segments: [.straight(200_000)], loops: false) }

    func testNormalTrucksStayGoverned() {
        let s = DrivingSession(road: straight(), seed: 1)
        _ = flatOut(s, seconds: 120)
        XCTAssertLessThan(s.truck.speed * mph, 60)
    }

    func testTurboGoesTowardTwoHundred() {
        for spec in [TruckSpec.starter, .volt, .titan] {
            let s = DrivingSession(spec: spec, road: straight(), seed: 1)
            s.turbo = true
            _ = flatOut(s, seconds: 150)
            let top = s.truck.speed * mph
            XCTAssertGreaterThan(top, 150, spec.name)
            XCTAssertLessThan(top, 230, spec.name)
        }
    }

    func testSpeedIsCalledOutEvery25Mph() {
        let s = DrivingSession(road: straight(), seed: 1)
        s.turbo = true
        let callouts = flatOut(s, seconds: 150).compactMap { e -> Int? in
            if case let .turboSpeed(v) = e { return Int((v * mph).rounded()) }
            return nil
        }
        XCTAssertEqual(Array(callouts.prefix(4)), [75, 100, 125, 150])
        XCTAssertEqual(Phrases(units: .imperial).turboSpeed(100 / mph), "100 miles per hour!")
    }

    func testTurboBurnsFuelFaster() {
        func used(_ turbo: Bool) -> Double {
            let s = DrivingSession(road: straight(), seed: 1)
            s.turbo = turbo
            _ = s.perform(.toggleEngine)
            for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
            for _ in 0..<(60 * 20) { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
            return s.stats.fuelUsedLiters
        }
        XCTAssertGreaterThan(used(true), used(false) * 2.5)
    }

    func testSpeedBonus() {
        var stats = TripStats()
        stats.topSpeed = 175 / mph
        XCTAssertNil(Payout.turboBonus(stats), "no bonus without Turbo Mode")
        stats.turbo = true
        XCTAssertEqual(Payout.turboBonus(stats)?.amount, 1_200)
        stats.crashes = 2
        XCTAssertEqual(Payout.turboBonus(stats)?.amount, 600)
        stats.crashes = 4
        XCTAssertNil(Payout.turboBonus(stats))
        stats.crashes = 0
        stats.topSpeed = 70 / mph
        XCTAssertNil(Payout.turboBonus(stats))
    }

    func testBonusShowsOnDeliveryAndFreeDrive() {
        let c = CareerState(seed: 3)
        let job = c.jobBoard[0]
        var stats = TripStats()
        stats.turbo = true
        stats.topSpeed = 125 / mph
        stats.distance = 5_000
        stats.drivingTime = job.timeLimit / 2
        let delivery = Payout.delivery(job, summary: TripSummary(goalName: "x", stats: stats, stopError: 5))
        XCTAssertTrue(delivery.lines.contains { $0.label.hasPrefix("Turbo speed bonus") && $0.amount == 600 })
        XCTAssertTrue(delivery.lines.contains { $0.label == "On-time bonus" })
        XCTAssertTrue(Payout.freeDrive(stats).lines.contains { $0.label.hasPrefix("Turbo speed bonus") })
    }

    func testSpeedDemonAndTopSpeedRecord() {
        var c = CareerState(seed: 4)
        var stats = TripStats()
        stats.turbo = true
        stats.topSpeed = 160 / mph
        let new = c.checkAchievements(after: TripResult(job: nil, summary: nil, stats: stats))
        XCTAssertTrue(new.contains(.speedDemon))
        XCTAssertEqual(Leaderboard.topSpeed.score(c), 160)
        stats.topSpeed = 100 / mph
        c.checkAchievements(after: TripResult(job: nil, summary: nil, stats: stats))
        XCTAssertEqual(Leaderboard.topSpeed.score(c), 160, "keeps the best")
    }

    func testNoPoliceInTurbo() {
        var road = straight()
        road.speedLimit = 80 / 3.6
        road.policeSpots = Array(stride(from: 2_000.0, to: 150_000, by: 3_000))
        let s = DrivingSession(road: road, seed: 5)
        s.turbo = true
        let events = flatOut(s, seconds: 120)
        XCTAssertFalse(events.contains { if case .policeChase = $0 { return true }; return false })
        XCTAssertEqual(s.stats.tickets, 0)
    }
}
