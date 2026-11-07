import Foundation
import SimCore

/// A hidden mode for making App Store screenshots in the simulator:
///   TruckSim -screenshot menu|jobs|garage|company|drive
/// It opens straight to that screen with example progress, never touches the real save,
/// and in "drive" the truck drives itself down the road.
enum ScreenshotMode {
    static let screen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screenshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    static var isOn: Bool { screen != nil }

    /// A player a few hours in: three trucks, upgrades, a driver, money in the bank, in Ridgeport.
    static func demoCareer() -> CareerState {
        let start = Date()
        var c = CareerState(seed: 2_026)
        c.money = 100_000
        c.buy(.workhorse)
        c.buy(.roadKing)
        c.select(.roadKing)
        c.buyUpgrade(.engine, for: .roadKing)
        c.buyUpgrade(.engine, for: .roadKing)
        c.buyUpgrade(.tires, for: .roadKing)
        c.buyUpgrade(.brakes, for: .starter)
        if let candidate = c.candidates.first(where: { $0.skill == 2 }) { c.hire(candidate, now: start) }
        c.move(to: "ridgeport")
        c.jobsCompleted = 23
        c.money = 12_450
        return c
    }

    /// Keeps the truck in its lane at a steady speed for the driving screenshot.
    static func autopilot(_ s: DrivingSession) -> DrivingInput {
        let target = min(19.0, s.currentSpeedLimit)
        return DrivingInput(throttle: s.truck.speed < target ? 0.7 : 0, brake: 0, steer: -s.laneGuidanceOffset * 0.8)
    }
}
