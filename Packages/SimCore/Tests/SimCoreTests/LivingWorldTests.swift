import XCTest
@testable import SimCore

final class LivingWorldTests: XCTestCase {
    private let dt = 1.0 / 60

    private func drive(_ s: DrivingSession, to speed: Double) {
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        while s.truck.speed < speed { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
    }

    /// Holds a speed (roughly) for some seconds, collecting events.
    private func cruise(_ s: DrivingSession, at speed: Double, seconds: Double, until stop: (([SimEvent]) -> Bool)? = nil) -> [SimEvent] {
        var all: [SimEvent] = []
        for _ in 0..<Int(seconds * 60) {
            let input = s.truck.speed < speed ? DrivingInput(throttle: 0.6) : DrivingInput(brake: s.truck.speed > speed + 1 ? 0.5 : 0)
            let e = s.step(dt: dt, input: input)
            all += e
            if stop?(e) == true { break }
        }
        return all
    }

    func testTimeOfDayFromTheClock() {
        XCTAssertEqual(TimeOfDay(hour: 6), .dawn)
        XCTAssertEqual(TimeOfDay(hour: 12), .day)
        XCTAssertEqual(TimeOfDay(hour: 19), .dusk)
        XCTAssertEqual(TimeOfDay(hour: 23), .night)
        XCTAssertEqual(TimeOfDay(hour: 2), .night)
        XCTAssertNil(TimeOfDay.day.announcement)
        XCTAssertNotNil(TimeOfDay.night.announcement)
    }

    func testSomeRoadsHaveConstructionTollsAndWildlife() {
        let map = WorldMap.standard
        var construction = 0, tolls = 0, wildlife = 0
        for e in map.edges.indices {
            for forward in [true, false] {
                let r = map.road(DirectedEdge(index: e, forward: forward))
                construction += r.speedZones.filter { $0.kind == .construction }.count
                tolls += r.tollBooths.count
                if r.hasWildlife { wildlife += 1 }
            }
        }
        XCTAssertGreaterThan(construction, 0)
        XCTAssertGreaterThan(tolls, 0)
        XCTAssertGreaterThan(wildlife, 0)
    }

    func testConstructionZoneIsAnnounced() {
        var road = Road(segments: [.straight(5_000)], loops: false)
        road.speedZones = [SpeedZone(start: 600, end: 1_300, limit: constructionSpeedLimit, name: "Construction zone", kind: .construction)]
        let s = DrivingSession(road: road, seed: 1)
        drive(s, to: 50 / 3.6)
        let events = cruise(s, at: 38 / 3.6, seconds: 160)
        XCTAssertTrue(events.contains(.enteredConstruction(speedLimit: constructionSpeedLimit)))
        XCTAssertTrue(events.contains { if case .leftConstruction = $0 { return true }; return false })
        XCTAssertFalse(events.contains { if case .enteredTown = $0 { return true }; return false })
        XCTAssertFalse(events.contains { if case .leftTown = $0 { return true }; return false })
    }

    func testSlowThroughTheTollPays() {
        var road = Road(segments: [.straight(5_000)], loops: false)
        road.tollBooths = [1_500]
        let s = DrivingSession(road: road, seed: 1)
        drive(s, to: 25 / 3.6)
        let events = cruise(s, at: 25 / 3.6, seconds: 300) { $0.contains { if case .tollPaid = $0 { return true }; return false } }
        XCTAssertTrue(events.contains { if case .tollBoothAhead = $0 { return true }; return false })
        XCTAssertTrue(events.contains(.tollPaid(cost: DrivingSession.tollCost)))
        XCTAssertEqual(s.stats.tollCost, DrivingSession.tollCost)
        XCTAssertEqual(s.stats.tickets, 0)
    }

    func testBlowingThroughTheTollIsAFine() {
        var road = Road(segments: [.straight(5_000)], loops: false)
        road.tollBooths = [1_500]
        let s = DrivingSession(road: road, seed: 1)
        drive(s, to: 70 / 3.6)
        let events = cruise(s, at: 70 / 3.6, seconds: 120) { $0.contains { if case .ranToll = $0 { return true }; return false } }
        XCTAssertTrue(events.contains(.ranToll(fine: DrivingSession.tollFine)))
        XCTAssertEqual(s.stats.tollCost, 0)
        XCTAssertEqual(s.stats.ticketCost, DrivingSession.tollFine)
    }

    func testTollsShowOnThePayout() {
        let c = CareerState(seed: 3)
        let job = c.jobBoard[0]
        var stats = TripStats()
        stats.drivingTime = job.timeLimit / 2
        stats.tollCost = 10
        let payout = Payout.delivery(job, summary: TripSummary(goalName: "x", stats: stats, stopError: 5))
        XCTAssertTrue(payout.lines.contains { $0.label == "Tolls" && $0.amount == -10 })
    }

    func testOldSavedTripsWithoutTollsStillLoad() throws {
        var stats = TripStats()
        stats.distance = 1234
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stats)) as! [String: Any]
        json.removeValue(forKey: "tollCost")
        let old = try JSONDecoder().decode(TripStats.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.distance, 1234)
        XCTAssertEqual(old.tollCost, 0)
    }

    private func deerRoad() -> Road {
        var road = Road(segments: [.straight(50_000)], loops: false)
        road.hasWildlife = true
        return road
    }

    private func waitForDeer(_ s: DrivingSession) -> Bool {
        let e = cruise(s, at: 60 / 3.6, seconds: 600) { $0.contains { if case .deerAhead = $0 { return true }; return false } }
        return e.contains { if case .deerAhead = $0 { return true }; return false }
    }

    func testHonkingScaresTheDeerOff() {
        let s = DrivingSession(road: deerRoad(), seed: 4)
        s.wildlifeEnabled = true
        s.timeOfDay = .night
        drive(s, to: 60 / 3.6)
        XCTAssertTrue(waitForDeer(s))
        _ = s.perform(.horn)
        let events = cruise(s, at: 60 / 3.6, seconds: 10)
        XCTAssertTrue(events.contains(.deerGone(scared: true)))
        XCTAssertFalse(events.contains(.crashed(.animal)))
        XCTAssertEqual(s.stats.crashes, 0)
    }

    func testIgnoringTheDeerAtSpeedIsACrash() {
        let s = DrivingSession(road: deerRoad(), seed: 4)
        s.wildlifeEnabled = true
        s.timeOfDay = .night
        drive(s, to: 60 / 3.6)
        XCTAssertTrue(waitForDeer(s))
        let events = cruise(s, at: 60 / 3.6, seconds: 20)
        XCTAssertTrue(events.contains(.crashed(.animal)))
    }

    func testBrakingForTheDeerIsSafe() {
        let s = DrivingSession(road: deerRoad(), seed: 4)
        s.wildlifeEnabled = true
        s.timeOfDay = .night
        drive(s, to: 60 / 3.6)
        XCTAssertTrue(waitForDeer(s))
        var events: [SimEvent] = []
        for _ in 0..<(60 * 20) { events += s.step(dt: dt, input: DrivingInput(brake: 0.6)) }
        XCTAssertFalse(events.contains(.crashed(.animal)))
        XCTAssertTrue(events.contains { if case .deerGone = $0 { return true }; return false })
    }

    func testNoDeerWhenWildlifeIsOffOrOnTheInterstate() {
        let off = DrivingSession(road: deerRoad(), seed: 4)
        off.timeOfDay = .night
        drive(off, to: 60 / 3.6)
        XCTAssertFalse(waitForDeer(off))

        let interstate = DrivingSession(road: Road(segments: [.straight(50_000)], loops: false), seed: 4)
        interstate.wildlifeEnabled = true
        interstate.timeOfDay = .night
        drive(interstate, to: 60 / 3.6)
        XCTAssertFalse(waitForDeer(interstate))
    }

    func testDeerPhrasesAndCrash() {
        let p = Phrases(units: .imperial)
        XCTAssertTrue(p.deerAhead(220).contains("Deer"))
        XCTAssertTrue(p.crash(.animal).contains("deer"))
        XCTAssertTrue(p.tollBoothAhead(800).contains("$5"))
        XCTAssertTrue(p.enteredConstruction(speedLimit: constructionSpeedLimit).contains("25"))
    }
}
