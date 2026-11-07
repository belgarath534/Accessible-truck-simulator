import XCTest
@testable import SimCore

final class DrivingSessionTests: XCTestCase {
    private func drive(_ session: DrivingSession, seconds: Double, input: DrivingInput) -> [SimEvent] {
        var events: [SimEvent] = []
        let dt = 1.0 / 60
        for _ in 0..<Int(seconds / dt) { events += session.step(dt: dt, input: input) }
        return events
    }

    private func startEngine(_ s: DrivingSession) {
        XCTAssertEqual(s.perform(.toggleEngine), [.engineStarting])
        let events = drive(s, seconds: 2, input: .idle)
        XCTAssertTrue(events.contains(.engineStarted))
        XCTAssertEqual(s.truck.engine, .running)
    }

    func testEngineOffMeansNoMovement() {
        let s = DrivingSession(road: Road(segments: [.straight(5_000)]))
        _ = drive(s, seconds: 5, input: DrivingInput(throttle: 1))
        XCTAssertEqual(s.truck.speed, 0)
    }

    func testAcceleratesShiftsAndRespectsLimiter() {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]))
        startEngine(s)
        let events = drive(s, seconds: 10, input: DrivingInput(throttle: 1))
        XCTAssertGreaterThan(s.truck.speed, 5, "should be moving after 10 s")
        XCTAssertTrue(events.contains { if case .gearChanged(_, true) = $0 { return true }; return false })

        _ = drive(s, seconds: 120, input: DrivingInput(throttle: 1))
        XCTAssertLessThanOrEqual(s.truck.speed, s.spec.speedLimiter + 0.5)
        XCTAssertGreaterThan(s.truck.speed, s.spec.speedLimiter - 2, "should reach the governor on a long straight")
        XCTAssertLessThanOrEqual(s.truck.rpm, s.spec.maxRPM)
    }

    func testZeroToEightyTakesTruckLikeTime() {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]))
        startEngine(s)
        var t = 0.0
        while s.truck.speed < 80 / 3.6 && t < 120 {
            _ = s.step(dt: 1.0 / 60, input: DrivingInput(throttle: 1))
            t += 1.0 / 60
        }
        XCTAssertGreaterThan(t, 15, "a truck should not be a sports car")
        XCTAssertLessThan(t, 70, "but it should not be painfully slow either")
    }

    func testBrakingStops() {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]))
        startEngine(s)
        _ = drive(s, seconds: 30, input: DrivingInput(throttle: 1))
        _ = drive(s, seconds: 15, input: DrivingInput(brake: 1))
        XCTAssertEqual(s.truck.speed, 0)
    }

    func testStraightRoadStaysInLaneWithoutSteering() {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]))
        startEngine(s)
        _ = drive(s, seconds: 30, input: DrivingInput(throttle: 1))
        XCTAssertLessThan(abs(s.truck.lateralOffset), 0.01)
    }

    func testCurveWithoutSteeringRunsOffTheOutside() {
        // Right-hand curve: doing nothing should drift to the LEFT (outside) and crash.
        let s = DrivingSession(road: Road(segments: [.straight(600), .right(radius: 300, length: 2_000)], loops: false))
        startEngine(s)
        let events = drive(s, seconds: 90, input: DrivingInput(throttle: 0.7))
        XCTAssertTrue(events.contains(.crashed(.leftRoad(.left))), "events: \(events)")
        XCTAssertTrue(events.contains { if case .curveAhead(let c) = $0 { return c.direction == .right }; return false })
        XCTAssertTrue(events.contains(.rumbleStrip(.left)))
    }

    func testSteeringIntoCurveKeepsTruckInLane() {
        let s = DrivingSession(road: Road(segments: [.straight(400), .left(radius: 400, length: 1_500)], loops: false))
        startEngine(s)
        // Simple proportional "driver" using only information a blind player gets from audio:
        // lateral offset (lane audio) and heading (how fast that offset changes).
        var crashed = false
        for _ in 0..<(60 * 80) {
            let y = s.truck.lateralOffset, h = s.truck.headingError
            let steer = -(1.2 * y + 6 * h)
            let throttle = s.truck.speed < 15 ? 0.6 : 0.0
            let ev = s.step(dt: 1.0 / 60, input: DrivingInput(throttle: throttle, steer: steer))
            if ev.contains(where: { if case .crashed = $0 { return true }; return false }) { crashed = true }
        }
        XCTAssertFalse(crashed)
        XCTAssertLessThan(abs(s.truck.lateralOffset), DrivingSession.rumbleOffset)
    }

    func testSignalsToggle() {
        let s = DrivingSession()
        XCTAssertEqual(s.perform(.signal(.left)), [.signalChanged(.on(.left))])
        XCTAssertEqual(s.perform(.signal(.left)), [.signalChanged(.off)])
        XCTAssertEqual(s.perform(.signal(.right)), [.signalChanged(.on(.right))])
        XCTAssertEqual(s.perform(.cancelSignal), [.signalChanged(.off)])
    }

    func testFuelIsConsumed() {
        let s = DrivingSession(road: Road(segments: [.straight(50_000)]))
        startEngine(s)
        _ = drive(s, seconds: 60, input: DrivingInput(throttle: 1))
        XCTAssertLessThan(s.truck.fuelLiters, s.spec.fuelCapacityLiters)
        XCTAssertGreaterThan(s.truck.fuelLiters, s.spec.fuelCapacityLiters - 30)
    }
}

final class RoadTests: XCTestCase {
    func testCurvatureRampsAndSign() {
        let road = Road(segments: [.straight(100), .right(radius: 200, length: 300)], loops: false)
        XCTAssertEqual(road.curvature(at: 50), 0)
        XCTAssertEqual(road.curvature(at: 250), 1.0 / 200, accuracy: 1e-9)
        XCTAssertLessThan(road.curvature(at: 110), 1.0 / 200)
        XCTAssertGreaterThan(road.curvature(at: 110), 0)
    }

    func testNextCurve() {
        let road = Road.practiceLoop
        let c = road.nextCurve(after: 0, within: 1_000)
        XCTAssertEqual(c?.direction, .right)
        XCTAssertEqual(c?.distance ?? 0, 800, accuracy: 0.001)
        XCTAssertNil(road.nextCurve(after: 0, within: 500))
    }

    func testLoopWraps() {
        let road = Road.practiceLoop
        XCTAssertEqual(road.normalized(road.totalLength + 10), 10, accuracy: 1e-9)
        // Near the end of the loop, the next curve is found after wrapping around.
        XCTAssertNotNil(road.nextCurve(after: road.totalLength - 100, within: 2_000))
    }
}

final class PhrasesTests: XCTestCase {
    func testCurvePhrase() {
        let c = UpcomingCurve(segmentIndex: 1, direction: .left, radius: 200, severity: .sharp, distance: 312, advisorySpeed: 19)
        XCTAssertEqual(Phrases(units: .metric).curve(c), "Sharp left curve in 300 meters, slow to 68.")
    }

