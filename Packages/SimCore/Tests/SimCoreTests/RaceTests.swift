import XCTest
@testable import SimCore

final class RaceTests: XCTestCase {
    func testRoomCodes() {
        var rng = SeededRandom(seed: 1)
        for _ in 0..<100 { XCTAssertTrue((1_000...9_999).contains(RaceCode.random(using: &rng))) }
        XCTAssertEqual(RaceCode.spoken(4827), "4 8 2 7")
        XCTAssertEqual(RaceCode.parse(" 48 27 "), 4827)
        XCTAssertNil(RaceCode.parse("123"))
        XCTAssertNil(RaceCode.parse("0123"))
    }

    func testMessagesRoundTrip() {
        let setup = RaceSetup(from: "a", to: "b", cargoName: Cargo.catalog[1].name, seed: 99, weather: .rain)
        for m in [RaceMessage.hello(name: "Sam", creator: true, version: RaceMessage.version), .setup(setup), .ready,
                  .state(RivalState(remaining: 500, lateral: -1, speed: 20, crashes: 1, drivingTime: 60)), .quit] {
            XCTAssertEqual(RaceMessage.decode(m.encoded()), m)
        }
        XCTAssertEqual(setup.cargo, Cargo.catalog[1])
    }

    func testWhoWins() {
        let done = RivalState(remaining: 0, crashes: 1, drivingTime: 300, finished: true)   // 315
        XCTAssertEqual(RaceOutcome.decide(myTime: 310, myCrashes: 0, iFinished: true, rival: done), .won)
        XCTAssertEqual(RaceOutcome.decide(myTime: 310, myCrashes: 1, iFinished: true, rival: done), .lost)
        XCTAssertEqual(RaceOutcome.decide(myTime: 315.2, myCrashes: 0, iFinished: true, rival: done), .tie)
        XCTAssertNil(RaceOutcome.decide(myTime: 100, myCrashes: 0, iFinished: true, rival: RivalState(remaining: 900)), "waiting")
        XCTAssertEqual(RaceOutcome.decide(myTime: 100, myCrashes: 0, iFinished: true,
                                          rival: RivalState(remaining: 900, quit: true)), .won)
        XCTAssertEqual(RaceOutcome.decide(myTime: 100, myCrashes: 0, iFinished: false, rival: done), .lost)
    }

    func testAnnouncer() {
        var a = RaceAnnouncer(rivalName: "Sam", units: .metric)
        var r = RivalState(remaining: 5_000, drivingTime: 1)
        XCTAssertEqual(a.update(myRemaining: 5_000, rival: r, time: 1), ["Sam is on the move!"])
        r.remaining = 4_600
        XCTAssertEqual(a.update(myRemaining: 4_900, rival: r, time: 20), [])
        r.remaining = 4_700
        XCTAssertEqual(a.update(myRemaining: 4_500, rival: r, time: 30), ["You passed Sam!"])
        r.remaining = 4_550
        XCTAssertEqual(a.update(myRemaining: 4_500, rival: r, time: 45), ["Sam is right behind you!"])
        XCTAssertEqual(a.update(myRemaining: 4_000, rival: r, time: 95), ["You're ahead of Sam by 550 meters."])
        r.crashes = 1
        XCTAssertEqual(a.update(myRemaining: 4_000, rival: r, time: 96), ["Sam crashed!"])
        r.remaining = 1_200
        XCTAssertEqual(a.update(myRemaining: 2_000, rival: r, time: 100),
                       ["Sam passed you!", "Sam is almost at the drop-off. Go faster!"])
        r.finished = true
        XCTAssertTrue(a.update(myRemaining: 1_000, rival: r, time: 110).first?.hasPrefix("Sam delivered") ?? false)
        XCTAssertEqual(a.update(myRemaining: 900, rival: r, time: 111), [], "said once")
    }

    func testBotWaitsThenDrivesAndFinishes() {
        var bot = RaceBot(routeLength: 3_000, level: .normal, seed: 4)
        for _ in 0..<600 { _ = bot.update(dt: 0.1, started: false) }
        XCTAssertEqual(bot.state.remaining, 3_000, "waits for the player")
        var t = 0.0
        while !bot.state.finished && t < 1_000 { _ = bot.update(dt: 0.1, started: true); t += 0.1 }
        XCTAssertTrue(bot.state.finished)
        XCTAssertEqual(bot.state.crashes, 1)
        XCTAssertGreaterThan(t, 150)
        XCTAssertLessThan(t, 330)
        var hard = RaceBot(routeLength: 3_000, level: .hard, seed: 4)
        while !hard.state.finished { _ = hard.update(dt: 0.1, started: true) }
        XCTAssertLessThan(hard.state.total, bot.state.total)
    }

    func testRivalTruckIsOnTheRoadAndCanBeHit() {
        let road = Road(segments: [.straight(5_000)], loops: false)
        let s = DrivingSession(road: road, goal: .destination(name: "Race", distance: 5_000), seed: 1)
        s.truck.position = 1_000
        s.truck.odometer = 1_000
        s.truck.speed = 20
        s.truck.engine = .running
        // The rival is 40 m ahead, crawling in our lane.
        s.rival = RivalState(remaining: 3_960, speed: 2, drivingTime: 10)
        var events: [SimEvent] = []
        for _ in 0..<(60 * 5) { events += s.step(dt: 1.0 / 60, input: DrivingInput(throttle: 0.6, brake: 0, steer: 0)) }
        XCTAssertTrue(events.contains(.bumpedRival), "\(events.prefix(10))")
        XCTAssertEqual(events.filter { $0 == .bumpedRival }.count, 1, "one bump is one crash")
        // Far away: not on the road.
        s.rival = RivalState(remaining: 100, speed: 20, drivingTime: 10)
        s.placeRival()
        XCTAssertFalse(s.traffic.contains { $0.id == DrivingSession.rivalID })
    }
}
