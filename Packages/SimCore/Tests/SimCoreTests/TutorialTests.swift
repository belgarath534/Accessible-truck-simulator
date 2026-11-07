import XCTest
@testable import SimCore

final class TutorialTests: XCTestCase {
    /// Drives the session for `seconds`, steering back to the lane centre, and feeds the tutorial.
    @discardableResult
    private func drive(_ s: DrivingSession, _ t: Tutorial, seconds: Double, throttle: Double = 0.6, brake: Double = 0,
                       actions: [DrivingAction] = [], until: Tutorial.Step? = nil) -> [String] {
        var said: [String] = []
        var pending = actions
        for _ in 0..<Int(seconds * 60) {
            for a in pending { _ = s.perform(a) }
            let input = DrivingInput(throttle: s.truck.speed < 12 ? throttle : 0, brake: brake,
                                     steer: -s.laneGuidanceOffset * 0.8)
            _ = s.step(dt: 1.0 / 60, input: input)
            if let line = t.update(dt: 1.0 / 60, session: s, actions: pending) { said.append(line) }
            pending = []
            if let until, t.step == until { break }
        }
        return said
    }

    func testWalksThroughEveryStep() {
        let s = DrivingSession(seed: 7)
        let t = Tutorial(mode: .joystick, units: .metric)
        let first = drive(s, t, seconds: 0.1, throttle: 0)
        XCTAssertTrue(first[0].hasPrefix("Welcome"))
        XCTAssertEqual(t.step, .startEngine)

        drive(s, t, seconds: 5, throttle: 0, actions: [.toggleEngine], until: .accelerate)
        XCTAssertEqual(t.step, .accelerate)
        drive(s, t, seconds: 40, until: .stayInLane)
        XCTAssertEqual(t.step, .stayInLane)
        drive(s, t, seconds: 30, until: .dashboard)
        XCTAssertEqual(t.step, .dashboard)
        drive(s, t, seconds: 3, actions: [.speakDashboard])
        XCTAssertEqual(t.step, .dashboard, "waits for the dashboard reading to finish")
        drive(s, t, seconds: 4)
        XCTAssertEqual(t.step, .roadAhead)
        drive(s, t, seconds: 7, actions: [.speakRoadAhead])
        XCTAssertEqual(t.step, .signalOn)
        drive(s, t, seconds: 0.5, actions: [.signal(.right)])
        XCTAssertEqual(t.step, .signalOff)
        drive(s, t, seconds: 0.5, actions: [.cancelSignal])
        XCTAssertEqual(t.step, .curve)
        drive(s, t, seconds: 300, until: .horn)
        XCTAssertEqual(t.step, .horn)
        drive(s, t, seconds: 0.5, actions: [.horn])
        XCTAssertEqual(t.step, .brake)
        let end = drive(s, t, seconds: 30, throttle: 0, brake: 1, until: .done)
        XCTAssertTrue(t.isComplete)
        XCTAssertTrue(end.last?.contains("Tutorial complete") ?? false)
    }

    func testRemindsWhenNothingHappens() {
        let s = DrivingSession(seed: 1)
        let t = Tutorial(mode: .tilt, units: .imperial)
        let said = drive(s, t, seconds: 60, throttle: 0)
        XCTAssertEqual(t.step, .startEngine)
        XCTAssertEqual(said.filter { $0.hasPrefix("Reminder") }.count, 2)
        XCTAssertTrue(said[0].contains("three fingers"))
    }

    func testTiltWordsAndUnits() {
        let t = Tutorial(mode: .tilt, units: .imperial)
        XCTAssertTrue(t.instruction(.accelerate).contains("right half"))
        XCTAssertTrue(t.instruction(.accelerate).contains("20 miles per hour"))
        XCTAssertTrue(t.instruction(.brake).contains("left half"))
    }
}