    func testDistances() {
        XCTAssertEqual(UnitSystem.metric.distance(1_250), "1.3 kilometers")
        XCTAssertEqual(UnitSystem.metric.distance(2_000), "2 kilometers")
        XCTAssertEqual(UnitSystem.metric.distance(84), "80 meters")
        XCTAssertEqual(UnitSystem.imperial.distance(100), "350 feet")
    }
}

final class TouchInterpreterTests: XCTestCase {
    func testTwoFingerSwipeRight() {
        let t = TouchInterpreter(mode: .tilt, areaWidth: 800)
        t.began(id: 1, at: .init(x: 100, y: 100), time: 0)
        t.began(id: 2, at: .init(x: 100, y: 200), time: 0.03)
        t.ended(id: 1, at: .init(x: 220, y: 105), time: 0.2)
        t.ended(id: 2, at: .init(x: 215, y: 195), time: 0.21)
        XCTAssertEqual(t.update(time: 0.25), [.swipe(fingers: 2, direction: .right)])
    }

    func testTwoFingerDoubleTap() {
        let t = TouchInterpreter(mode: .tilt, areaWidth: 800)
        for (start, id) in [(0.0, 1), (0.25, 3)] {
            t.began(id: id, at: .init(x: 100, y: 100), time: start)
            t.began(id: id + 1, at: .init(x: 150, y: 100), time: start + 0.02)
            t.ended(id: id, at: .init(x: 101, y: 100), time: start + 0.1)
            t.ended(id: id + 1, at: .init(x: 151, y: 100), time: start + 0.11)
            XCTAssertEqual(t.update(time: start + 0.12), [])
        }
        XCTAssertEqual(t.update(time: 1.0), [.tap(fingers: 2, count: 2)])
    }

    func testSingleHeldFingerBecomesPedal() {
        let t = TouchInterpreter(mode: .tilt, areaWidth: 800)
        t.began(id: 1, at: .init(x: 700, y: 100), time: 0)
        _ = t.update(time: 0.1)
        XCTAssertEqual(t.input(at: 0.1).throttle, 0, "not a pedal yet")
        _ = t.update(time: 0.2)
        XCTAssertGreaterThan(t.input(at: 0.2).throttle, 0)
        XCTAssertEqual(t.input(at: 2).throttle, 1)

        // A second finger on the left half brakes while the first still holds the gas.
        t.began(id: 2, at: .init(x: 100, y: 100), time: 2)
        _ = t.update(time: 2.3)
        XCTAssertGreaterThan(t.input(at: 2.3).brake, 0)

        t.ended(id: 1, at: .init(x: 700, y: 100), time: 3)
        XCTAssertEqual(t.input(at: 3).throttle, 0)
        XCTAssertEqual(t.update(time: 3.5), [], "releasing a pedal is not a gesture")
    }

    func testGestureWhileHoldingPedal() {
        let t = TouchInterpreter(mode: .tilt, areaWidth: 800)
        t.began(id: 1, at: .init(x: 700, y: 100), time: 0)
        _ = t.update(time: 0.5)
        t.began(id: 2, at: .init(x: 100, y: 100), time: 1)
        t.began(id: 3, at: .init(x: 100, y: 200), time: 1.02)
        t.ended(id: 2, at: .init(x: 100, y: 40), time: 1.2)
        t.ended(id: 3, at: .init(x: 100, y: 130), time: 1.2)
        XCTAssertEqual(t.update(time: 1.25), [.swipe(fingers: 2, direction: .up)])
        XCTAssertEqual(t.input(at: 1.25).throttle, 1, "gas still held")
    }

    func testJoystick() {
        let t = TouchInterpreter(mode: .joystick, areaWidth: 800)
        t.began(id: 1, at: .init(x: 400, y: 300), time: 0)
        _ = t.update(time: 0.3)
        t.moved(id: 1, to: .init(x: 455, y: 176), time: 0.4)
        let i = t.input(at: 0.4)
        XCTAssertEqual(i.steer, 0.5, accuracy: 0.001)
        XCTAssertEqual(i.throttle, 1, accuracy: 0.001)
        XCTAssertEqual(i.brake, 0)
    }

    func testGestureMap() {
        XCTAssertEqual(GestureMap.action(for: .tap(fingers: 3, count: 2)), .toggleEngine)
        XCTAssertEqual(GestureMap.action(for: .swipe(fingers: 2, direction: .left)), .signal(.left))
        XCTAssertNil(GestureMap.action(for: .tap(fingers: 1, count: 1)))
    }
}

final class TripTests: XCTestCase {
    /// A simple "driver" that keeps the lane, holds a speed, and brakes to stop at the drop-off.
    private func driveTrip(_ s: DrivingSession, cruise: Double = 22, stopAt targetRemaining: Double = 0,
                           maxSeconds: Double = 2_000) -> [SimEvent] {
        _ = s.perform(.toggleEngine)
        var events: [SimEvent] = []
        var t = 0.0
        while t < maxSeconds && s.summary == nil {
            let truck = s.truck
            let steer = -(1.2 * truck.lateralOffset + 6 * truck.headingError)
            var target = cruise
            if let r = s.remaining {
                // Speed we can still stop from at a gentle 2 m/s².
                let d = max(0, r - targetRemaining)
                target = min(target, (2 * 2 * d).squareRoot())
            }
            let throttle = truck.speed < target - 1 ? 0.7 : 0
            let brake = truck.speed > target + 0.5 || (s.remaining.map { $0 <= targetRemaining } ?? false) ? 0.6 : 0
            events += s.step(dt: 1.0 / 60, input: DrivingInput(throttle: throttle, brake: brake, steer: steer))
            t += 1.0 / 60
        }
        return events
    }

    func testPracticeTripEndsAtDropOff() {
        let road = Road(segments: [.straight(3_000)], loops: true)
        let s = DrivingSession(road: road, goal: .practice(on: road))
        let events = driveTrip(s)
        guard let summary = s.summary else { return XCTFail("trip never finished") }
        XCTAssertEqual(summary.goalName, "Practice Drive")
        XCTAssertLessThan(abs(summary.stopError), DrivingSession.arrivalTolerance)
        XCTAssertGreaterThan(summary.stats.drivingTime, 60)
        XCTAssertEqual(summary.stats.distance, 3_000, accuracy: 60)
        XCTAssertTrue(events.contains(.tripProgress(remaining: 2_000)))
        XCTAssertTrue(events.contains(.tripProgress(remaining: 1_000)))
        XCTAssertFalse(events.contains(.tripProgress(remaining: 5_000)), "milestone longer than the trip")
        XCTAssertTrue(events.contains { if case .destinationAhead = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .arrived = $0 { return true }; return false })

        // Once finished, the simulation is frozen.
        let position = s.truck.position
        XCTAssertEqual(s.step(dt: 1, input: DrivingInput(throttle: 1)), [])
        XCTAssertEqual(s.truck.position, position)
    }

