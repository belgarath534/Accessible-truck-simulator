import Foundation

public struct TouchPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum SwipeDirection: String, Equatable, Sendable { case up, down, left, right }

public enum TouchGesture: Equatable, Sendable {
    case tap(fingers: Int, count: Int)
    case swipe(fingers: Int, direction: SwipeDirection)
}

public enum TouchSteeringMode: String, CaseIterable, Sendable {
    /// Phone held like a steering wheel. Hold right half = accelerate, hold left half = brake, tilt to steer.
    case tilt
    /// One-finger joystick: put a finger down anywhere, slide up to accelerate, down to brake, left/right to steer.
    case joystick
}

/// Turns raw touches into pedals/steering and multi-finger gestures.
///
/// Pure logic (no UIKit) so the rules can be unit-tested. The driving view feeds it every touch, and the
/// view is marked "allows direct interaction" so this works with VoiceOver on.
///
/// Rules:
/// - Fingers that land together (within `clusterWindow`) form a group.
/// - A lone finger that stays down longer than `controlDelay` becomes a *control* finger (pedal or joystick).
/// - A group of 2+ fingers is a *gesture*: a tap if it barely moves, a swipe if it moves.
/// - Repeated taps with the same finger count become double/triple taps.
public final class TouchInterpreter {
    public var mode: TouchSteeringMode
    /// Width of the touch area in points; used to split the screen into left/right pedals.
    public var areaWidth: Double

    public var clusterWindow = 0.12
    public var controlDelay = 0.16
    public var tapMaxDuration = 0.4
    public var tapMaxMove = 30.0
    public var swipeMinMove = 50.0
    public var multiTapWindow = 0.32
    public var joystickRadius = 110.0
    public var joystickDeadZone = 14.0

    private enum Role { case pending, control, gesture }

    private struct Tracked {
        var start: TouchPoint
        var current: TouchPoint
        var startTime: Double
        var role: Role
        var cluster: Int
    }

    private struct Cluster {
        var startTime: Double
        var members: Set<Int>
        var maxFingers: Int
        var active: Set<Int>
        var displacement: [Int: (dx: Double, dy: Double)] = [:]
        var lastEnd: Double = 0
    }

    private var touches: [Int: Tracked] = [:]
    private var clusters: [Int: Cluster] = [:]
    private var nextCluster = 0
    private var controlOrder: [Int] = []

    private var pendingTap: (fingers: Int, count: Int, time: Double)?
    private var outbox: [TouchGesture] = []

    public init(mode: TouchSteeringMode, areaWidth: Double) {
        self.mode = mode
        self.areaWidth = areaWidth
    }

    // MARK: Feeding touches

    public func began(id: Int, at p: TouchPoint, time: Double) {
        let open = clusters.first { _, c in
            time - c.startTime <= clusterWindow && !c.active.isEmpty &&
                c.members.allSatisfy { touches[$0]?.role != .control }
        }?.key
        let clusterID: Int
        if let open {
            clusterID = open
        } else {
            clusterID = nextCluster
            nextCluster += 1
            clusters[clusterID] = Cluster(startTime: time, members: [], maxFingers: 0, active: [])
        }
        touches[id] = Tracked(start: p, current: p, startTime: time, role: .pending, cluster: clusterID)
        clusters[clusterID]!.members.insert(id)
        clusters[clusterID]!.active.insert(id)
        let c = clusters[clusterID]!
        clusters[clusterID]!.maxFingers = max(c.maxFingers, c.active.count)
        if c.members.count >= 2 {
            for m in c.members { touches[m]?.role = .gesture }
        }
    }

    public func moved(id: Int, to p: TouchPoint, time: Double) {
        touches[id]?.current = p
    }

    public func ended(id: Int, at p: TouchPoint, time: Double) {
        guard var t = touches.removeValue(forKey: id) else { return }
        t.current = p
        controlOrder.removeAll { $0 == id }
        guard var c = clusters[t.cluster] else { return }
        c.active.remove(id)
        c.displacement[id] = (p.x - t.start.x, p.y - t.start.y)
        c.lastEnd = time
        clusters[t.cluster] = c

        switch t.role {
        case .control:
            clusters[t.cluster] = nil
        case .pending:
            clusters[t.cluster] = nil
            // A quick single-finger touch.
            if time - t.startTime < tapMaxDuration && hypot(p.x - t.start.x, p.y - t.start.y) < tapMaxMove {
                registerTap(fingers: 1, time: time)
            }
        case .gesture:
            if c.active.isEmpty {
                clusters[t.cluster] = nil
                classify(c)
            }
        }
    }

