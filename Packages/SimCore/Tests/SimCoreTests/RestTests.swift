import XCTest
@testable import SimCore

final class RestTests: XCTestCase {
    func testTiredThenDrowsyThenANapAndABonus() {
        let road = Road(segments: [.straight(200_000)], loops: false)
        let s = DrivingSession(road: road, seed: 2)
        s.restEnabled = true
        s.truck.engine = .running
        s.truck.speed = 20
        var events: [SimEvent] = []
        s.awakeTime = Rest.tiredAfter - 1
        for _ in 0..<(60 * 2) { events += s.step(dt: 1.0 / 60, input: DrivingInput(throttle: 0.5, brake: 0, steer: 0)) }
        XCTAssertEqual(events.filter { $0 == .gettingTired }.count, 1)
        s.awakeTime = Rest.drowsyAfter
        events = []
        for _ in 0..<(60 * 90) { events += s.step(dt: 1.0 / 60, input: DrivingInput(throttle: 0.5, brake: 0, steer: 0)) }
        XCTAssertTrue(events.contains(.drowsy))

        // Off: nothing.
        let off = DrivingSession(road: road, seed: 2)
        off.truck.engine = .running
        off.truck.speed = 20
        off.awakeTime = Rest.drowsyAfter
        var quiet: [SimEvent] = []
        for _ in 0..<(60 * 90) { quiet += off.step(dt: 1.0 / 60, input: DrivingInput(throttle: 0.5, brake: 0, steer: 0)) }
        XCTAssertFalse(quiet.contains(.drowsy) || quiet.contains(.gettingTired))
    }

    func testNapAtATruckStopAndTheBonus() {
        var road = Road(segments: [.straight(5_000)], loops: false)
        road.truckStops = [1_000]
        let s = DrivingSession(road: road, seed: 2)
        s.restEnabled = true
        s.truck.engine = .running
        s.truck.position = 1_000
        s.awakeTime = Rest.drowsyAfter
        var events: [SimEvent] = []
        s.truck.signal = .on(.right)
        for _ in 0..<(60 * 3) { events += s.step(dt: 1.0 / 60, input: DrivingInput(throttle: 0, brake: 1, steer: 0)) }
        XCTAssertTrue(events.contains(.pulledIntoTruckStop), "\(events)")
        XCTAssertTrue(events.contains(.napped))
        XCTAssertEqual(s.awakeTime, 0, accuracy: 0.1)
        XCTAssertEqual(s.stats.naps, 1)

        var c = CareerState()
        let job = DeliveryJob(cargo: Cargo.catalog[0], distance: 10_000, pay: 1_000, timeLimit: 3_600)
        var stats = TripStats()
        stats.naps = 1
        let pay = c.deliveryPayout(job, summary: TripSummary(goalName: "x", stats: stats, stopError: 0), weather: .clear)
        XCTAssertTrue(pay.lines.contains { $0.label == "Well-rested driver bonus" && $0.amount == Rest.bonus })
        _ = c
    }

    func testOldSavesWithoutNapsStillLoad() throws {
        let data = try JSONEncoder().encode(TripStats())
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict["naps"] = nil
        let stats = try JSONDecoder().decode(TripStats.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertNil(stats.naps)
    }
}

final class SilverLakeTests: XCTestCase {
    func testSilverLakeIsOnTheMapAndReachableFromEveryTown() {
        let map = WorldMap.standard
        XCTAssertEqual(map.towns.count, 6)
        XCTAssertEqual(map.node("silver_lake")?.name, "Silver Lake")
        for town in map.towns where town.id != "silver_lake" {
            XCTAssertNotNil(map.route(from: town.id, to: "silver_lake"), town.name)
            XCTAssertNotNil(Navigator(map: map, origin: "silver_lake", destination: town.id), town.name)
        }
        XCTAssertEqual(map.outgoing(from: "silver_lake").count, 2, "two roads in")
        // Its own cargo shows up on its job board.
        var rng = SeededRandom(seed: 9)
        let jobs = (0..<30).map { _ in JobBoard.makeJob(using: &rng, from: "silver_lake") }
        XCTAssertTrue(jobs.contains { $0.cargo.name == "Spring water" || $0.cargo.name == "Maple syrup" })
    }
}