    func testStoppingShortDoesNotFinish() {
        let road = Road(segments: [.straight(2_000)], loops: true)
        let s = DrivingSession(road: road, goal: .destination(name: "Test", distance: 1_500))
        let events = driveTrip(s, stopAt: 300, maxSeconds: 200)
        XCTAssertNil(s.summary)
        XCTAssertTrue(events.contains { if case .stoppedShort = $0 { return true }; return false })
    }

    func testFreeDriveNeverFinishes() {
        let s = DrivingSession(road: .practiceLoop, goal: .freeDrive)
        _ = driveTrip(s, maxSeconds: 120)
        XCTAssertNil(s.summary)
        XCTAssertNil(s.remaining)
    }

    func testTripPhrases() {
        let p = Phrases(units: .metric)
        XCTAssertEqual(p.duration(605), "10 minutes 5 seconds")
        XCTAssertEqual(p.duration(61), "1 minute 1 second")
        var stats = TripStats()
        stats.distance = 4_200
        stats.drivingTime = 300
        stats.topSpeed = 25
        let status = p.tripStatus(goal: .destination(name: "Practice Drive", distance: 12_000), stats: stats, remaining: 7_800)
        XCTAssertTrue(status.hasPrefix("Practice Drive. 4.2 kilometers driven, 7.8 kilometers to the drop-off, 35 percent done."), status)
        XCTAssertTrue(p.tripStatus(goal: .freeDrive, stats: stats, remaining: nil).contains("No destination"))
        let summary = TripSummary(goalName: "Practice Drive", stats: stats, stopError: 8)
        XCTAssertTrue(p.arrived(summary).hasPrefix("Delivered! Practice Drive complete. Perfect stop"))
        XCTAssertEqual(p.roadAhead(nil, remaining: 7_800), "7.8 kilometers to the drop-off. Straight road ahead.")
    }
}

final class CareerTests: XCTestCase {
    func testJobBoardIsVariedAndSensible() {
        var rng = SeededRandom(seed: 42)
        for town in WorldMap.standard.towns {
            for _ in 0..<10 {
                let board = JobBoard.makeBoard(using: &rng, from: town.id)
                XCTAssertEqual(board.count, 3)
                XCTAssertEqual(Set(board.map(\.cargo)).count, 3, "no duplicate cargo")
                for job in board {
                    XCTAssertEqual(job.origin, town.id)
                    XCTAssertNotEqual(job.destination, town.id)
                    XCTAssertTrue((4_000...25_000).contains(job.distance), "\(job.distance)")
                    XCTAssertGreaterThan(job.pay, 0)
                    // A fair driver at 50 km/h always makes it in time.
                    XCTAssertGreaterThan(job.timeLimit, job.distance / (50 / 3.6))
                }
            }
        }
    }

    func testDeliveryPayout() {
        let cargo = Cargo(name: "Test", massKg: 10_000, ratePerKm: 100)
        let job = DeliveryJob(cargo: cargo, distance: 10_000, pay: 1_000, timeLimit: 900)
        var stats = TripStats()
        stats.drivingTime = 800
        stats.distance = 10_000
        let clean = Payout.delivery(job, summary: TripSummary(goalName: "x", stats: stats, stopError: 5))
        XCTAssertEqual(clean.total, 1_000 + 100 + 100 + 50, "pay + on time + no crash + perfect stop")

        stats.crashes = 2
        stats.drivingTime = 1_000 // 100 s late -> 2 minutes -> 6%
        let messy = Payout.delivery(job, summary: TripSummary(goalName: "x", stats: stats, stopError: 40))
        XCTAssertEqual(messy.total, 1_000 - 60 - 100, "5 percent per crash")

        let fragileJob = DeliveryJob(cargo: Cargo(name: "Glass", massKg: 4_000, ratePerKm: 100, fragile: true),
                                     distance: 10_000, pay: 1_000, timeLimit: 900)
        stats.crashes = 5
        let wrecked = Payout.delivery(fragileJob, summary: TripSummary(goalName: "x", stats: stats, stopError: 40))
        XCTAssertEqual(wrecked.total, 1_000 - 60 - 400, "damage is capped at 40 percent")
    }

    func testFreeDrivePaysLessThanJobs() {
        var stats = TripStats()
        stats.distance = 10_000
        XCTAssertEqual(Payout.freeDrive(stats).total, 350)
        stats.crashes = 3
        XCTAssertEqual(Payout.freeDrive(stats).total, 0, "never negative")
        XCTAssertLessThan(Payout.freeDriveRatePerKm * 2, Cargo.catalog.map(\.ratePerKm).min()!)
    }

    func testCareerSavesAndReplacesJobs() throws {
        var career = CareerState(seed: 7)
        XCTAssertEqual(career.money, CareerState.startingMoney)
        let job = career.jobBoard[1]
        career.record(Payout(lines: [.init(label: "x", amount: 1_200)]), distance: 8_000)
        career.completeJob(job)
        XCTAssertEqual(career.money, CareerState.startingMoney + 1_200)
        XCTAssertEqual(career.jobsCompleted, 1)
        XCTAssertEqual(career.currentTown, job.destination, "delivering moves you to the destination")
        XCTAssertTrue(career.jobBoard.allSatisfy { $0.origin == career.currentTown })
        XCTAssertFalse(career.jobBoard.contains(job))
        XCTAssertEqual(career.jobBoard.count, 3)

        let data = try JSONEncoder().encode(career)
        XCTAssertEqual(try JSONDecoder().decode(CareerState.self, from: data), career)
    }

    func testMoneyAndJobPhrases() {
        XCTAssertEqual(Phrases.money(12_450), "$12,450")
        XCTAssertEqual(Phrases.money(500), "$500")
        XCTAssertEqual(Phrases.money(-150), "minus $150")
        let job = DeliveryJob(cargo: Cargo(name: "Glassware", massKg: 4_000, ratePerKm: 160, fragile: true),
                              distance: 12_000, pay: 1_920, timeLimit: 1_620)
        XCTAssertEqual(Phrases(units: .metric).job(job),
                       "Glassware, 12 kilometers, pays $1,920, time limit 27 minutes, 4 tonnes, fragile.")
        let mapJob = DeliveryJob(cargo: job.cargo, distance: 12_000, pay: 1_920, timeLimit: 1_620,
                                 origin: "ridgeport", destination: "bayview")
        XCTAssertTrue(Phrases(units: .metric).job(mapJob).hasPrefix("Glassware to Bayview, 12 kilometers"))
    }

    func testHeavyCargoBrakesLonger() {
        func stoppingDistance(cargo: Double) -> Double {
            let s = DrivingSession(road: Road(segments: [.straight(90_000)]), cargoMassKg: cargo)
            _ = s.perform(.toggleEngine)
            for _ in 0..<(60 * 2) { _ = s.step(dt: 1.0 / 60, input: .idle) }
            while s.truck.speed < 20 { _ = s.step(dt: 1.0 / 60, input: DrivingInput(throttle: 1)) }
            let start = s.truck.odometer
            while s.truck.speed > 0 { _ = s.step(dt: 1.0 / 60, input: DrivingInput(brake: 1)) }
            return s.truck.odometer - start
        }
        XCTAssertGreaterThan(stoppingDistance(cargo: 24_000), stoppingDistance(cargo: 0) * 1.3)
    }

