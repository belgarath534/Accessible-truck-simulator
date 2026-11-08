import XCTest
@testable import SimCore

final class AchievementTests: XCTestCase {
    func testIdsAndPointsFitGameCenter() {
        let ids = Achievement.allCases.map(\.gameCenterID)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertLessThanOrEqual(Achievement.allCases.map(\.points).reduce(0, +), 1_000)
        XCTAssertTrue(Achievement.allCases.allSatisfy { $0.points > 0 && $0.points <= 100 && !$0.title.isEmpty })
        XCTAssertTrue(ids.allSatisfy { $0.count <= 100 })
    }

    func testNewCareerHasNothing() {
        var c = CareerState(seed: 1)
        XCTAssertEqual(c.checkAchievements(), [])
        XCTAssertEqual(c.visitedTowns, ["millbrook"])
    }

    func testDeliveryAchievements() {
        var c = CareerState(seed: 1)
        var job = c.jobBoard[0]
        job.cargo.massKg = 22_000
        job.cargo.fragile = true
        var stats = TripStats()
        stats.drivingTime = job.timeLimit - 60
        let summary = TripSummary(goalName: job.goal.name, stats: stats, stopError: 3)
        c.record(Payout.delivery(job, summary: summary), distance: job.distance)
        c.completeJob(job)
        let earned = c.checkAchievements(after: TripResult(job: job, summary: summary, stats: stats))
        XCTAssertEqual(Set(earned), [.firstDelivery, .perfectStop, .cleanRun, .onTime, .heavyHauler, .handleWithCare])
        // Earned once only.
        XCTAssertEqual(c.checkAchievements(after: TripResult(job: job, summary: summary, stats: stats)), [])
        XCTAssertTrue(c.visitedTowns.contains(job.destination!))
    }

    func testCrashesAndLatenessDontEarnSkillAchievements() {
        var c = CareerState(seed: 2)
        let job = c.jobBoard[0]
        var stats = TripStats()
        stats.crashes = 2
        stats.drivingTime = job.timeLimit + 120
        let summary = TripSummary(goalName: job.goal.name, stats: stats, stopError: 50)
        c.completeJob(job)
        let earned = Set(c.checkAchievements(after: TripResult(job: job, summary: summary, stats: stats)))
        XCTAssertTrue(earned.isDisjoint(with: [.perfectStop, .cleanRun, .onTime, .handleWithCare]))
        XCTAssertTrue(earned.contains(.firstDelivery))
    }

    func testTicketsAndTruckStops() {
        var c = CareerState(seed: 3)
        var stats = TripStats()
        stats.tickets = 1
        stats.fuelCost = 300
        XCTAssertEqual(Set(c.checkAchievements(after: TripResult(job: nil, summary: nil, stats: stats))), [.busted, .fillUp])
        var towed = TripStats()
        towed.tows = 1
        towed.fuelCost = 250
        var d = CareerState(seed: 3)
        XCTAssertFalse(d.checkAchievements(after: TripResult(job: nil, summary: nil, stats: towed)).contains(.fillUp))
    }

    func testGarageAndCompanyAchievements() {
        var c = CareerState(seed: 4)
        c.money = 1_000_000
        c.buyUpgrade(.brakes, for: .starter)
        XCTAssertEqual(c.checkAchievements(), [.firstUpgrade])
        c.buyUpgrade(.brakes, for: .starter)
        c.buyUpgrade(.brakes, for: .starter)
        XCTAssertEqual(c.checkAchievements(), [.maxedOut])
        c.buy(.workhorse)
        c.buy(.roadKing)
        XCTAssertEqual(Set(c.checkAchievements()), [.workhorse, .roadKing])
        c.hire(c.candidates[0])
        XCTAssertEqual(c.checkAchievements(), [.firstDriver])
        // Hiring puts each driver in a free truck, so a second hire makes a fleet.
        c.hire(c.candidates[0])
        XCTAssertEqual(c.drivers.filter { $0.truckID != nil }.count, 2)
        XCTAssertEqual(c.checkAchievements(), [.fleetOwner])
    }

    func testTotalsAndTowns() {
        var c = CareerState(seed: 5)
        c.totalEarned = 60_000
        c.kilometersDriven = 1_200
        c.jobsCompleted = 100
        for town in WorldMap.standard.towns { c.move(to: town.id) }
        XCTAssertEqual(Set(c.checkAchievements()),
                       [.firstDelivery, .deliveries10, .deliveries50, .deliveries100, .earned10k, .earned50k,
                        .thousandKilometers, .allTowns])
    }

    func testOldSavesStillLoad() throws {
        var c = CareerState(seed: 6)
        c.unlock(.tutorial)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]
        XCTAssertEqual((json["achievements"] as? [String]), ["tutorial"])
        json.removeValue(forKey: "achievements")
        json.removeValue(forKey: "visitedTowns")
        let old = try JSONDecoder().decode(CareerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.achievements, [])
        XCTAssertEqual(old.visitedTowns, ["millbrook"])
    }

    func testLeaderboardScores() {
        var c = CareerState(seed: 7)
        c.totalEarned = -50
        c.jobsCompleted = 4
        XCTAssertEqual(Leaderboard.totalEarned.score(c), 0)
        XCTAssertEqual(Leaderboard.deliveries.score(c), 4)
    }
}

final class GameCenterListTests: XCTestCase {
    /// store/game_center/achievements.json (what App Store Connect gets) must match the game.
    func testStoreListMatchesTheGame() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("store/game_center/achievements.json")
        let list = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        XCTAssertEqual(list.map { $0["id"] as! String }, Achievement.allCases.map(\.rawValue))
        for (entry, a) in zip(list, Achievement.allCases) {
            XCTAssertEqual(entry["title"] as? String, a.title)
            XCTAssertEqual(entry["detail"] as? String, a.detail)
            XCTAssertEqual(entry["points"] as? Int, a.points)
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: repo.appendingPathComponent("store/game_center/images/\(a.rawValue).png").path))
        }
    }
}
