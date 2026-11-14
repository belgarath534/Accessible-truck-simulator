import XCTest
@testable import SimCore

final class AdvancedTutorialTests: XCTestCase {
    /// A student who does each step: drives, asks what's around, pulls into the truck stop, rolls down the hill
    /// off the gas, and stops.
    func testAStudentFinishesEveryStep() {
        let s = DrivingSession(road: .advancedLesson, goal: .freeDrive, seed: 5)
        let t = AdvancedTutorial(units: .metric)
        var said: [String] = []
        var seen: [AdvancedTutorial.Step] = []
        var signalled = false
        _ = s.perform(.toggleEngine)
        for _ in 0..<(60 * 600) {
            if seen.last != t.step { seen.append(t.step) }
            var actions: [DrivingAction] = []
            var input = DrivingInput(throttle: 0, brake: 0, steer: 0)
            let road = s.road
            let p = s.truck.position.truncatingRemainder(dividingBy: road.totalLength)
            switch t.step {
            case .drive:
                input.throttle = 0.6
            case .aroundMe:
                if !actions.contains(.speakAroundMe), said.last?.contains("three fingers") == true, s.truck.speed > 0 {
                    actions.append(.speakAroundMe); _ = s.perform(.speakAroundMe)
                }
                input.throttle = s.truck.speed < 9 ? 0.3 : 0
            case .truckStop:
                let toStop = AdvancedTutorial.truckStopAt - p
                if toStop < 200, !signalled { signalled = true; actions.append(.signal(.right)); _ = s.perform(.signal(.right)) }
                // Roll in slowly with the signal on, then stop just past the pump.
                let target = toStop > 250 ? 9.0 : 4.0
                if toStop > -30 {
                    input.throttle = s.truck.speed < target ? 0.3 : 0
                    if s.truck.speed > target + 1 { input.brake = 0.5 }
                } else {
                    input.brake = 0.8
                }
            case .leaveStop:
                input.throttle = 0.6
            case .hill:
                input.throttle = p < AdvancedTutorial.hillStart - 100 && s.truck.speed < 14 ? 0.5 : 0
                if s.truck.speed > 24 { input.brake = 0.3 }
            case .stop:
                input.brake = 0.8
            case .done:
                break
            }
            // Steer to the middle of the lane.
            input.steer = max(-1, min(1, -s.truck.lateralOffset * 0.8 - s.truck.headingError * 3))
            _ = s.step(dt: 1.0 / 60, input: input)
            if let line = t.update(dt: 1.0 / 60, session: s, actions: actions) { said.append(line) }
            if t.isComplete { break }
        }
        XCTAssertTrue(t.isComplete, "stuck at \(t.step); said: \(said.suffix(2))")
        XCTAssertEqual(seen, [.drive, .aroundMe, .truckStop, .leaveStop, .hill, .stop])
        XCTAssertTrue(said.first?.hasPrefix(AdvancedTutorial.welcome) ?? false)
        XCTAssertTrue(said.last?.hasSuffix(AdvancedTutorial.finished) ?? false)
        XCTAssertTrue(said.contains { $0.contains("with the engine brake") }, "used the engine brake on the hill")
    }

    func testTheLessonRoad() {
        let r = Road.advancedLesson
        XCTAssertTrue(r.loops)
        XCTAssertEqual(r.truckStops, [AdvancedTutorial.truckStopAt])
        XCTAssertLessThan(r.grade(at: 2_700), -0.05)
    }
}