    func testDeadlineWarnings() {
        let s = DrivingSession(road: Road(segments: [.straight(90_000)]), goal: .destination(name: "x", distance: 80_000),
                               timeLimit: 400)
        _ = s.perform(.toggleEngine)
        var events: [SimEvent] = []
        for _ in 0..<(60 * 420) { events += s.step(dt: 1.0 / 60, input: DrivingInput(throttle: 0.5)) }
        XCTAssertTrue(events.contains(.timeLeft(seconds: 300)))
        XCTAssertTrue(events.contains(.timeLeft(seconds: 60)))
        XCTAssertTrue(events.contains(.lateForDelivery))
    }
}

final class HandlingTests: XCTestCase {
    /// A driver who only uses what a blind player hears: the lane beeps (which side, from 0.25 m off centre),
    /// with half a second of reaction time, steering hard away from them; and curve announcements, slowing
    /// to the suggested speed.
    private func crashesOnPracticeLoop(assist: SteeringAssist) -> Int {
        let s = DrivingSession(road: .practiceLoop, goal: .practice(on: .practiceLoop), assist: assist)
        _ = s.perform(.toggleEngine)
        let dt = 1.0 / 60
        var heard: [Double] = Array(repeating: 0, count: 30) // 0.5 s delay line of lane-beep side
        var targetSpeed = 22.0
        var t = 0.0
        while s.summary == nil && t < 3_000 {
            let y = s.truck.lateralOffset
            heard.append(abs(y) > 0.25 ? (y > 0 ? 1 : -1) : 0)
            let beep = heard.removeFirst()
            let steer = -beep * 0.8
            if let curve = s.road.nextCurve(after: s.truck.position, within: 250) {
                targetSpeed = curve.advisorySpeed
            } else if s.road.curvature(at: s.truck.position) == 0 {
                targetSpeed = 22
            }
            if let r = s.remaining { targetSpeed = min(targetSpeed, (4 * max(0, r)).squareRoot()) }
            let throttle = s.truck.speed < targetSpeed - 1 ? 0.6 : 0
            let brake = s.truck.speed > targetSpeed + 1 || (s.remaining ?? 1) <= 0 ? 0.5 : 0
            _ = s.step(dt: dt, input: DrivingInput(throttle: throttle, brake: brake, steer: steer))
            t += dt
        }
        return s.stats.crashes
    }

    func testSimpleHandlingIsDrivableByEar() {
        let simple = crashesOnPracticeLoop(assist: .medium)
        let realistic = crashesOnPracticeLoop(assist: .off)
        print("Crashes by ear on the practice loop: medium assist \(simple), realistic \(realistic)")
        XCTAssertLessThanOrEqual(simple, 1)
        XCTAssertLessThan(simple, max(realistic, 1) + 1)
    }
}

final class GarageTests: XCTestCase {
    func testCatalogIsOrderedAndDistinct() {
        let trucks = TruckSpec.catalog
        XCTAssertEqual(trucks.map(\.id), ["old_reliable", "workhorse", "road_king"])
        XCTAssertEqual(trucks.first?.price, 0)
        XCTAssertEqual(trucks.map(\.price), trucks.map(\.price).sorted())
        XCTAssertGreaterThan(TruckSpec.roadKing.horsepower, TruckSpec.starter.horsepower)
        XCTAssertLessThan(TruckSpec.workhorse.horsepower, TruckSpec.starter.horsepower)
        XCTAssertNotEqual(TruckSpec.workhorse.sound, TruckSpec.roadKing.sound)
        XCTAssertEqual(TruckSpec.withID("road_king").name, "Road King")
        XCTAssertEqual(TruckSpec.withID("nonsense").id, "old_reliable")
    }

    func testRoadKingPullsHarder() {
        func zeroToSixty(_ spec: TruckSpec) -> Double {
            let s = DrivingSession(spec: spec, road: Road(segments: [.straight(90_000)]), cargoMassKg: 20_000)
            _ = s.perform(.toggleEngine)
            for _ in 0..<(60 * 2) { _ = s.step(dt: 1.0 / 60, input: .idle) }
            var t = 0.0
            while s.truck.speed < 60 / 3.6 && t < 300 { _ = s.step(dt: 1.0 / 60, input: DrivingInput(throttle: 1)); t += 1.0 / 60 }
            return t
        }
        XCTAssertLessThan(zeroToSixty(.roadKing), zeroToSixty(.starter) * 0.85)
    }

    func testBuyingAndSelecting() {
        var career = CareerState(seed: 1)
        XCTAssertEqual(career.truck.id, "old_reliable")
        XCTAssertEqual(career.buy(.workhorse), .notEnoughMoney(short: 6_000 - CareerState.startingMoney))
        XCTAssertFalse(career.select(.workhorse))
        career.money = 7_000
        XCTAssertEqual(career.buy(.workhorse), .bought)
        XCTAssertEqual(career.money, 1_000)
        XCTAssertEqual(career.truck.id, "workhorse")
        XCTAssertEqual(career.buy(.workhorse), .alreadyOwned)
        XCTAssertTrue(career.select(.starter))
        XCTAssertEqual(career.truck.id, "old_reliable")
    }

    func testOldSaveWithoutGarageLoads() throws {
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CareerState(seed: 3))) as! [String: Any]
        old.removeValue(forKey: "ownedTrucks")
        old.removeValue(forKey: "selectedTruck")
        let loaded = try JSONDecoder().decode(CareerState.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(loaded.ownedTrucks, ["old_reliable"])
        XCTAssertEqual(loaded.selectedTruck, "old_reliable")
    }

    func testTruckPhrase() {
        let text = Phrases(units: .metric).truck(.roadKing)
        XCTAssertTrue(text.hasPrefix("Road King. "), text)
        XCTAssertTrue(text.contains("top speed 100 kilometers per hour"), text)
    }
}

final class UpgradeTests: XCTestCase {
    func testBuyingUpgrades() {
        var career = CareerState(seed: 5)
        career.money = 10_000
        XCTAssertEqual(career.buyUpgrade(.engine, for: .roadKing), .notOwned)
        XCTAssertEqual(career.buyUpgrade(.engine, for: .starter), .upgraded(level: 1))
        XCTAssertEqual(career.buyUpgrade(.engine, for: .starter), .upgraded(level: 2))
        XCTAssertEqual(career.money, 10_000 - 2_000 - 4_500)
        XCTAssertEqual(career.buyUpgrade(.engine, for: .starter), .notEnoughMoney(short: 8_000 - 3_500))
        career.money = 20_000
        XCTAssertEqual(career.buyUpgrade(.engine, for: .starter), .upgraded(level: 3))
        XCTAssertEqual(career.buyUpgrade(.engine, for: .starter), .maxed)
        XCTAssertEqual(career.upgradeLevels(for: .starter)[.engine], 3)
        XCTAssertEqual(career.upgradeLevels(for: .workhorse)[.engine], 0, "upgrades belong to one truck")
    }

