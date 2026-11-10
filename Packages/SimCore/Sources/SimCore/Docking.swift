import Foundation

/// Backing into the loading dock by ear, after stopping at a delivery's drop-off.
public struct DockingState: Equatable, Sendable {
    /// Metres from the back of the trailer to the dock.
    public var distance: Double
    /// How far the trailer is to the right of the dock (negative: to the left), metres.
    public var lateral: Double
    /// Reversing speed, m/s (always backward).
    public var speed: Double = 0
    var calledOut: Set<Int> = []
}

public enum DockRating: String, Codable, Sendable {
    case perfect, good, crooked, bumped, skipped
}

public extension DrivingSession {
    /// Where the dock starts, metres behind the trailer.
    static let dockStartDistance = 20.0
    /// Fastest reversing speed, m/s (about 5 mph).
    static let dockMaxReverse = 2.2
    /// Touching the dock faster than this is a bump, m/s.
    static let dockBumpSpeed = 0.8
}

extension DrivingSession {
    /// Starts docking instead of finishing the delivery. Returns true if it started.
    func startDocking(stopError: Double, events: inout [SimEvent]) -> Bool {
        guard dockingEnabled, docking == nil, dockRating == nil else { return false }
        pendingStopError = stopError
        let lateral = Double.random(in: 0.6...1.4, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
        docking = DockingState(distance: DrivingSession.dockStartDistance, lateral: lateral)
        truck.signal = .off
        events.append(.dockingStarted(distance: DrivingSession.dockStartDistance))
        return true
    }

    func stepDocking(dt: Double, input: DrivingInput, events: inout [SimEvent]) {
        guard var d = docking else { return }
        let running = truck.engine == .running
        let target = running ? input.throttle * DrivingSession.dockMaxReverse : 0
        if input.brake > 0.05 {
            d.speed = max(0, d.speed - input.brake * 3 * dt)
        } else {
            d.speed += (target - d.speed) * min(1, dt * 1.5)
        }
        d.distance -= d.speed * dt
        // Steering moves the trailer sideways while reversing, the same way it moves the truck while driving.
        d.lateral += input.steer * d.speed * 0.45 * dt
        truck.speed = 0
        truck.lateralOffset = d.lateral
        if running { truck.rpm = spec.idleRPM + input.throttle * 250 }
        truck.engineLoad = input.throttle * 0.3

        for mark in [10, 5, 2] where d.distance <= Double(mark) && !d.calledOut.contains(mark) {
            d.calledOut.insert(mark)
            events.append(.dockingProgress(distance: Double(mark), lateral: d.lateral))
        }
        if d.distance <= 0 {
            let rating: DockRating
            if d.speed > DrivingSession.dockBumpSpeed {
                rating = .bumped
            } else if abs(d.lateral) <= 0.3 {
                rating = .perfect
            } else if abs(d.lateral) <= 0.7 {
                rating = .good
            } else {
                rating = .crooked
            }
            finishDocking(rating, events: &events)
            return
        }
        docking = d
    }

    func finishDocking(_ rating: DockRating, events: inout [SimEvent]) {
        docking = nil
        dockRating = rating
        events.append(.docked(rating))
        var result = TripSummary(goalName: goal.name, stats: stats, stopError: pendingStopError)
        result.dockRating = rating
        summary = result
        events.append(.arrived(result))
    }
}

public extension Payout {
    /// The docking bonus (or nothing), as a share of the job's pay.
    static func dockingLine(_ rating: DockRating?, pay: Int) -> Line? {
        switch rating {
        case .perfect: return Line(label: "Perfect docking bonus", amount: Int((Double(pay) * 0.05).rounded()))
        case .good: return Line(label: "Docking bonus", amount: Int((Double(pay) * 0.02).rounded()))
        default: return nil
        }
    }
}
