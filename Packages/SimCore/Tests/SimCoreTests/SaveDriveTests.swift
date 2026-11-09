import XCTest
@testable import SimCore

final class SaveDriveTests: XCTestCase {
    private let dt = 1.0 / 60

    private func drive(_ s: DrivingSession, seconds: Double) {
        for _ in 0..<Int(seconds * 60) {
            _ = s.step(dt: dt, input: DrivingInput(throttle: s.truck.speed < 18 ? 0.6 : 0, steer: -s.laneGuidanceOffset * 0.8))
        }
    }

    func testSaveAndContinueAJobOnTheMap() throws {
        let career = CareerState(seed: 11)
        let job = try XCTUnwrap(career.jobBoard.first { $0.destination != nil })
        let nav = try XCTUnwrap(Navigator(map: .standard, origin: job.origin!, destination: job.destination!))
        let s = DrivingSession(goal: job.goal, cargoMassKg: job.cargo.massKg, timeLimit: job.timeLimit, navigator: nav, seed: 3)
        s.weather = .rain
        _ = s.perform(.toggleEngine)
        drive(s, seconds: 400)
        let saved = SavedDrive(kind: .job, job: job, origin: job.origin!, snapshot: s.snapshot)
        let remainingBefore = try XCTUnwrap(s.remaining)

        // Through the save file and back.
        var c = career
        c.savedDrive = saved
        let loaded = try JSONDecoder().decode(CareerState.self, from: JSONEncoder().encode(c))
        let back = try XCTUnwrap(loaded.savedDrive)
        XCTAssertEqual(back, saved)

        let nav2 = try XCTUnwrap(Navigator(map: .standard, origin: job.origin!, destination: job.destination!))
        let r = DrivingSession(goal: job.goal, cargoMassKg: job.cargo.massKg, timeLimit: job.timeLimit, navigator: nav2, seed: 4)
        r.restore(back.snapshot)
        XCTAssertEqual(try XCTUnwrap(r.remaining), remainingBefore, accuracy: 0.5)
        XCTAssertEqual(r.stats.distance, s.stats.distance, accuracy: 0.5)
        XCTAssertEqual(r.truck.fuelLiters, s.truck.fuelLiters, accuracy: 0.01)
        XCTAssertEqual(r.weather, .rain)
        XCTAssertEqual(r.truck.speed, 0)
        XCTAssertEqual(r.truck.engine, .off)
        XCTAssertEqual(r.timeLeft ?? 0, s.timeLeft ?? 0, accuracy: 0.01)

        // It carries on to the drop-off, without repeating milestones already passed.
        _ = r.perform(.toggleEngine)
        var events: [SimEvent] = []
        for _ in 0..<(60 * 3_000) where r.summary == nil {
            var target = min(18, r.currentSpeedLimit)
            if let c = r.road.nextCurve(after: r.truck.position, within: 250) { target = min(target, c.advisorySpeed) }
            if let rem = r.remaining { target = min(target, (3 * max(0, rem)).squareRoot()) }
            for case let .navInstruction(n) in events.suffix(3) where n.distance <= 300 {
                let want: SignalState = n.turn == .left ? .on(.left) : (n.turn == .right ? .on(.right) : .off)
                if r.truck.signal != want { _ = r.perform(want == .off ? .cancelSignal : .signal(n.turn == .left ? .left : .right)) }
            }
            events += r.step(dt: dt, input: DrivingInput(throttle: r.truck.speed < target - 1 ? 0.6 : 0,
                                                        brake: r.truck.speed > target + 1 || (r.remaining ?? 1) <= 0 ? 0.6 : 0,
                                                        steer: -r.laneGuidanceOffset * 0.8))
        }
        XCTAssertNotNil(r.summary, "finished the delivery after continuing")
        let milestones = events.compactMap { e -> Double? in if case let .tripProgress(m) = e { return m }; return nil }
        XCTAssertTrue(milestones.allSatisfy { $0 < remainingBefore }, "no repeated milestones: \(milestones)")
    }

    func testSaveAndContinueThePracticeLoop() {
        let s = DrivingSession(goal: .practice(on: .practiceLoop), seed: 1)
        _ = s.perform(.toggleEngine)
        drive(s, seconds: 120)
        let r = DrivingSession(goal: .practice(on: .practiceLoop), seed: 2)
        r.restore(s.snapshot)
        XCTAssertEqual(r.truck.position, s.truck.position, accuracy: 0.01)
        XCTAssertEqual(r.remaining ?? 0, s.remaining ?? 0, accuracy: 0.01)
    }

    func testOldSavesHaveNoSavedDrive() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CareerState(seed: 1))) as! [String: Any]
        json.removeValue(forKey: "savedDrive")
        XCTAssertNil(try JSONDecoder().decode(CareerState.self, from: JSONSerialization.data(withJSONObject: json)).savedDrive)
    }
}
