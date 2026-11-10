import XCTest
@testable import SimCore

final class HolidayTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T12:00:00Z")! }

    func testHolidayDates() {
        XCTAssertEqual(Holiday.on(date("2026-10-31"), calendar: cal), .halloween)
        XCTAssertEqual(Holiday.on(date("2026-11-26"), calendar: cal), .thanksgiving)
        XCTAssertEqual(Holiday.on(date("2026-12-24"), calendar: cal), .christmas)
        XCTAssertEqual(Holiday.on(date("2027-01-01"), calendar: cal), .newYear)
        XCTAssertEqual(Holiday.on(date("2026-12-31"), calendar: cal), .newYear)
        XCTAssertNil(Holiday.on(date("2026-11-10"), calendar: cal))
        XCTAssertNil(Holiday.on(date("2026-07-04"), calendar: cal))
    }

    func testHolidayCargoOnTheBoardOnlyDuringTheHoliday() {
        var c = CareerState(seed: 1)
        c.boardDate = date("2026-11-26")
        c.refreshBoard()
        XCTAssertTrue(c.jobBoard.contains { ["Turkeys", "Pumpkin pies"].contains($0.cargo.name) })
        c.boardDate = date("2026-11-10")
        for _ in 0..<20 {
            c.refreshBoard()
            XCTAssertFalse(c.jobBoard.contains { Holiday.isHolidayCargo($0.cargo.name) })
        }
    }

    func testRookiesDontGetHazmatFireworks() {
        var c = CareerState(seed: 2)
        c.boardDate = date("2027-01-01")
        c.refreshBoard()
        XCTAssertFalse(c.jobBoard.contains { $0.cargo.name == "Fireworks" })
        c.reputation = 400
        c.refreshBoard()
        XCTAssertTrue(c.jobBoard.contains { $0.cargo.name == "Fireworks" })
    }

    func testHolidayBonus() {
        let cargo = Holiday.thanksgiving.cargo[0]
        let job = DeliveryJob(cargo: cargo, distance: 10_000, pay: 2_000, timeLimit: 900, origin: "millbrook", destination: "bayview")
        var stats = TripStats()
        stats.drivingTime = 600
        let pay = Payout.delivery(job, summary: TripSummary(goalName: "x", stats: stats, stopError: -20))
        XCTAssertTrue(pay.lines.contains { $0.label == "Holiday bonus" && $0.amount == 300 })
    }

    func testSavedHolidayJobsKeepTheirKind() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Holiday.thanksgiving.cargo[0])) as! [String: Any]
        json.removeValue(forKey: "kind")
        let old = try JSONDecoder().decode(Cargo.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.kind, .refrigerated)
    }

    func testSnowyChristmas() {
        var rng = SeededRandom(seed: 3)
        let christmas = (0..<200).map { _ in Holiday.weather(using: &rng, date: date("2026-12-24"), calendar: cal) }
        let early = (0..<200).map { _ in Holiday.weather(using: &rng, date: date("2026-12-05"), calendar: cal) }
        XCTAssertGreaterThan(christmas.filter { $0 == .snow }.count, early.filter { $0 == .snow }.count * 2)
    }
}