    func testUpgradesChangeTheTruck() {
        var levels = UpgradeLevels()
        levels[.engine] = 3
        levels[.fuelTank] = 2
        levels[.tires] = 1
        let t = TruckSpec.starter.upgraded(levels)
        XCTAssertGreaterThan(t.horsepower, TruckSpec.starter.horsepower)
        XCTAssertEqual(t.fuelCapacityLiters, TruckSpec.starter.fuelCapacityLiters * 1.5, accuracy: 0.001)
        XCTAssertGreaterThan(t.steeringLatAccel, TruckSpec.starter.steeringLatAccel)
        XCTAssertLessThan(t.sound.pitch, TruckSpec.starter.sound.pitch, "a bigger engine sounds deeper")

        var career = CareerState(seed: 9)
        career.upgrades[TruckSpec.starter.id] = levels
        XCTAssertEqual(career.truck.horsepower, t.horsepower, "the driven truck has its upgrades")
    }

    func testSavesKeepUpgrades() throws {
        var career = CareerState(seed: 2)
        career.money = 5_000
        career.buyUpgrade(.brakes, for: .starter)
        let loaded = try JSONDecoder().decode(CareerState.self, from: JSONEncoder().encode(career))
        XCTAssertEqual(loaded.upgradeLevels(for: .starter)[.brakes], 1)
    }
}

final class FuelTests: XCTestCase {
    private let road = Road(segments: [.straight(20_000)], loops: true, truckStops: [3_000, 12_000])

    private func drive(_ s: DrivingSession, until stop: (DrivingSession) -> Bool, maxSeconds: Double = 1_000,
                       input: (DrivingSession) -> DrivingInput) -> [SimEvent] {
        var events: [SimEvent] = []
        var t = 0.0
        while !stop(s) && t < maxSeconds {
            events += s.step(dt: 1.0 / 60, input: input(s))
            t += 1.0 / 60
        }
        return events
    }

    func testFullTankLastsAboutTwoHours() {
        let s = DrivingSession(road: Road(segments: [.straight(200_000)]))
        XCTAssertEqual(s.range, s.spec.fuelCapacityLiters / DrivingSession.typicalFuelPerMetre, accuracy: 1)
        XCTAssertGreaterThan(s.range, 110_000)
        XCTAssertLessThan(s.range, 180_000)
        // Even the longest job on the map fits in a full tank with room to spare.
        XCTAssertLessThan(CareerState.fuelNeeded(forDistance: 25_000), s.spec.fuelCapacityLiters * 0.3)
    }

    func testPullInAndRefuel() {
        let s = DrivingSession(road: road, startingFuel: 100)
        _ = s.perform(.toggleEngine)
        _ = s.perform(.signal(.right))
        var events = drive(s, until: { $0.isAtTruckStop }) { s in
            // Cruise at about 40 km/h toward the truck stop.
            DrivingInput(throttle: s.truck.speed < 11 ? 0.5 : 0, steer: -s.truck.lateralOffset)
        }
        XCTAssertTrue(events.contains(.truckStopAhead(distance: events.compactMap { if case let .truckStopAhead(d) = $0 { return d }; return nil }.first ?? -1)))
        XCTAssertTrue(events.contains(.pulledIntoTruckStop))
        events = drive(s, until: { !$0.isAtTruckStop && $0.truck.fuelLiters > 300 }) { _ in DrivingInput(brake: 1) }
        XCTAssertTrue(events.contains(.refuelStarted))
        guard let refuel = events.compactMap({ e -> (Double, Int)? in if case let .refueled(l, c) = e { return (l, c) }; return nil }).first
        else { return XCTFail("no refuel: \(events)") }
        XCTAssertEqual(s.truck.fuelLiters, s.spec.fuelCapacityLiters, accuracy: 1)
        XCTAssertEqual(refuel.1, Int((refuel.0 * DrivingSession.truckStopFuelPrice).rounded()))
        XCTAssertEqual(s.stats.fuelCost, refuel.1)
    }

    func testTooFastMissesTheExit() {
        let s = DrivingSession(road: road, startingFuel: 100)
        _ = s.perform(.toggleEngine)
        _ = s.perform(.signal(.right))
        let events = drive(s, until: { $0.truck.position > 3_200 }) { s in
            DrivingInput(throttle: 1, steer: -s.truck.lateralOffset)
        }
        XCTAssertTrue(events.contains(.missedTruckStop(tooFast: true)))
        XCTAssertFalse(s.isAtTruckStop)
    }

    func testOutOfFuelGetsTowed() {
        let s = DrivingSession(road: road, startingFuel: 0.5)
        _ = s.perform(.toggleEngine)
        let events = drive(s, until: { $0.stats.tows > 0 }) { s in
            DrivingInput(throttle: s.truck.engine == .running ? 1 : 0, steer: -s.truck.lateralOffset)
        }
        XCTAssertTrue(events.contains(.outOfFuel))
        XCTAssertEqual(s.stats.tows, 1)
        XCTAssertEqual(s.truck.position, 3_000, accuracy: 1, "towed to the next truck stop")
        XCTAssertEqual(s.truck.fuelLiters, s.spec.fuelCapacityLiters * 0.25, accuracy: 0.1)
        let payout = Payout.freeDrive(s.stats)
        XCTAssertTrue(payout.lines.contains { $0.label == "Tow truck" && $0.amount == -DrivingSession.towFee })
    }

    func testFuelWarnings() {
        let s = DrivingSession(road: road, startingFuel: 0.26 * TruckSpec.starter.fuelCapacityLiters)
        _ = s.perform(.toggleEngine)
        let events = drive(s, until: { $0.truck.fuelLiters < 0.09 * $0.spec.fuelCapacityLiters }, maxSeconds: 3_000) { s in
            DrivingInput(throttle: 1, steer: -s.truck.lateralOffset)
        }
        XCTAssertTrue(events.contains { if case .fuelLow(_, _, false) = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .fuelLow(_, _, true) = $0 { return true }; return false })
    }

    func testCareerFuelAndYard() throws {
        var career = CareerState(seed: 4)
        XCTAssertEqual(career.fuelLiters(for: .starter), TruckSpec.starter.fuelCapacityLiters)
        career.setFuel(100, for: .starter)
        XCTAssertEqual(career.yardFillCost(for: .starter), 900)
        career.money = 1_000
        XCTAssertTrue(career.fillAtYard(.starter))
        XCTAssertEqual(career.money, 100)
        career.setFuel(0, for: .starter)
        XCTAssertFalse(career.fillAtYard(.starter), "only partly filled: not enough money")
        XCTAssertEqual(career.fuelLiters(for: .starter), 100.0 / 3, accuracy: 0.5)
        let loaded = try JSONDecoder().decode(CareerState.self, from: JSONEncoder().encode(career))
        XCTAssertEqual(loaded.fuelLiters(for: .starter), career.fuelLiters(for: .starter), accuracy: 0.001)
    }

