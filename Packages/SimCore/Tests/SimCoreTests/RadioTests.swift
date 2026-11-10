import XCTest
@testable import SimCore

final class StoryMissionTests: XCTestCase {
    private func summary(_ job: DeliveryJob, late: Bool = false) -> TripSummary {
        var s = TripStats()
        s.drivingTime = late ? job.timeLimit + 60 : job.timeLimit * 0.8
        return TripSummary(goalName: "x", stats: s, stopError: -20)
    }

    func testMissionsAreValid() {
        let map = WorldMap.standard
        for m in StoryMission.all {
            XCTAssertNotNil(map.node(m.from), m.title)
            XCTAssertNotNil(map.node(m.to), m.title)
            XCTAssertTrue(Cargo.catalog.contains { $0.name == m.cargoName }, m.title)
            XCTAssertLessThanOrEqual(m.cargo.kind.requiredLevel, m.level, "\(m.title) needs a level that allows its cargo")
            XCTAssertNotNil(map.route(from: m.from, to: m.to), m.title)
        }
        XCTAssertEqual(StoryMission.all.map(\.id), Array(1...StoryMission.all.count))
    }

    func testTheFirstMissionWaitsInItsTown() throws {
        var c = CareerState(seed: 1)
        XCTAssertFalse(c.jobBoard.contains { $0.storyID != nil }, "not in Millbrook")
        c.move(to: "ridgeport")
        let job = try XCTUnwrap(c.jobBoard.first)
        XCTAssertEqual(job.storyID, 1)
        XCTAssertEqual(job.destination, "bayview")
        XCTAssertEqual(job.cargo.name, "Medical supplies")
    }

    func testFinishingAMissionPaysAndMovesTheStoryOn() throws {
        var c = CareerState(seed: 2)
        c.move(to: "ridgeport")
        let job = try XCTUnwrap(c.jobBoard.first { $0.storyID == 1 })
        let sum = summary(job)
        let payout = c.deliveryPayout(job, summary: sum)
        XCTAssertTrue(payout.lines.contains { $0.label == "Story bonus: The Medicine Run" && $0.amount == 2_000 })
        let news = c.completeDelivery(job, summary: sum)
        XCTAssertEqual(c.storyProgress, 1)
        XCTAssertTrue(news.contains(StoryMission.all[0].success))
        XCTAssertTrue(news.contains { $0.contains("The Ice Cream Emergency") })
        XCTAssertNil(c.nextStoryMission, "mission 2 needs Reliable")
        XCTAssertEqual(c.lockedStoryMission?.id, 2)
    }

    func testALateMissionCanBeRetried() throws {
        var c = CareerState(seed: 3)
        c.move(to: "ridgeport")
        let job = try XCTUnwrap(c.jobBoard.first { $0.storyID == 1 })
        let payout = c.deliveryPayout(job, summary: summary(job, late: true))
        XCTAssertFalse(payout.lines.contains { $0.label.hasPrefix("Story bonus") })
        let news = c.completeDelivery(job, summary: summary(job, late: true))
        XCTAssertEqual(c.storyProgress, 0)
        XCTAssertTrue(news.contains { $0.contains("failed") })
        c.move(to: "ridgeport")
        XCTAssertEqual(c.jobBoard.first?.storyID, 1)
    }

    func testOldSavesStartTheStory() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CareerState(seed: 4))) as! [String: Any]
        json.removeValue(forKey: "storyProgress")
        let old = try JSONDecoder().decode(CareerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.storyProgress, 0)
        XCTAssertEqual(old.nextStoryMission?.id, 1)
    }
}

final class BreakdownTests: XCTestCase {
    private func hiredCareer() -> (CareerState, Date) {
        var c = CareerState(seed: 5)
        c.money = 50_000
        let start = Date(timeIntervalSince1970: 1_000_000)
        var d = Driver(name: "Nadia", skill: 3, truckID: TruckSpec.starter.id, lastUpdate: start)
        d.nextRaiseAt = 100_000
        c.drivers = [d]
        return (c, start)
    }

    /// Runs the driver for many hours until they break down.
    private func untilBreakdown(_ c: inout CareerState, from start: Date) -> (Date, [DriverReport]) {
        var now = start
        for _ in 0..<500 {
            now = now.addingTimeInterval(1_200)
            let reports = c.updateDrivers(now: now)
            if reports.contains(where: { $0.brokeDownIn != nil }) { return (now, reports) }
        }
        XCTFail("no breakdown in 500 deliveries")
        return (now, [])
    }

    func testBreakdownsHappenAndStopWork() {
        var (c, start) = hiredCareer()
        let (when, reports) = untilBreakdown(&c, from: start)
        XCTAssertNotNil(c.drivers[0].brokeDownIn)
        XCTAssertTrue(Phrases.driverReports(reports)?.contains("broke down near") ?? false)
        let done = c.drivers[0].jobsDone
        _ = c.updateDrivers(now: when.addingTimeInterval(5 * 3600))
        XCTAssertEqual(c.drivers[0].jobsDone, done, "no work while broken down")
    }

    func testTowGetsThemBackOnTheRoad() {
        var (c, start) = hiredCareer()
        let (when, _) = untilBreakdown(&c, from: start)
        let money = c.money
        XCTAssertTrue(c.sendTow(c.drivers[0], now: when))
        XCTAssertEqual(c.money, money - Driver.towCost)
        XCTAssertNil(c.drivers[0].brokeDownIn)
        c.driverBreakdowns = false // a second breakdown right away is possible; not what this test is about
        let done = c.drivers[0].jobsDone
        _ = c.updateDrivers(now: when.addingTimeInterval(3_600))
        XCTAssertGreaterThan(c.drivers[0].jobsDone, done)
    }

    func testWaitingItOutTakesTwoHours() {
        var (c, start) = hiredCareer()
        let (when, _) = untilBreakdown(&c, from: start)
        c.letWait(c.drivers[0], now: when)
        _ = c.updateDrivers(now: when.addingTimeInterval(3_600))
        XCTAssertNotNil(c.drivers[0].brokeDownIn, "still waiting after an hour")
        _ = c.updateDrivers(now: when.addingTimeInterval(2 * 3_600 + 10))
        XCTAssertNil(c.drivers[0].brokeDownIn, "repaired after two hours")
    }
}

final class CBRadioTests: XCTestCase {
    func testOtherTruckersTalkWhenItsOn() {
        func chatter(_ on: Bool) -> Int {
            let s = DrivingSession(road: Road(segments: [.straight(100_000)], loops: false), seed: 9)
            s.cbRadioEnabled = on
            _ = s.perform(.toggleEngine)
            var n = 0
            for _ in 0..<(60 * 900) {
                let e = s.step(dt: 1.0 / 60, input: DrivingInput(throttle: s.truck.speed < 15 ? 0.5 : 0))
                n += e.filter { $0 == .cbChatter }.count
            }
            return n
        }
        XCTAssertGreaterThanOrEqual(chatter(true), 2)
        XCTAssertEqual(chatter(false), 0)
    }
}

final class RadioLineTests: XCTestCase {
    func testEveryLineHasAUniqueFileAndACaption() {
        let all = RadioLines.all
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(all.count, 7 + 10 + 4 + 4 + 8)
        XCTAssertTrue(RadioLines.cb[0].caption.hasPrefix("Big Mike on the CB: "))
        XCTAssertFalse(RadioLines.dj[0].overCB)
        XCTAssertEqual(RadioLines.storyBriefing(StoryMission.all[0]).fileName, "voice_story_1_brief")
    }
}
