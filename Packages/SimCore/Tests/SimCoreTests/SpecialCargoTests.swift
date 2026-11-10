import XCTest
@testable import SimCore

final class SpecialCargoTests: XCTestCase {
    private let dt = 1.0 / 60

    private func job(_ name: String) -> DeliveryJob {
        let cargo = Cargo.catalog.first { $0.name == name }!
        return DeliveryJob(cargo: cargo, distance: 10_000, pay: 2_000, timeLimit: 900, origin: "millbrook", destination: "bayview")
    }

    private func started(_ kind: CargoKind, road: Road = Road(segments: [.straight(100_000)], loops: false)) -> DrivingSession {
        let s = DrivingSession(road: road, timeLimit: 900, seed: 3)
        s.cargoKind = kind
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        return s
    }

    private func run(_ s: DrivingSession, _ input: DrivingInput, seconds: Double) -> [SimEvent] {
        var all: [SimEvent] = []
        for _ in 0..<Int(seconds * 60) { all += s.step(dt: dt, input: input) }
        return all
    }

    func testEveryKindIsOnTheMapAndOldSavesKeepTheirKind() throws {
        let exports = Set(WorldMap.standard.towns.flatMap(\.exports))
        for kind in CargoKind.allCases where kind != .standard {
            XCTAssertTrue(Cargo.catalog.contains { $0.kind == kind && exports.contains($0.name) }, "\(kind)")
        }
        // A job board saved before special cargo: Frozen food comes back refrigerated.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Cargo.catalog[1])) as! [String: Any]
        json.removeValue(forKey: "kind")
        let old = try JSONDecoder().decode(Cargo.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.name, "Frozen food")
        XCTAssertEqual(old.kind, .refrigerated)
    }

    func testHardBrakingScaresLivestockButGentleBrakingDoesnt() {
        let s = started(.livestock)
        _ = run(s, DrivingInput(throttle: 1), seconds: 25)
        _ = run(s, DrivingInput(brake: 0.4), seconds: 4)
        XCTAssertEqual(s.stats.livestockScares, 0)
        _ = run(s, DrivingInput(throttle: 1), seconds: 10)
        let events = run(s, DrivingInput(brake: 1), seconds: 3)
        XCTAssertTrue(events.contains(.livestockScared))
        XCTAssertEqual(s.stats.livestockScares, 1, "one scare per hard stop, not one per frame")
    }

    func testAnimalsMakeNoise() {
        let s = started(.livestock)
        XCTAssertTrue(run(s, .idle, seconds: 100).contains(.livestockSound))
        let plain = started(.standard)
        XCTAssertFalse(run(plain, .idle, seconds: 100).contains(.livestockSound))
    }

    func testOversizeWarnsWhenTooFast() {
        let s = started(.oversize)
        var events: [SimEvent] = []
        for _ in 0..<(60 * 60) {
            let input = s.truck.speed < 55 / 2.236_94 ? DrivingInput(throttle: 1) : .idle
            events += s.step(dt: dt, input: input)
        }
        XCTAssertTrue(events.contains(.oversizeTooFast(limit: DrivingSession.oversizeSpeedLimit)))
        XCTAssertGreaterThan(s.stats.oversizeWarnings, 0)

        let careful = started(.oversize)
        for _ in 0..<(60 * 60) {
            let input = careful.truck.speed < 40 / 2.236_94 ? DrivingInput(throttle: 1) : .idle
            _ = careful.step(dt: dt, input: input)
        }
        XCTAssertEqual(careful.stats.oversizeWarnings, 0)
    }

    func testRefrigeratedSpoilsAfterTheDeadline() {
        let s = started(.refrigerated)
        // The delivery clock starts when the truck moves; crawl along past the 15-minute deadline.
        var events: [SimEvent] = []
        for _ in 0..<(60 * 920) {
            events += s.step(dt: dt, input: s.truck.speed < 5 ? DrivingInput(throttle: 0.3) : .idle)
        }
        XCTAssertEqual(events.filter { $0 == .cargoSpoiling }.count, 1)
    }

    func testHazmatSpillsOnTheFirstCrash() {
        let s = started(.hazmat)
        _ = run(s, DrivingInput(throttle: 1), seconds: 15)
        let events = run(s, DrivingInput(throttle: 0.5, steer: 1), seconds: 15)
        XCTAssertTrue(events.contains(.hazmatSpill(cost: DrivingSession.hazmatCleanupCost)))
        XCTAssertTrue(s.stats.hazmatSpilled)
        XCTAssertEqual(events.filter { if case .hazmatSpill = $0 { return true }; return false }.count, 1)
    }

    func testPay() {
        var stats = TripStats()
        stats.drivingTime = 600
        func pay(_ name: String) -> Payout {
            Payout.delivery(job(name), summary: TripSummary(goalName: "x", stats: stats, stopError: 5))
        }
        XCTAssertEqual(pay("Cattle").total, pay("Furniture").total, "clean runs pay the same base")

        stats.livestockScares = 2
        XCTAssertTrue(pay("Cattle").lines.contains { $0.label.hasPrefix("Stressed animals") && $0.amount == -200 })
        stats.livestockScares = 20
        XCTAssertTrue(pay("Cattle").lines.contains { $0.label.hasPrefix("Stressed animals") && $0.amount == -600 }, "capped at 30%")
        stats.livestockScares = 0

        stats.oversizeWarnings = 1
        XCTAssertTrue(pay("Wind turbine blade").lines.contains { $0.label.hasPrefix("Wide load") && $0.amount == -100 })
        stats.oversizeWarnings = 0

        stats.drivingTime = 1_000
        XCTAssertTrue(pay("Ice cream").lines.contains { $0.label == "Spoiled cargo" && $0.amount == -500 })
        XCTAssertFalse(pay("Furniture").lines.contains { $0.label == "Spoiled cargo" })
        stats.drivingTime = 600

        stats.crashes = 1
        stats.hazmatSpilled = true
        let spill = pay("Gasoline")
        XCTAssertEqual(spill.total, -DrivingSession.hazmatCleanupCost)
        XCTAssertFalse(spill.lines.contains { $0.label == "Delivery pay" })
    }

    func testPhrases() {
        let p = Phrases(units: .imperial)
        XCTAssertTrue(p.job(job("Gasoline")).contains("hazmat"))
        XCTAssertTrue(p.jobIntro(job("Cattle")).contains("brake gently"))
        XCTAssertTrue(p.jobIntro(job("Wind turbine blade")).contains("45 miles per hour"))
        XCTAssertNil(p.cargoRules(.standard))
    }
}