    func testPracticeLoopHasTruckStops() {
        XCTAssertEqual(Road.practiceLoop.truckStops.count, 3)
        for stop in Road.practiceLoop.truckStops {
            XCTAssertEqual(Road.practiceLoop.curvature(at: stop), 0, "truck stops are on straights")
        }
    }
}

final class MapTests: XCTestCase {
    let map = WorldMap.standard

    func testEveryTownCanReachEveryOther() {
        for a in map.towns {
            for b in map.towns where a.id != b.id {
                let r = map.route(from: a.id, to: b.id)
                XCTAssertNotNil(r, "\(a.id) -> \(b.id)")
                if let r {
                    XCTAssertEqual(map.from(r.first!), a.id)
                    XCTAssertEqual(map.to(r.last!), b.id)
                    for (x, y) in zip(r, r.dropFirst()) { XCTAssertEqual(map.to(x), map.from(y), "route is connected") }
                }
            }
        }
    }

    func testGeneratedRoadsHaveExactLengthAndStraightEnds() {
        for e in map.edges {
            let road = e.road
            XCTAssertEqual(road.totalLength, road.totalLength.rounded(), accuracy: 1)
            XCTAssertEqual(road.curvature(at: 100), 0, "\(e.name) starts straight")
            XCTAssertEqual(road.curvature(at: road.totalLength - 100), 0, "\(e.name) ends straight")
            for stop in road.truckStops { XCTAssertEqual(road.curvature(at: stop), 0) }
        }
        XCTAssertGreaterThan(map.edges.filter { !$0.road.truckStops.isEmpty }.count, 2)
    }

    func testReversedRoadMirrorsCurves() {
        let road = map.edges[1].road
        let back = road.reversed()
        XCTAssertEqual(back.totalLength, road.totalLength, accuracy: 0.001)
        for s in stride(from: 0.0, to: road.totalLength, by: 97) {
            XCTAssertEqual(back.curvature(at: road.totalLength - s), -road.curvature(at: s), accuracy: 1e-9)
        }
    }

    func testJunctionTurns() {
        // Coming from Millbrook along Route 1 into Millbrook Junction: Highway 9 to Cedar Falls is a left
        // (north), Interstate 40 is straight on (east).
        let route1 = map.outgoing(from: "millbrook").first!
        let choices = map.choices(after: route1)
        XCTAssertEqual(choices.first { $0.toward == "Cedar Falls" }?.turn, .left)
        XCTAssertEqual(choices.first { $0.roadName == "Interstate 40" }?.turn, .straight)
        XCTAssertFalse(choices.contains { $0.turn == .uTurn }, "no U-turns at junctions")
    }

    func testTownSpeedZones() {
        let e = map.outgoing(from: "millbrook").first!
        let road = map.road(e)
        XCTAssertEqual(road.speedLimit(at: 100), townSpeedLimit, accuracy: 0.01)
        XCTAssertEqual(road.speedLimit(at: 2_000), RoadStyle.country.speedLimit, accuracy: 0.01)
    }

    /// Drives a whole job on the map, following the GPS with the turn signal, like a player would.
    func testDriveAJobFollowingTheGPS() {
        guard let nav = Navigator(map: map, origin: "millbrook", destination: "ridgeport") else { return XCTFail() }
        let planned = map.length(of: map.route(from: "millbrook", to: "ridgeport")!)
        let s = DrivingSession(goal: .destination(name: "Test", distance: planned), navigator: nav)
        XCTAssertEqual(s.remaining ?? 0, planned, accuracy: 1)
        _ = s.perform(.toggleEngine)
        var events: [SimEvent] = []
        var t = 0.0
        while s.summary == nil && t < 3_000 {
            // Signal as instructed at 300 m.
            if case let .navInstruction(n)? = events.last, n.distance <= 300 {
                switch n.turn {
                case .left: _ = s.perform(.signal(.left))
                case .right: _ = s.perform(.signal(.right))
                default: _ = s.perform(.cancelSignal)
                }
            }
            var target = min(20, s.currentSpeedLimit)
            if let c = s.road.nextCurve(after: s.truck.position, within: 250) { target = min(target, c.advisorySpeed) }
            if let r = s.remaining { target = min(target, (3 * max(0, r)).squareRoot()) }
            let steer = -(1.2 * s.truck.lateralOffset + 6 * s.truck.headingError)
            let input = DrivingInput(throttle: s.truck.speed < target - 1 ? 0.6 : 0,
                                     brake: s.truck.speed > target + 1 || (s.remaining ?? 1) <= 0 ? 0.6 : 0, steer: steer)
            events += s.step(dt: 1.0 / 60, input: input)
            t += 1.0 / 60
        }
        XCTAssertNotNil(s.summary, "arrived")
        XCTAssertFalse(events.contains { if case .rerouted = $0 { return true }; return false }, "never left the route")
        XCTAssertTrue(events.contains { if case .navInstruction = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .enteredTown("Ridgeport", _) = $0 { return true }; return false })
        XCTAssertEqual(s.stats.distance, planned, accuracy: 80)
    }

    func testWrongTurnReroutes() {
        guard let nav = Navigator(map: map, origin: "millbrook", destination: "ridgeport") else { return XCTFail() }
        // Route 1 then Interstate 40 is the plan; turning left at Millbrook Junction goes to Cedar Falls instead.
        nav.takeJunction(signal: .on(.left))
        XCTAssertEqual(map.to(nav.edge), "cedar_falls")
        let remaining = nav.remaining(at: 0)!
        XCTAssertEqual(map.to(nav.route.last!), "ridgeport", "new route still ends at Ridgeport")
        XCTAssertGreaterThan(remaining, 0)
    }

    func testOldSavesGetJobsFromTheCurrentTown() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CareerState(seed: 8))) as! [String: Any]
        json.removeValue(forKey: "currentTown")
        var jobs = json["jobBoard"] as! [[String: Any]]
        for i in jobs.indices { jobs[i].removeValue(forKey: "origin"); jobs[i].removeValue(forKey: "destination") }
        json["jobBoard"] = jobs
        let loaded = try JSONDecoder().decode(CareerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(loaded.currentTown, "millbrook")
        XCTAssertTrue(loaded.jobBoard.allSatisfy { $0.origin == "millbrook" })
    }
}

final class PoliceTests: XCTestCase {
    private func session(cop: Bool) -> DrivingSession {
        var road = Road(segments: [.straight(5_000)], loops: false, speedLimit: 60 / 3.6)
        road.policeSpots = [2_000]
        let s = DrivingSession(road: road, seed: 1)
        s.policePresenceChance = cop ? 1 : 0
        _ = s.perform(.toggleEngine)
        return s
    }

