import Foundation

/// Turns raw touches into the game's gestures, with exact timing. Pure logic, so it can be tested.
public struct GestureReader {
    public enum Direction: Equatable, Sendable { case up, down, left, right }
    public enum Gesture: Equatable, Sendable {
        case tap(fingers: Int, count: Int)
        case swipe(fingers: Int, Direction)
        case holdBegan
        case holdEnded
    }

    private struct Touch { var start: (x: Double, y: Double); var last: (x: Double, y: Double); var time: Double }
    private var touches: [Int: Touch] = [:]
    private var maxFingers = 0
    private var groupStart = 0.0
    private var moved = false
    private var holding = false
    private var pendingTap: (fingers: Int, time: Double, count: Int)?

    public static let swipeDistance = 40.0
    public static let tapTime = 0.35
    public static let doubleTapGap = 0.3
    public static let holdTime = 0.45

    public init() {}

    public mutating func began(id: Int, x: Double, y: Double, time: Double) -> [Gesture] {
        if touches.isEmpty {
            maxFingers = 0
            groupStart = time
            moved = false
        }
        touches[id] = Touch(start: (x, y), last: (x, y), time: time)
        maxFingers = max(maxFingers, touches.count)
        var out: [Gesture] = []
        if holding { holding = false; out.append(.holdEnded) }
        return out
    }

    public mutating func moved(id: Int, x: Double, y: Double, time: Double) {
        guard var t = touches[id] else { return }
        t.last = (x, y)
        touches[id] = t
        if hypot(x - t.start.x, y - t.start.y) > 12 { moved = true }
    }

    public mutating func ended(id: Int, x: Double, y: Double, time: Double) -> [Gesture] {
        guard let t = touches.removeValue(forKey: id) else { return [] }
        var out: [Gesture] = []
        if holding { holding = false; out.append(.holdEnded) }
        guard touches.isEmpty else { return out }
        let dx = x - t.start.x, dy = y - t.start.y
        if hypot(dx, dy) >= Self.swipeDistance {
            let dir: Direction = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
            out.append(.swipe(fingers: maxFingers, dir))
        } else if !moved, time - groupStart < Self.tapTime {
            if let p = pendingTap, p.fingers == maxFingers, time - p.time < Self.doubleTapGap {
                pendingTap = nil
                out.append(.tap(fingers: maxFingers, count: 2))
            } else {
                out += flush(now: time, force: true)
                pendingTap = (maxFingers, time, 1)
            }
        }
        return out
    }

    /// Call every frame: holds start after a moment, and single taps are confirmed once no second tap came.
    public mutating func update(time: Double) -> [Gesture] {
        var out = flush(now: time, force: false)
        if !holding, touches.count == 1, !moved, maxFingers == 1, time - groupStart > Self.holdTime {
            holding = true
            out.append(.holdBegan)
        }
        return out
    }

    private mutating func flush(now: Double, force: Bool) -> [Gesture] {
        guard let p = pendingTap, force || now - p.time >= Self.doubleTapGap else { return [] }
        pendingTap = nil
        return [.tap(fingers: p.fingers, count: 1)]
    }

    public mutating func cancelAll() -> [Gesture] {
        touches = [:]
        pendingTap = nil
        if holding { holding = false; return [.holdEnded] }
        return []
    }
}

/// What each gesture does while flying.
public enum GestureMap {
    public enum Command: Equatable, Sendable {
        case action(FlightAction)
        case pause
        case recenter
        case brakes(Bool)
    }

    public static func command(for g: GestureReader.Gesture) -> Command? {
        switch g {
        case .swipe(1, .up): return .action(.throttleUp)
        case .swipe(1, .down): return .action(.throttleDown)
        case .swipe(2, .up): return .action(.throttleFull)
        case .swipe(2, .down): return .pause
        case .swipe(2, .right): return .action(.flapsDown)
        case .swipe(2, .left): return .action(.flapsUp)
        case .swipe(3, .up): return .action(.toggleAutopilot)
        case .swipe(3, .down): return .action(.throttleIdle)
        case .tap(2, 1): return .recenter
        case .tap(2, 2): return .action(.speakInstruments)
        case .tap(3, 1): return .action(.speakNavigation)
        case .tap(3, 2): return .action(.toggleEngine)
        case .holdBegan: return .brakes(true)
        case .holdEnded: return .brakes(false)
        default: return nil
        }
    }

    public struct Help: Hashable, Sendable {
        public let gesture: String
        public let action: String
    }

    public static let help: [Help] = [
        Help(gesture: "Three-finger double tap", action: "Start or stop the engine"),
        Help(gesture: "One-finger swipe up or down", action: "Throttle up or down by 10 percent"),
        Help(gesture: "Two-finger swipe up", action: "Full throttle"),
        Help(gesture: "Three-finger swipe down", action: "Throttle to idle"),
        Help(gesture: "Two-finger swipe right or left", action: "Flaps down or up"),
        Help(gesture: "Hold one finger still", action: "Wheel brakes, on the ground"),
        Help(gesture: "Two-finger double tap", action: "Instruments: speed, altitude, heading and more"),
        Help(gesture: "Three-finger tap", action: "Navigation: where the airport is"),
        Help(gesture: "Three-finger swipe up", action: "Autopilot on or off (holds height and heading)"),
        Help(gesture: "Two-finger tap", action: "Recenter: the way you hold the phone now is level"),
        Help(gesture: "Two-finger swipe down", action: "Pause"),
    ]
}
