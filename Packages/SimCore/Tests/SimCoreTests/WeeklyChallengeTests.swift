import XCTest
@testable import SimCore

final class WeeklyChallengeTests: XCTestCase {
    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s + "T12:00:00Z")!
    }

    func testWeeksRunMondayToSunday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let mon = WeeklyChallenge.weekNumber(of: date("2026-11-09"), calendar: cal)
        XCTAssertEqual(WeeklyChallenge.weekNumber(of: date("2026-11-15"), calendar: cal), mon, "Sunday is the same week")
        XCTAssertEqual(WeeklyChallenge.weekNumber(of: date("2026-11-16"), calendar: cal), mon + 1, "next Monday is a new week")
    }

    func testSameChallengeForEveryoneAndVarietyOverTime() {
        XCTAssertEqual(WeeklyChallenge.forWeek(202646), WeeklyChallenge.forWeek(202646))
        let goals = Set((202601...202652).map { "\(WeeklyChallenge.forWeek($0).goal)" })
        XCTAssertGreaterThan(goals.count, 5)
        for w in 202601...202652 {
            let c = WeeklyChallenge.forWeek(w)
            XCTAssertGreaterThan(c.prize, 0)
            XCTAssertTrue(c.description.hasSuffix("."))
        }
    }

    private func job(_ name: String, to town: String = "bayview") -> DeliveryJob {
        DeliveryJob(cargo: Cargo.catalog.first { $0.name == name }!, distance: 10_000, pay: 2_000, timeLimit: 900,
                    origin: "millbrook", destination: town)
    }

    private func summary(crashes: Int = 0, late: Bool = false) -> TripSummary {
        var s = TripStats()
        s.drivingTime = late ? 1_000 : 600
        s.crashes = crashes
        return TripSummary(goalName: "x", stats: s, stopError: -20)
    }

    func testProgressAndPrize() throws {
        // Find a week whose challenge is "clean deliveries".
        let week = try XCTUnwrap((202601...202852).first { if case .cleanDeliveries = WeeklyChallenge.forWeek($0).goal { return true }; return false })
        let challenge = WeeklyChallenge.forWeek(week)
        XCTAssertTrue(challenge.counts(job: job("Furniture"), summary: summary(), weather: .clear))
        XCTAssertFalse(challenge.counts(job: job("Furniture"), summary: summary(crashes: 1), weather: .clear))
        var spill = summary(crashes: 1)
        spill.stats.hazmatSpilled = true
        XCTAssertFalse(challenge.counts(job: job("Gasoline"), summary: spill, weather: .clear), "a spill never counts")
    }

    func testRecordWeeklyThisWeek() {
        var c = CareerState(seed: 2)
        let now = Date()
        let challenge = c.weeklyChallenge(now: now)
        // Build a delivery that counts for whatever this week's challenge is.
        let towns = WorldMap.standard.towns.map(\.id)
        var cargo = "Furniture", town = "bayview", weather = Weather.clear
        switch challenge.goal {
        case let .deliverKind(kind, _): cargo = Cargo.catalog.first { $0.kind == kind }!.name
        case let .deliverTo(t, _): town = t
        case .badWeather: weather = .rain
        default: break
        }
        _ = towns
        var sum = summary()
        sum.stopError = 0.5 // perfect, for the perfect-finish challenge
        let start = c.money
        var news: [String] = []
        for _ in 0..<challenge.target { news = c.recordWeekly(job: job(cargo, to: town), summary: sum, weather: weather, now: now) }
        XCTAssertTrue(news.first?.hasPrefix("Weekly challenge complete!") ?? false, "\(news)")
        XCTAssertEqual(c.money, start + challenge.prize)
        XCTAssertEqual(c.weeklyChallengesWon, 1)
        XCTAssertTrue(c.weeklyDone(now: now))
        XCTAssertEqual(c.recordWeekly(job: job(cargo, to: town), summary: sum, weather: weather, now: now), [], "paid once")
        XCTAssertEqual(Leaderboard.weeklyChallenges.score(c), 1)
    }

    func testANewWeekStartsFresh() {
        var c = CareerState(seed: 3)
        c.weeklyWeek = 202001
        c.weeklyCount = 3
        c.weeklyClaimed = true
        XCTAssertEqual(c.weeklyProgress(), 0)
        XCTAssertFalse(c.weeklyDone())
    }
}
