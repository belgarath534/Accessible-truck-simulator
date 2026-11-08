import XCTest
@testable import SimCore

final class TruckLineupTests: XCTestCase {
    private let dt = 1.0 / 60

    private func session(_ spec: TruckSpec, cargo: Double = 0) -> DrivingSession {
        let s = DrivingSession(spec: spec, road: Road(segments: [.straight(200_000)]), cargoMassKg: cargo, seed: 1)
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        return s
    }

    private func zeroTo(_ kmh: Double, _ spec: TruckSpec, cargo: Double = 0) -> Double {
        let s = session(spec, cargo: cargo)
        var t = 0.0
        while s.truck.speed < kmh / 3.6 && t < 300 { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)); t += dt }
        return t
    }

    func testCatalogIsOrderedDistinctAndAllDrivable() {
        let trucks = TruckSpec.catalog
        XCTAssertEqual(trucks.count, 11)
        XCTAssertEqual(Set(trucks.map(\.id)).count, trucks.count)
        XCTAssertEqual(Set(trucks.map(\.name)).count, trucks.count)
        XCTAssertEqual(trucks.map(\.price), trucks.map(\.price).sorted())
        XCTAssertEqual(trucks.first?.price, 0)
        XCTAssertEqual(trucks.last?.id, "titan")
        // Every truck sounds different.
        for (i, a) in trucks.enumerated() {
            for b in trucks[(i + 1)...] { XCTAssertNotEqual(a.sound, b.sound, "\(a.name) and \(b.name) sound the same") }
        }
        // Every truck gets up to 60 km/h with a 10 tonne load in reasonable time.
        for t in trucks { XCTAssertLessThan(zeroTo(60, t, cargo: 10_000), 80, t.name) }
    }

    func testTitanIsQuickestAndIronBullPullsHeavyLoads() {
        let titan = zeroTo(60, .titan, cargo: 20_000)
        for t in TruckSpec.catalog where t.id != "titan" && !t.isElectric {
            XCTAssertLessThan(titan, zeroTo(60, t, cargo: 20_000), t.name)
        }
        XCTAssertLessThan(zeroTo(60, .ironBull, cargo: 25_000), zeroTo(60, .roadKing, cargo: 25_000) * 0.9)
    }

    func testLongHaulerGoesFurthestOnATank() {
        func range(_ spec: TruckSpec) -> Double {
            let s = session(spec)
            while s.truck.fuelLiters > spec.fuelCapacityLiters * 0.9 {
                _ = s.step(dt: dt, input: DrivingInput(throttle: s.truck.speed < 22 ? 0.6 : 0))
            }
            return s.stats.distance / (spec.fuelCapacityLiters * 0.1) * spec.fuelCapacityLiters
        }
        let long = range(.longHauler)
        for t in TruckSpec.catalog where t.id != "long_hauler" && !t.isElectric {
            XCTAssertGreaterThan(long, range(t), t.name)
        }
    }

    func testCityHaulerSteersSharpestAndMountainGoatStopsShortest() {
        XCTAssertEqual(TruckSpec.catalog.max { $0.steeringLatAccel < $1.steeringLatAccel }?.id, "city_hauler")
        func stoppingDistance(_ spec: TruckSpec) -> Double {
            let s = session(spec, cargo: 15_000)
            while s.truck.speed < 60 / 3.6 { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
            let start = s.truck.odometer
            while s.truck.speed > 0 { _ = s.step(dt: dt, input: DrivingInput(brake: 1)) }
            return s.truck.odometer - start
        }
        XCTAssertLessThan(stoppingDistance(.mountainGoat), stoppingDistance(.roadKing))
        XCTAssertLessThan(stoppingDistance(.mountainGoat), stoppingDistance(.starter))
    }

    func testVoltIsElectric() {
        XCTAssertTrue(TruckSpec.volt.isElectric)
        XCTAssertTrue(TruckSpec.volt.sound.electric)
        let s = session(.volt)
        XCTAssertEqual(s.truck.engine, .running)
        XCTAssertLessThan(s.truck.rpm, 50, "an electric motor is silent at a standstill")
        var shifts = 0
        for _ in 0..<(60 * 40) {
            shifts += s.step(dt: dt, input: DrivingInput(throttle: 1)).filter { if case .gearChanged = $0 { return true }; return false }.count
        }
        XCTAssertEqual(shifts, 0)
        XCTAssertGreaterThan(s.truck.speed, 90 / 3.6)
        XCTAssertLessThanOrEqual(s.truck.speed, TruckSpec.volt.speedLimiter + 0.5)
        // Cheaper to run than a diesel of the same power.
        let diesel = session(.roadKing)
        for _ in 0..<(60 * 40) { _ = diesel.step(dt: dt, input: DrivingInput(throttle: 1)) }
        XCTAssertLessThan(s.stats.fuelUsedLiters, diesel.stats.fuelUsedLiters)
    }

    func testElectricWords() {
        let p = Phrases(units: .metric, electric: true)
        XCTAssertTrue(p.fuelLow(fraction: 0.2, nextStop: 1_000, urgent: false).hasPrefix("Battery low"))
        XCTAssertEqual(p.refuelStarted, "Charging.")
        XCTAssertTrue(p.refueled(liters: 120, cost: 300).hasPrefix("Charged"))
        let s = DrivingSession(spec: .volt)
        let dash = p.dashboard(s.dashboard)
        XCTAssertTrue(dash.contains("battery 100 percent"))
        XCTAssertFalse(dash.contains("gear"))
        XCTAssertTrue(Phrases(units: .metric).truck(.volt).contains("kilowatt hour battery"))
        XCTAssertTrue(Phrases(units: .metric).dashboard(DrivingSession().dashboard).contains("fuel 100 percent"))
    }

    func testCollector() {
        var c = CareerState(seed: 9)
        c.money = 1_000_000
        for t in TruckSpec.catalog.dropLast() { c.buy(t) }
        XCTAssertFalse(c.checkAchievements().contains(.collector))
        c.buy(.titan)
        XCTAssertTrue(c.checkAchievements().contains(.collector))
        XCTAssertLessThanOrEqual(Achievement.allCases.map(\.points).reduce(0, +), 1_000)
    }
}
