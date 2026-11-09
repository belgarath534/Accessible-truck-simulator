import XCTest
@testable import SimCore

final class WeighStationTests: XCTestCase {
    private let dt = 1.0 / 60

    /// A long straight road with one weigh station.
    private func session(cargoKg: Double, stationAt station: Double = 1_500) -> DrivingSession {
        var road = Road(segments: [.straight(5_000)], loops: false)
        road.weighStations = [station]
        return DrivingSession(road: road, cargoMassKg: cargoKg, seed: 1)
    }

    private func drive(_ s: DrivingSession, to speed: Double) {
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        while s.truck.speed < speed { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
    }

    /// Holds a speed (roughly) for some seconds, collecting events, until `stop` sees what it wants.
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

    private func isWeighStationResult(_ events: [SimEvent]) -> Bool {
        events.contains {
            switch $0 {
            case .weighedIn, .skippedWeighStation: return true
            default: return false
            }
        }
    }

    /// Hits a deer at speed: one crash on this trip.
    private func crash(_ s: DrivingSession) {
        s.deer = Deer(position: s.truck.position + 15, leavesAt: s.time + 100)
        let events = cruise(s, at: s.truck.speed, seconds: 10) { $0.contains(.crashed(.animal)) }
        XCTAssertTrue(events.contains(.crashed(.animal)))
        XCTAssertEqual(s.stats.crashes, 1)
    }

    // MARK: - Pulling in

    func testPullingInCleanIsGoodToGo() {
        let s = session(cargoKg: 24_000)
        drive(s, to: 40 / 3.6)
        _ = s.perform(.signal(.right))
        let events = cruise(s, at: 40 / 3.6, seconds: 300, until: isWeighStationResult)
        XCTAssertTrue(events.contains { if case .weighStationAhead = $0 { return true }; return false })
        XCTAssertTrue(events.contains(.weighedIn(cargoKg: 24_000, fine: 0)))
        XCTAssertEqual(s.stats.weighStationFines, 0)
        XCTAssertEqual(s.stats.tickets, 0)
        XCTAssertEqual(s.stats.ticketCost, 0)
        XCTAssertEqual(s.truck.signal, .off, "Pulling in turns the signal off, like a truck stop")
    }

    func testHeavyLoadAfterACrashIsAnUnsafeLoadFine() {
        let s = session(cargoKg: 24_000, stationAt: 2_000)
        drive(s, to: 40 / 3.6)
        crash(s)
        _ = s.perform(.signal(.right))
        let events = cruise(s, at: 40 / 3.6, seconds: 300, until: isWeighStationResult)
        XCTAssertTrue(events.contains(.weighedIn(cargoKg: 24_000, fine: DrivingSession.unsafeLoadFine)))
        XCTAssertEqual(s.stats.weighStationFines, 150)
        XCTAssertEqual(s.stats.tickets, 0)
    }

    func testLightLoadAfterACrashStillPasses() {
        let s = session(cargoKg: 6_000, stationAt: 2_000)
        drive(s, to: 40 / 3.6)
        crash(s)
        _ = s.perform(.signal(.right))
        let events = cruise(s, at: 40 / 3.6, seconds: 300, until: isWeighStationResult)
        XCTAssertTrue(events.contains(.weighedIn(cargoKg: 6_000, fine: 0)))
        XCTAssertEqual(s.stats.weighStationFines, 0)
    }

    // MARK: - Skipping it

    func testSkippingTheWeighStationIsATicket() {
        let s = session(cargoKg: 12_000)
        drive(s, to: 60 / 3.6)
        let events = cruise(s, at: 60 / 3.6, seconds: 300, until: isWeighStationResult)
        XCTAssertTrue(events.contains(.skippedWeighStation(fine: 200, tooFast: false)))
        XCTAssertFalse(events.contains { if case .weighedIn = $0 { return true }; return false })
        XCTAssertEqual(s.stats.tickets, 1)
        XCTAssertEqual(s.stats.ticketCost, 200)
        XCTAssertEqual(s.stats.weighStationFines, 0)
    }

    func testSignallingButTooFastStillCountsAsSkipping() {
        let s = session(cargoKg: 12_000)
        drive(s, to: 75 / 3.6)
        _ = s.perform(.signal(.right))
        let events = cruise(s, at: 75 / 3.6, seconds: 300, until: isWeighStationResult)
        XCTAssertTrue(events.contains(.skippedWeighStation(fine: 200, tooFast: true)))
        XCTAssertEqual(s.stats.tickets, 1)
    }

    func testEachStationIsHandledOnce() {
        let s = session(cargoKg: 12_000)
        drive(s, to: 60 / 3.6)
        let events = cruise(s, at: 60 / 3.6, seconds: 150)
        XCTAssertEqual(events.filter { if case .skippedWeighStation = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(events.filter { if case .weighStationAhead = $0 { return true }; return false }.count, 1)
    }

    // MARK: - Old saves

    func testOldSavedDrivesStillLoad() throws {
        var stats = TripStats()
        stats.distance = 4_200
        stats.tickets = 1
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stats)) as! [String: Any]
        json["weighStationFines"] = nil
        let loaded = try JSONDecoder().decode(TripStats.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(loaded.weighStationFines, 0)
        XCTAssertEqual(loaded.distance, 4_200)
        XCTAssertEqual(loaded.tickets, 1)

        // A whole saved drive from before weigh stations.
        let snapshot = session(cargoKg: 0).snapshot
        var drive = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        var savedStats = drive["stats"] as! [String: Any]
        savedStats["weighStationFines"] = nil
        drive["stats"] = savedStats
        let restored = try JSONDecoder().decode(DriveSnapshot.self, from: JSONSerialization.data(withJSONObject: drive))
        XCTAssertEqual(restored.stats.weighStationFines, 0)
    }

    func testFinesSurviveASave() throws {
        var stats = TripStats()
        stats.weighStationFines = 150
        let loaded = try JSONDecoder().decode(TripStats.self, from: JSONEncoder().encode(stats))
        XCTAssertEqual(loaded.weighStationFines, 150)
    }

    func testRestoringPastAStationDoesNotFineYou() {
        let s = session(cargoKg: 12_000)
        drive(s, to: 60 / 3.6)
        _ = cruise(s, at: 60 / 3.6, seconds: 200) { _ in s.truck.position > 1_510 && s.truck.position < 1_530 }
        // Save just past the station before it was judged, then pick the drive up again.
        var snap = s.snapshot
        snap.stats = TripStats()
        let resumed = session(cargoKg: 12_000)
        resumed.restore(snap)
        drive(resumed, to: 30 / 3.6)
        let events = cruise(resumed, at: 30 / 3.6, seconds: 20)
        XCTAssertFalse(events.contains { if case .skippedWeighStation = $0 { return true }; return false })
        XCTAssertEqual(resumed.stats.tickets, 0)
    }

    // MARK: - The map

    func testWeighStationsAreOnTheLongerCountryRoads() {
        let map = WorldMap.standard
        var stations = 0
        for e in map.edges.indices {
            let edge = map.edges[e]
            for forward in [true, false] {
                let r = map.road(DirectedEdge(index: e, forward: forward))
                if edge.style != .country || r.totalLength < weighStationMinRoadLength {
                    XCTAssertTrue(r.weighStations.isEmpty, "\(edge.name) should have no weigh station")
                    continue
                }
                XCTAssertEqual(r.weighStations.count, 1, "\(edge.name) should have a weigh station")
                for spot in r.weighStations {
                    stations += 1
                    XCTAssertTrue(r.truckStops.allSatisfy { abs($0 - spot) > 400 }, "Too close to a truck stop on \(edge.name)")
                    XCTAssertNil(r.speedZone(at: spot), "Inside a town or work zone on \(edge.name)")
                }
            }
        }
        XCTAssertGreaterThan(stations, 0)
        XCTAssertTrue(map.road(DirectedEdge(index: 0, forward: true)).weighStations.isEmpty, "Route 1 is too short")
    }

    func testReversedRoadKeepsItsWeighStation() {
        var road = Road(segments: [.straight(5_000)], loops: false)
        road.weighStations = [1_500]
        XCTAssertEqual(road.reversed().weighStations, [3_500])
    }

    // MARK: - What the player hears

    func testEverythingIsSpoken() {
        let p = Phrases(units: .metric)
        XCTAssertTrue(p.weighStationAhead(800).hasPrefix("Weigh station ahead. Trucks must pull in."))
        XCTAssertTrue(p.weighStationAhead(800).contains("signal right"))
        XCTAssertEqual(p.weighedIn(cargoKg: 24_000, fine: 0), "On the scale. Your load weighs 24 tonnes. You're good to go, driver.")
        XCTAssertTrue(p.weighedIn(cargoKg: 24_000, fine: 150).contains("Unsafe load fine: $150"))
        XCTAssertTrue(p.skippedWeighStation(fine: 200, tooFast: false).contains("$200"))
        XCTAssertTrue(p.skippedWeighStation(fine: 200, tooFast: true).hasPrefix("Too fast to pull into the weigh station"))
        XCTAssertEqual(Phrases(units: .imperial).cargoWeight(24_000), "26 tons")
        XCTAssertEqual(p.weighedIn(cargoKg: 0, fine: 0), "On the scale. No load. You're good to go, driver.")
    }

    func testUnsafeLoadFineShowsOnThePayout() {
        var stats = TripStats()
        stats.weighStationFines = 150
        let payout = Payout.freeDrive(stats)
        XCTAssertTrue(payout.lines.contains { $0.label == "Weigh station fine" && $0.amount == -150 })
    }
}
