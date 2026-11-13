import XCTest
@testable import FlightCore

final class CareerTests: XCTestCase {
    func summary(landedAt: String?, landing: LandingRating? = .smooth, crash: CrashReason? = nil) -> FlightSummary {
        FlightSummary(completed: crash == nil, crash: crash, landing: crash == nil ? landing : nil, touchdownFPM: -200,
                      centrelineOffset: 0, landedAt: landedAt, flightTime: 500, distance: 20_000, message: "")
    }

    func testBoardRanksAndPay() {
        var rng = SeededRandom(seed: 3)
        var c = PilotCareer()
        c.refreshBoard(using: &rng)
        XCTAssertEqual(c.board.count, 3)
        XCTAssertEqual(Set(c.board.map(\.to)).count, 3, "three different airports")
        XCTAssertTrue(c.board.allSatisfy { $0.from == "pine" && $0.kind.rank == .student && $0.pay > 100 })
        XCTAssertEqual(PilotRank.forFlights(0), .student)
        XCTAssertEqual(PilotRank.forFlights(3), .privatePilot)
        XCTAssertEqual(PilotRank.forFlights(25), .captain)
        XCTAssertTrue(c.board[0].summary.contains("pays $"))
    }

    func testAGoodFlightPaysAndMovesThePlane() {
        var rng = SeededRandom(seed: 5)
        var c = PilotCareer()
        c.flightsDone = 2
        let job = FlightJob(id: UUID(), kind: .passengers, load: "Two hikers", from: "pine", to: "harbor", distance: 27_000, pay: 600)
        let pay = c.finish(job, summary: summary(landedAt: "harbor", landing: .butter), comfort: 95, using: &rng)
        XCTAssertEqual(pay.lines.map(\.amount), [600, 120, 90])
        XCTAssertEqual(c.money, 500 + 810)
        XCTAssertEqual(c.location, "harbor")
        XCTAssertEqual(c.rank, .privatePilot)
        XCTAssertTrue(pay.news.contains("Promoted! You're now a Private Pilot."))
        XCTAssertTrue(c.board.allSatisfy { $0.from == "harbor" })
        XCTAssertTrue(pay.spoken.contains("Total: $810."))
    }

    func testRoughRideWrongAirportAndCrash() {
        var rng = SeededRandom(seed: 5)
        var c = PilotCareer()
        let job = FlightJob(id: UUID(), kind: .passengers, load: "Two hikers", from: "pine", to: "harbor", distance: 27_000, pay: 600)
        let rough = c.finish(job, summary: summary(landedAt: "harbor", landing: .firm), comfort: 40, using: &rng)
        XCTAssertEqual(rough.total, 450)
        var d = PilotCareer()
        XCTAssertEqual(d.finish(job, summary: summary(landedAt: "mesa"), comfort: 100, using: &rng).total, 0)
        XCTAssertEqual(d.location, "mesa")
        XCTAssertEqual(d.flightsDone, 0)
        var e = PilotCareer()
        XCTAssertEqual(e.finish(job, summary: summary(landedAt: nil, crash: .hardLanding), comfort: 0, using: &rng).total, 0)
        XCTAssertEqual(e.condition, 0.59, accuracy: 0.001)
        XCTAssertEqual(e.location, "pine")
    }

    func testTheMechanic() {
        var c = PilotCareer()
        XCTAssertEqual(c.repairCost, 0)
        XCTAssertFalse(c.repair(), "nothing to fix")
        c.condition = 0.5
        XCTAssertEqual(c.repairCost, 1_500)
        XCTAssertLessThan(c.powerFactor, 1)
        XCTAssertFalse(c.repair(), "can't afford it")
        c.money = 2_000
        XCTAssertTrue(c.repair())
        XCTAssertEqual(c.money, 500)
        XCTAssertEqual(c.condition, 1)
        XCTAssertEqual(c.powerFactor, 1)
        // Grounded and broke: a free patch-up, so you're never stuck.
        c.condition = 0.1
        c.money = 0
        XCTAssertFalse(c.canFlyJobs)
        XCTAssertTrue(c.emergencyRepairIfStuck())
        XCTAssertTrue(c.canFlyJobs)
    }

    func testComfortDropsInSteepTurnsAndAWornEngineIsWeaker() {
        let s = FlightSession(start: .air(x: 0, y: 0, altitude: 900, heading: 0, speed: 52, throttle: 0.7, flaps: 0),
                              goal: .freeFlight, assist: .off)
        s.passengers = true
        var events: [FlightEvent] = []
        for _ in 0..<(60 * 20) { events += s.step(dt: 1.0 / 60, input: FlightInput(pitch: 0.2, roll: 1)) }
        XCTAssertLessThan(s.comfort, 70)
        XCTAssertEqual(events.filter { $0 == .passengersUneasy }.count, 1)

        func speedAfterRoll(power: Double) -> Double {
            let g = FlightSession(start: .runway("pine"), goal: .freeFlight)
            g.powerFactor = power
            g.startEngineNow()
            _ = g.perform(.throttleFull)
            for _ in 0..<(60 * 8) { _ = g.step(dt: 1.0 / 60, input: FlightInput()) }
            return g.airspeed
        }
        XCTAssertLessThan(speedAfterRoll(power: 0.8), speedAfterRoll(power: 1) - 2)
    }

    func testTowerLinesAreRecorded() {
        let pine = World.airport("pine")!
        XCTAssertEqual(Phrases.towerTakeoff(pine), "Pine Valley tower. Runway 9, cleared for takeoff. Have a good flight.")
        XCTAssertEqual(VoiceLines.line(for: Phrases.towerLanding(pine))?.speaker, .tower)
        XCTAssertEqual(Phrases.money(1_250), "$1,250")
    }
}
