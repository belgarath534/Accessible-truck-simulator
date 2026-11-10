import XCTest
@testable import SimCore

final class WearTests: XCTestCase {
    private let dt = 1.0 / 60

    func testTrucksWearAndServiceRestoresThem() {
        var c = CareerState(seed: 1)
        XCTAssertEqual(c.condition(of: .starter), 100)
        c.wear(.starter, kilometers: 200, crashes: 2)
        XCTAssertEqual(c.condition(of: .starter), 84, accuracy: 0.01)
        XCTAssertEqual(c.serviceCost(.starter), 240)
        c.money = 1_000
        XCTAssertTrue(c.service(.starter))
        XCTAssertEqual(c.money, 760)
        XCTAssertEqual(c.condition(of: .starter), 100)
        XCTAssertFalse(c.service(.starter), "nothing to do")
    }

    func testWornTrucksLosePower() {
        XCTAssertEqual(TruckSpec.starter.worn(80), TruckSpec.starter)
        XCTAssertLessThan(TruckSpec.starter.worn(0).peakTorque, TruckSpec.starter.peakTorque * 0.9)
    }

    func testOldSavesAreLikeNew() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CareerState(seed: 2))) as! [String: Any]
        json.removeValue(forKey: "truckCondition")
        let old = try JSONDecoder().decode(CareerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.condition(of: .starter), 100)
    }

    func testWornTrucksBlowTiresMoreOften() {
        XCTAssertGreaterThan(DrivingSession.blowoutChancePerKm(condition: 20), DrivingSession.blowoutChancePerKm(condition: 100) * 5)
    }

    private func blowoutSession() -> DrivingSession {
        let s = DrivingSession(road: Road(segments: [.straight(400_000)], loops: false), seed: 3)
        s.blowoutsEnabled = true
        s.condition = 0
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        return s
    }

    func testABlowoutPullsTheTruckUntilYouStopAndChangeTheTire() throws {
        let s = blowoutSession()
        var side: Side?
        for _ in 0..<(60 * 7_200) where side == nil {
            for e in s.step(dt: dt, input: DrivingInput(throttle: s.truck.speed < 20 ? 0.6 : 0)) {
                if case let .blowout(sd) = e { side = sd }
            }
        }
        let blown = try XCTUnwrap(side, "a worn truck blows a tire within two hours")
        let before = s.truck.lateralOffset
        for _ in 0..<60 { _ = s.step(dt: dt, input: .idle) }
        let drift = s.truck.lateralOffset - before
        XCTAssertEqual(drift > 0, blown == .right, "pulls toward the blown tire")

        var events: [SimEvent] = []
        for _ in 0..<(60 * 30) where s.blowout != nil { events += s.step(dt: dt, input: DrivingInput(brake: 0.4)) }
        XCTAssertNil(s.blowout)
        XCTAssertTrue(events.contains(.tireChanged(cost: DrivingSession.tireChangeCost)))
        XCTAssertEqual(s.stats.repairCost, DrivingSession.tireChangeCost)
        XCTAssertTrue(Payout.expenses(s.stats).contains { $0.label == "Roadside tire change" })
    }

    func testNoBlowoutsWhenOff() {
        let s = DrivingSession(road: Road(segments: [.straight(400_000)], loops: false), seed: 3)
        s.condition = 0
        _ = s.perform(.toggleEngine)
        var n = 0
        for _ in 0..<(60 * 600) {
            n += s.step(dt: dt, input: DrivingInput(throttle: s.truck.speed < 20 ? 0.6 : 0)).filter { if case .blowout = $0 { return true }; return false }.count
        }
        XCTAssertEqual(n, 0)
    }
}
