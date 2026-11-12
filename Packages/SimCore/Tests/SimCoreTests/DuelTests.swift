import XCTest
@testable import SimCore

final class DuelTests: XCTestCase {
    func makeDuel(_ names: [String]) throws -> Duel {
        let towns = WorldMap.standard.towns
        let job = try XCTUnwrap(Duel.makeJob(from: towns[0].id, to: towns[1].id, cargo: Cargo.catalog[0]))
        return Duel(job: job, players: names, seed: 42, weather: .rain)
    }

    func testFastestWithPenaltiesWins() throws {
        var duel = try makeDuel(["Sam", " ", "Alex"])
        XCTAssertEqual(duel.players.map(\.name), ["Sam", "Player 2", "Alex"])
        XCTAssertTrue(duel.turnIntro(units: .metric).contains("Sam's turn, player 1 of 3"))
        duel.record(time: 300, crashes: 2, delivered: true)   // 330
        XCTAssertTrue(duel.turnIntro(units: .metric).contains("Time to beat: 5 minutes 30 seconds"))
        duel.record(time: 320, crashes: 0, delivered: true)   // 320
        duel.record(time: 100, crashes: 0, delivered: false)  // gave up
        XCTAssertTrue(duel.isOver)
        XCTAssertEqual(duel.standings.map(\.name), ["Player 2", "Sam", "Alex"])
        XCTAssertEqual(duel.winner?.name, "Player 2")
        XCTAssertTrue(duel.spokenResults.hasPrefix("Player 2 wins!"), duel.spokenResults)
        XCTAssertTrue(duel.spokenResults.contains("Sam: 5 minutes 0 seconds, 2 crashes (plus 30 seconds), total 5 minutes 30 seconds."))
        XCTAssertTrue(duel.spokenResults.contains("Alex: didn't finish."))
    }

    func testTieAndNobodyFinished() throws {
        var tie = try makeDuel(["A", "B"])
        tie.record(time: 200, crashes: 1, delivered: true)
        tie.record(time: 215, crashes: 0, delivered: true)
        XCTAssertNil(tie.winner)
        XCTAssertTrue(tie.spokenResults.hasPrefix("It's a tie!"))
        var none = try makeDuel(["A", "B"])
        none.record(time: 10, crashes: 0, delivered: false)
        none.record(time: 10, crashes: 0, delivered: false)
        XCTAssertTrue(none.spokenResults.hasPrefix("Nobody finished."))
    }

    func testJobHasNoPayAndSameTownIsRejected() {
        let towns = WorldMap.standard.towns
        XCTAssertNil(Duel.makeJob(from: towns[0].id, to: towns[0].id, cargo: Cargo.catalog[0]))
        let job = Duel.makeJob(from: towns[0].id, to: towns[2].id, cargo: Cargo.catalog[1])
        XCTAssertEqual(job?.pay, 0)
        XCTAssertGreaterThan(job?.distance ?? 0, 0)
    }

    func testSameSeedSameRoadAndTraffic() throws {
        let duel = try makeDuel(["A", "B"])
        func drive() -> [Double] {
            let nav = Navigator(map: .standard, origin: duel.job.origin!, destination: duel.job.destination!)
            let s = DrivingSession(goal: duel.job.goal, navigator: nav, seed: duel.seed)
            s.trafficEnabled = true
            _ = s.perform(.toggleEngine)
            var input = DrivingInput()
            input.throttle = 0.5
            for _ in 0..<(60 * 90) { _ = s.step(dt: 1.0 / 60, input: input) }
            return s.traffic.map(\.position)
        }
        XCTAssertEqual(drive(), drive())
    }
}