    /// Call every frame. Promotes lone fingers to controls and releases single taps once the
    /// double-tap window has passed. Returns the finished gestures.
    public func update(time: Double) -> [TouchGesture] {
        for (id, t) in touches where t.role == .pending && time - t.startTime >= controlDelay {
            if clusters[t.cluster]?.members.count == 1 {
                touches[id]?.role = .control
                controlOrder.append(id)
            }
        }
        let gestureInProgress = touches.values.contains { $0.role == .gesture }
        if let tap = pendingTap, time - tap.time > multiTapWindow, !gestureInProgress {
            outbox.append(.tap(fingers: tap.fingers, count: tap.count))
            pendingTap = nil
        }
        defer { outbox.removeAll() }
        return outbox
    }

    // MARK: Continuous controls

    public func input(at time: Double) -> DrivingInput {
        var result = DrivingInput()
        switch mode {
        case .tilt:
            for id in controlOrder {
                guard let t = touches[id] else { continue }
                let held = time - t.startTime
                if t.start.x < areaWidth / 2 {
                    result.brake = max(result.brake, min(1, 0.3 + held / 0.5))
                } else {
                    result.throttle = max(result.throttle, min(1, 0.25 + held / 0.8))
                }
            }
        case .joystick:
            guard let id = controlOrder.last, let t = touches[id] else { return result }
            let dx = t.current.x - t.start.x
            let up = t.start.y - t.current.y
            result.steer = min(1, max(-1, dx / joystickRadius))
            if up > joystickDeadZone {
                result.throttle = min(1, (up - joystickDeadZone) / joystickRadius)
            } else if up < -joystickDeadZone {
                result.brake = min(1, (-up - joystickDeadZone) / joystickRadius)
            }
        }
        return result
    }

    /// True while at least one finger is acting as a pedal or joystick.
    public var hasControlTouch: Bool { !controlOrder.isEmpty }

    public func reset() {
        touches.removeAll()
        clusters.removeAll()
        controlOrder.removeAll()
        pendingTap = nil
        outbox.removeAll()
    }

    // MARK: Private

    private func classify(_ c: Cluster) {
        let moves = c.displacement.values
        guard !moves.isEmpty else { return }
        let n = Double(moves.count)
        let avgX = moves.map(\.dx).reduce(0, +) / n
        let avgY = moves.map(\.dy).reduce(0, +) / n
        let maxMove = moves.map { hypot($0.dx, $0.dy) }.max() ?? 0
        let duration = c.lastEnd - c.startTime

        if maxMove < tapMaxMove && duration < tapMaxDuration {
            registerTap(fingers: c.maxFingers, time: c.lastEnd)
        } else if hypot(avgX, avgY) >= swipeMinMove {
            let dir: SwipeDirection = abs(avgX) > abs(avgY) ? (avgX > 0 ? .right : .left) : (avgY > 0 ? .down : .up)
            flushPendingTap()
            outbox.append(.swipe(fingers: c.maxFingers, direction: dir))
        }
    }

    private func registerTap(fingers: Int, time: Double) {
        if let tap = pendingTap, tap.fingers == fingers, time - tap.time <= multiTapWindow + tapMaxDuration {
            pendingTap = (fingers, tap.count + 1, time)
        } else {
            flushPendingTap()
            pendingTap = (fingers, 1, time)
        }
    }

    private func flushPendingTap() {
        if let tap = pendingTap {
            outbox.append(.tap(fingers: tap.fingers, count: tap.count))
            pendingTap = nil
        }
    }
}

/// The default gesture → action mapping for the driving screen.
public enum GestureMap {
    public static func action(for gesture: TouchGesture) -> DrivingAction? {
        switch gesture {
        case .swipe(2, .left): return .signal(.left)
        case .swipe(2, .right): return .signal(.right)
        case .tap(2, 1): return .cancelSignal
        case .tap(2, 2): return .speakDashboard
        case .tap(3, 1): return .speakRoadAhead
        case .tap(3, 2): return .toggleEngine
        case .swipe(2, .up): return .horn
        case .swipe(2, .down): return .pause
        default: return nil
        }
    }

    /// Spoken help for the controls screen and the in-game help.
    public struct Help: Hashable, Sendable {
        public let gesture: String
        public let action: String
        init(_ gesture: String, _ action: String) { self.gesture = gesture; self.action = action }
    }

    public static let help: [Help] = [
        Help("Three-finger double tap", "Start or stop the engine"),
        Help("Two-finger double tap", "Speak the dashboard: speed, gear, fuel and more"),
        Help("Three-finger tap", "GPS: what's on the road ahead"),
        Help("Two-finger swipe left or right", "Turn signal left or right"),
        Help("Two-finger tap", "Cancel turn signal"),
        Help("Two-finger swipe up", "Horn"),
        Help("Two-finger swipe down", "Pause menu"),
    ]
}