    private func run(_ s: DrivingSession, seconds: Double, input: (DrivingSession) -> DrivingInput) -> [SimEvent] {
        var events: [SimEvent] = []
        for _ in 0..<Int(seconds * 60) { events += s.step(dt: 1.0 / 60, input: input(s)) }
        return events
    }

    func testSpeedingPastACopMeansATicketWhenYouStop() {
        let s = session(cop: true)
        var events = run(s, seconds: 200) { s in
            // Speed to about 80 in a 60, then stop when the siren starts.
            s.sirenOn ? DrivingInput(brake: 1) : DrivingInput(throttle: s.truck.speed < 22 ? 1 : 0)
        }
        events = events.filter { if case .gearChanged = $0 { return false }; return true }
        XCTAssertTrue(events.contains(.passedPolice))
        XCTAssertTrue(events.contains { if case .policeChase = $0 { return true }; return false })
        guard case let .speedingTicket(speed, limit, fine)? = events.first(where: { if case .speedingTicket = $0 { return true }; return false })
        else { return XCTFail("no ticket: \(events)") }
        XCTAssertGreaterThan(speed, limit)
        XCTAssertEqual(fine, DrivingSession.speedingFine(speed: speed, limit: limit))
        XCTAssertEqual(s.stats.tickets, 1)
        XCTAssertTrue(Payout.freeDrive(s.stats).lines.contains { $0.label == "Speeding ticket" && $0.amount == -fine })
    }

    func testDrivingAtTheLimitIsFine() {
        let s = session(cop: true)
        let events = run(s, seconds: 200) { s in DrivingInput(throttle: s.truck.speed < 60 / 3.6 ? 0.6 : 0) }
        XCTAssertTrue(events.contains(.passedPolice))
        XCTAssertFalse(events.contains { if case .policeChase = $0 { return true }; return false })
    }

    func testNoCopNoTicket() {
        let s = session(cop: false)
        let events = run(s, seconds: 200) { s in DrivingInput(throttle: s.truck.speed < 24 ? 1 : 0) }
        XCTAssertFalse(events.contains { if case .policeChase = $0 { return true }; return false })
    }

    func testFleeingCostsMore() {
        let s = session(cop: true)
        let events = run(s, seconds: 200) { s in DrivingInput(throttle: s.truck.speed < 22 ? 1 : 0) }
        guard case let .fledPolice(fine)? = events.first(where: { if case .fledPolice = $0 { return true }; return false })
        else { return XCTFail("didn't flee") }
        XCTAssertGreaterThan(fine, 1_000)
    }

    func testFineScale() {
        XCTAssertEqual(DrivingSession.speedingFine(speed: 70 / 3.6, limit: 50 / 3.6), 600)
        XCTAssertEqual(DrivingSession.speedingFine(speed: 50 / 3.6, limit: 50 / 3.6), 100)
    }

    func testMapHasPoliceInTowns() {
        let map = WorldMap.standard
        let e = map.outgoing(from: "ridgeport").first!
        let road = map.road(e)
        XCTAssertTrue(road.policeSpots.contains { $0 < townZoneLength }, "a cop inside Ridgeport")
    }
}

final class CompanyTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)

    private func careerWithTwoTrucks() -> CareerState {
        var c = CareerState(seed: 11)
        c.money = 50_000
        c.buy(.workhorse)
        c.select(.starter)
        return c
    }

    func testHireAndEarnOverTime() {
        var c = careerWithTwoTrucks()
        let candidate = c.candidates.first { $0.skill == 2 }!
        XCTAssertEqual(c.hire(candidate, now: start), .hired)
        XCTAssertEqual(c.money, 50_000 - 6_000 - 4_000)
        XCTAssertEqual(c.drivers.count, 1)
        XCTAssertEqual(c.drivers[0].truckID, "workhorse", "gets the free truck")
        XCTAssertEqual(c.candidates.count, 3, "a new candidate takes their place")

        // 1 hour later: 25-minute jobs -> 2 done, 10 minutes into the third.
        let reports = c.updateDrivers(now: start.addingTimeInterval(3_600))
        XCTAssertEqual(reports, [DriverReport(name: candidate.name, jobs: 2, earned: 750)])
        XCTAssertEqual(c.money, 40_000 + 750)
        XCTAssertEqual(c.drivers[0].progress, 600, accuracy: 0.001)
        // 15 more minutes finishes the third job.
        XCTAssertEqual(c.updateDrivers(now: start.addingTimeInterval(4_500)).first?.jobs, 1)
    }

    func testAwayTimeIsCapped() {
        var c = careerWithTwoTrucks()
        c.hire(c.candidates.first { $0.skill == 1 }!, now: start)
        let reports = c.updateDrivers(now: start.addingTimeInterval(3 * 24 * 3_600))
        XCTAssertEqual(reports.first?.jobs, 16, "8 hours of 30-minute jobs, not 3 days")
    }

    func testDriversNeedATruck() {
        var c = CareerState(seed: 3)
        c.money = 20_000
        let candidate = c.candidates[0]
        XCTAssertEqual(c.hire(candidate, now: start), .hired)
        XCTAssertNil(c.drivers[0].truckID, "your only truck is the one you drive")
        XCTAssertEqual(c.updateDrivers(now: start.addingTimeInterval(7_200)), [])
        XCTAssertFalse(c.assign(c.drivers[0].id, to: .starter, now: start), "can't take your truck")
    }

    func testNotEnoughMoneyToHire() {
        var c = CareerState(seed: 4)
        let pricey = c.candidates.first { $0.skill == 3 }!
        XCTAssertEqual(c.hire(pricey), .notEnoughMoney(short: 9_000 - CareerState.startingMoney))
    }

    func testSwitchingToADriversTruckSwapsTrucks() {
        var c = careerWithTwoTrucks()
        c.hire(c.candidates[0], now: start)
        XCTAssertEqual(c.drivers[0].truckID, "workhorse")
        XCTAssertTrue(c.select(.workhorse))
        XCTAssertEqual(c.selectedTruck, "workhorse")
        XCTAssertEqual(c.drivers[0].truckID, "old_reliable", "the driver takes the truck you left")
    }

    func testFiringAndSaving() throws {
        var c = careerWithTwoTrucks()
        c.hire(c.candidates[0], now: start)
        let loaded = try JSONDecoder().decode(CareerState.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(loaded.drivers, c.drivers)
        c.fire(c.drivers[0].id, now: start)
        XCTAssertTrue(c.drivers.isEmpty)
    }

    func testReportPhrase() {
        let text = Phrases.driverReports([DriverReport(name: "Sam Hayes", jobs: 4, earned: 1_200)])
        XCTAssertEqual(text, "Your drivers: Sam Hayes delivered 4 jobs and earned $1,200.")
        XCTAssertNil(Phrases.driverReports([]))
    }
}

