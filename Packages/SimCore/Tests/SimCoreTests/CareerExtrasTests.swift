import XCTest
@testable import SimCore

final class CareerExtrasTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    func day(_ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: hour))!
    }

    func testStreakGrowsDayByDayAndPaysOncePerDay() {
        var c = CareerState()
        XCTAssertEqual(c.streakLine(now: day(9), calendar: cal)?.amount, 100)
        _ = c.recordStreak(now: day(9), calendar: cal)
        XCTAssertNil(c.streakLine(now: day(9, hour: 20), calendar: cal), "only the first delivery of the day")
        XCTAssertEqual(c.recordStreak(now: day(9, hour: 20), calendar: cal), [])
        XCTAssertEqual(c.streakLine(now: day(10), calendar: cal)?.amount, 200)
        _ = c.recordStreak(now: day(10), calendar: cal)
        XCTAssertEqual(c.streakDays, 2)
        // Skipping a day starts again.
        _ = c.recordStreak(now: day(12), calendar: cal)
        XCTAssertEqual(c.streakDays, 1)
        XCTAssertEqual(c.bestStreak, 2)
        XCTAssertEqual(CareerState.streakBonus(days: 30), 700, "capped at a week")
    }

    func testRivalRaceSettlesWhenTheWeekChanges() {
        var c = CareerState()
        let monday = day(9, hour: 1), nextWeek = day(17)
        XCTAssertEqual(c.recordRace(earned: 1_000_000, now: monday), [])
        XCTAssertEqual(c.earnedThisWeek(now: monday), 1_000_000)
        XCTAssertTrue(c.raceStatus(now: monday).contains("You're ahead"))
        let news = c.recordRace(earned: 500, now: nextWeek)
        XCTAssertTrue(news.first?.contains("you beat") ?? false)
        XCTAssertEqual(c.rivalWins, 1)
        XCTAssertEqual(c.earnedThisWeek(now: nextWeek), 500)
    }

    func testRivalTargetIsStableAndGrowsWithReputation() {
        XCTAssertEqual(Rival.weeklyTarget(week: 202646, level: .rookie), Rival.weeklyTarget(week: 202646, level: .rookie))
        XCTAssertLessThan(Rival.weeklyTarget(week: 202646, level: .rookie), Rival.weeklyTarget(week: 202646, level: .legend))
    }

    func testStatsLinesAndOldSavesLoad() throws {
        let c = CareerState()
        XCTAssertTrue(c.statsLines(units: .imperial).contains { $0.hasPrefix("Deliveries: 0") })
        let data = try JSONEncoder().encode(c)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for k in ["streakDays", "bestStreak", "rivalWins", "weekEarned"] { dict[k] = nil }
        let old = try JSONDecoder().decode(CareerState.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(old.streakDays, 0)
    }
}
