import XCTest
@testable import SimCore

final class SnowTests: XCTestCase {
    private let dt = 1.0 / 60

    func testSnowOnlyInWinter() {
        var rng = SeededRandom(seed: 1)
        let summer = (0..<500).map { _ in Weather.random(using: &rng, month: 7) }
        XCTAssertFalse(summer.contains(.snow))
        let winter = (0..<500).map { _ in Weather.random(using: &rng, month: 12) }
        XCTAssertTrue(winter.contains(.snow))
        XCTAssertGreaterThan(winter.filter { $0 == .clear }.count, 150, "still mostly clear")
    }

    func testSnowIsTheMostSlipperyAndPaysTheMost() {
        XCTAssertLessThan(Weather.snow.grip, Weather.storm.grip)
        XCTAssertLessThan(Weather.snow.braking, Weather.storm.braking)
        XCTAssertGreaterThan(Weather.snow.payBonus, Weather.storm.payBonus)
        let job = CareerState(seed: 1).jobBoard[0]
        var stats = TripStats()
        stats.drivingTime = job.timeLimit / 2
        let pay = Payout.delivery(job, summary: TripSummary(goalName: "x", stats: stats, stopError: -20), weather: .snow)
        XCTAssertTrue(pay.lines.contains { $0.label == "Snow bonus" && $0.amount == Int((Double(job.pay) * 0.3).rounded()) })
    }

    private func stopping(_ w: Weather, chains: Bool) -> Double {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]), seed: 1)
        s.weather = w
        s.chainsOn = chains
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        while s.truck.speed < 45 / 3.6 { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
        let start = s.truck.odometer
        while s.truck.speed > 0 { _ = s.step(dt: dt, input: DrivingInput(brake: 1)) }
        return s.truck.odometer - start
    }

    func testChainsHelpInTheSnowAndHoldYourSpeed() {
        XCTAssertGreaterThan(stopping(.snow, chains: false), stopping(.snow, chains: true) * 1.2)
        XCTAssertEqual(stopping(.clear, chains: true), stopping(.clear, chains: false), accuracy: 0.5, "chains only matter in snow")

        let s = DrivingSession(road: Road(segments: [.straight(50_000)]), seed: 1)
        s.weather = .snow
        s.chainsOn = true
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 3) { _ = s.step(dt: dt, input: .idle) }
        for _ in 0..<(60 * 90) { _ = s.step(dt: dt, input: DrivingInput(throttle: 1)) }
        XCTAssertLessThan(s.truck.speed * 3.6, 53)
    }

    func testBuyingChains() {
        var c = CareerState(seed: 2)
        c.money = 100
        XCTAssertEqual(c.buyChains(), .notEnoughMoney(short: 500))
        c.money = 1_000
        XCTAssertEqual(c.buyChains(), .bought)
        XCTAssertTrue(c.hasChains)
        XCTAssertEqual(c.money, 400)
        XCTAssertEqual(c.buyChains(), .alreadyOwned)
    }

    func testSnowRadioLine() {
        XCTAssertEqual(RadioLines.djWeather(.snow).id, "dj_weather_snow")
        XCTAssertNotNil(Weather.snow.announcement)
    }
}