final class BalanceTests: XCTestCase {
    /// A typical 13-mile job with a couple of crashes should still pay well.
    func testRoughJobStillPays() {
        let cargo = Cargo.catalog.first { $0.name == "Lumber" }!
        let job = DeliveryJob(cargo: cargo, distance: 21_000, pay: 2_730, timeLimit: 1_800)
        var stats = TripStats()
        stats.distance = 21_000
        stats.drivingTime = 1_500
        stats.crashes = 2
        let payout = Payout.delivery(job, summary: TripSummary(goalName: "x", stats: stats, stopError: 30))
        XCTAssertGreaterThan(payout.total, Int(Double(job.pay) * 0.95))
    }

    func testFuelCheckPhrase() {
        let p = Phrases(units: .metric)
        XCTAssertTrue(p.fuelCheck(fuelLiters: 400, capacity: 400, distance: 20_000).hasPrefix("Fuel OK"))
        XCTAssertTrue(p.fuelCheck(fuelLiters: 5, capacity: 400, distance: 20_000).hasPrefix("Not enough fuel"))
    }
}

final class TrafficTests: XCTestCase {
    private func session(interstate: Bool = false) -> DrivingSession {
        var road = Road(segments: [.straight(20_000)], loops: false, speedLimit: 80 / 3.6)
        road.leftLaneSameDirection = interstate
        let s = DrivingSession(road: road, seed: 5)
        s.trafficEnabled = true
        s.oncomingTimer = 1_000 // no random spawns unless a test wants them
        s.slowTimer = 1_000
        _ = s.perform(.toggleEngine)
        for _ in 0..<120 { _ = s.step(dt: 1.0 / 60, input: .idle) }
        return s
    }

    private func run(_ s: DrivingSession, seconds: Double, input: (DrivingSession) -> DrivingInput) -> [SimEvent] {
        var events: [SimEvent] = []
        for _ in 0..<Int(seconds * 60) { events += s.step(dt: 1.0 / 60, input: input(s)) }
        return events
    }

    private func keepLane(_ s: DrivingSession, throttle: Double = 0.6) -> DrivingInput {
        DrivingInput(throttle: s.truck.speed < 20 ? throttle : 0, steer: -s.laneGuidanceOffset)
    }

    func testOncomingTrafficPassesSafelyWhenYouStayInLane() {
        let s = session()
        s.traffic = [TrafficVehicle(id: 1, kind: .truck, oncoming: true, lane: DrivingSession.leftLaneCenter,
                                    position: 400, speed: 20)]
        let events = run(s, seconds: 30) { self.keepLane($0) }
        XCTAssertFalse(events.contains { if case .crashed = $0 { return true }; return false })
        XCTAssertTrue(s.traffic.isEmpty || s.traffic[0].position < s.truck.position, "it went past")
    }

    func testDriftingIntoOncomingTrafficIsAHeadOnCrash() {
        let s = session()
        s.traffic = [TrafficVehicle(id: 1, kind: .car, oncoming: true, lane: DrivingSession.leftLaneCenter,
                                    position: 500, speed: 20)]
        let events = run(s, seconds: 30) { s in
            DrivingInput(throttle: s.truck.speed < 15 ? 0.6 : 0, steer: s.truck.lateralOffset > -3.7 ? -0.6 : 0)
        }
        XCTAssertTrue(events.contains(.oncomingHorn))
        XCTAssertTrue(events.contains(.wrongSideOfRoad))
        XCTAssertTrue(events.contains(.crashed(.collision(headOn: true, vehicle: .car))))
    }

    func testRearEndingASlowVehicle() {
        let s = session()
        s.traffic = [TrafficVehicle(id: 1, kind: .pickup, oncoming: false, lane: 0, position: 250, speed: 8)]
        let events = run(s, seconds: 60) { s in DrivingInput(throttle: 1, steer: -s.laneGuidanceOffset) }
        XCTAssertTrue(events.contains { if case .vehicleAhead(_, _, .pickup) = $0 { return true }; return false })
        XCTAssertTrue(events.contains(.tooClose))
        XCTAssertTrue(events.contains(.crashed(.collision(headOn: false, vehicle: .pickup))))
    }

    func testFollowingASlowVehicleIsSafe() {
        let s = session()
        s.traffic = [TrafficVehicle(id: 1, kind: .truck, oncoming: false, lane: 0, position: 250, speed: 8)]
        let events = run(s, seconds: 90) { s in
            let gap = (s.traffic.first?.position ?? 1e9) - s.truck.position
            let target = gap < 60 ? 7.0 : 18.0
            return DrivingInput(throttle: s.truck.speed < target ? 0.5 : 0, brake: s.truck.speed > target + 1 ? 0.8 : 0,
                                steer: -s.laneGuidanceOffset)
        }
        XCTAssertFalse(events.contains { if case .crashed = $0 { return true }; return false })
    }

    func testPassingOnTheInterstate() {
        let s = session(interstate: true)
        _ = s.perform(.signal(.left))
        let events = run(s, seconds: 20) { s in
            DrivingInput(throttle: s.truck.speed < 20 ? 0.6 : 0, steer: s.truck.lateralOffset > -3.5 ? -0.6 : 0)
        }
        XCTAssertEqual(s.targetLane, DrivingSession.leftLaneCenter, "signalled: the left lane is where you mean to be")
        XCTAssertTrue(events.contains(.changedLane(toLeft: true, oncoming: false)))
        XCTAssertFalse(events.contains(.wrongSideOfRoad))
        XCTAssertFalse(events.contains { if case .rumbleStrip(.some) = $0 { return true }; return false })
        _ = s.perform(.signal(.right))
        let back = run(s, seconds: 10) { s in DrivingInput(steer: -s.truck.lateralOffset) }
        XCTAssertTrue(back.contains(.changedLane(toLeft: false, oncoming: false)))
        XCTAssertEqual(s.targetLane, 0)
    }

    func testSpawning() {
        let twoWay = session()
        twoWay.oncomingTimer = 1
        twoWay.slowTimer = 1
        // A slow vehicle only appears once you're moving; oncoming ones start 700 m out, beyond earshot.
        _ = run(twoWay, seconds: 12) { self.keepLane($0) }
        XCTAssertTrue(twoWay.traffic.contains { $0.oncoming })
        XCTAssertTrue(twoWay.traffic.contains { !$0.oncoming })
        XCTAssertFalse(twoWay.trafficSounds.isEmpty)

        let interstate = session(interstate: true)
        interstate.oncomingTimer = 1
        _ = run(interstate, seconds: 5) { self.keepLane($0) }
        XCTAssertFalse(interstate.traffic.contains { $0.oncoming }, "the other carriageway is separate")
    }

    func testTrafficOffByDefault() {
        let s = DrivingSession(road: Road(segments: [.straight(20_000)], loops: false))
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 120) { _ = s.step(dt: 1.0 / 60, input: DrivingInput(throttle: 0.5)) }
        XCTAssertTrue(s.traffic.isEmpty)
    }
}
