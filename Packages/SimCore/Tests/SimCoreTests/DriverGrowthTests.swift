import XCTest
@testable import SimCore

final class DriverGrowthTests: XCTestCase {
    private func hiredCareer() -> (CareerState, UUID, Date) {
        var c = CareerState(seed: 21)
        c.driverBreakdowns = false // these tests count deliveries exactly
        c.money = 100_000
        c.buy(.workhorse)
        c.select(.starter)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let rookie = c.candidates.first { $0.skill == 1 }!
        c.hire(rookie, now: start)
        return (c, c.drivers[0].id, start)
    }

    /// Lets the drivers work for this many deliveries' worth of time (in 8-hour chunks, like coming back often).
    private func work(_ c: inout CareerState, jobs: Int, from start: inout Date) -> [DriverReport] {
        var reports: [DriverReport] = []
        let seconds = Double(jobs) * (c.drivers.first?.minutesPerJob ?? 30) * 60 + 1
        var left = seconds
        while left > 0 {
            let step = min(left, 4 * 3_600)
            start = start.addingTimeInterval(step)
            reports += c.updateDrivers(now: start)
            left -= step
        }
        return reports
    }

    func testAfterTwentyDeliveriesTheyAskForARaise() {
        var (c, id, now) = hiredCareer()
        _ = work(&c, jobs: 19, from: &now)
        XCTAssertNil(c.drivers[0].raiseRequest)
        let reports = work(&c, jobs: 2, from: &now)
        XCTAssertEqual(c.drivers[0].raiseRequest, 1_500)
        XCTAssertTrue(reports.contains { $0.askedForRaise == 1_500 })
        XCTAssertTrue(Phrases.driverReports(reports)!.contains("asks for a raise of $1,500"))

        let before = c.drivers[0].hourlyEarnings
        let money = c.money
        XCTAssertEqual(c.giveRaise(id, now: now), .promoted(stars: 2))
        XCTAssertEqual(c.money, money - 1_500)
        XCTAssertEqual(c.drivers[0].skill, 2)
        XCTAssertGreaterThan(c.drivers[0].hourlyEarnings, before)
        XCTAssertNil(c.drivers[0].raiseRequest)
    }

    func testNotNowMeansTheyAskAgainLater() {
        var (c, id, now) = hiredCareer()
        _ = work(&c, jobs: 21, from: &now)
        c.declineRaise(id, now: now)
        XCTAssertNil(c.drivers[0].raiseRequest)
        _ = work(&c, jobs: 10, from: &now)
        XCTAssertNil(c.drivers[0].raiseRequest, "not yet")
        _ = work(&c, jobs: 7, from: &now)
        XCTAssertNotNil(c.drivers[0].raiseRequest, "asks again after 15 more")
        XCTAssertEqual(c.drivers.count, 1)
    }

    func testIgnoredRequestsEndWithThemQuitting() {
        var (c, _, now) = hiredCareer()
        _ = work(&c, jobs: 21, from: &now)
        XCTAssertNotNil(c.drivers[0].raiseRequest)
        let reports = work(&c, jobs: 16, from: &now)
        XCTAssertTrue(c.drivers.isEmpty)
        XCTAssertTrue(reports.contains { $0.quit })
        XCTAssertTrue(c.freeTrucks.contains { $0.id == "workhorse" }, "their truck is free again")
    }

    func testTopDriversDontAskForMore() {
        var c = CareerState(seed: 22)
        c.money = 100_000
        c.buy(.workhorse)
        c.select(.starter)
        var now = Date(timeIntervalSince1970: 1_000_000)
        c.hire(c.candidates.first { $0.skill == 3 }!, now: now)
        _ = work(&c, jobs: 80, from: &now)
        XCTAssertNil(c.drivers[0].raiseRequest)
        XCTAssertEqual(c.drivers[0].skill, 3)
    }

    func testOldSavesLoad() throws {
        let d = Driver(name: "Old Timer", skill: 1)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as! [String: Any]
        for key in ["raiseRequest", "deliveriesUntilQuit", "nextRaiseAt"] { json.removeValue(forKey: key) }
        let back = try JSONDecoder().decode(Driver.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(back.raiseRequest)
    }
}

final class DriverTrucksTests: XCTestCase {
    func testDriversCanUseTheNewTrucks() {
        var c = CareerState(seed: 31)
        c.money = 1_000_000
        c.buy(.cityHauler)
        c.buy(.titan)
        c.buy(.volt)
        c.select(.starter)
        let now = Date(timeIntervalSince1970: 1_000_000)
        for _ in 0..<3 { c.hire(c.candidates[2], now: now) } // three 3-star drivers
        let trucks = Set(c.drivers.compactMap(\.truckID))
        XCTAssertEqual(trucks, ["city_hauler", "titan", "volt"])
        // A fourth driver waits: every truck is in use.
        c.hire(c.candidates[0], now: now)
        XCTAssertNil(c.drivers.last?.truckID)
        XCTAssertTrue(c.freeTrucks.isEmpty)
    }
}
