import Foundation

/// Something that teaches during a drive: feed it every frame, it says what to do next.
public protocol GuidedLesson: AnyObject {
    var isComplete: Bool { get }
    /// `actions`: gestures since the last call. Returns something to say, or nil.
    func update(dt: Double, session: DrivingSession, actions: [DrivingAction]) -> String?
}

extension Tutorial: GuidedLesson {}

public extension Road {
    /// The advanced tutorial's road: a truck stop, then a steep downhill to try the engine brake. It loops.
    static let advancedLesson: Road = {
        var r = Road(segments: [.straight(1_500), .right(radius: 900, length: 400), .straight(1_600),
                                .left(radius: 900, length: 400), .straight(1_100)], loops: true)
        r.truckStops = [AdvancedTutorial.truckStopAt]
        r.hills = [Hill(start: AdvancedTutorial.hillStart, end: AdvancedTutorial.hillEnd, grade: -0.07)]
        return r
    }()
}

/// The second tutorial, for the newer features: what's around me, truck stops, the engine brake on a steep
/// hill, and a spoken tour of everything else (duels, online races, the road train, the manual gearbox).
public final class AdvancedTutorial: GuidedLesson {
    public enum Step: Int, CaseIterable, Sendable {
        case drive, aroundMe, truckStop, leaveStop, hill, stop, done
    }

    static let truckStopAt = 1_100.0
    static let hillStart = 2_300.0
    static let hillEnd = 3_100.0
    public static let reminderInterval = 25.0

    public private(set) var step: Step = .drive
    public var isComplete: Bool { step == .done }

    let units: UnitSystem
    private var started = false
    private var sinceSpoken = 0.0
    private var listening: Double?
    private var held = 0.0
    private var sawEngineBrake = false

    public init(units: UnitSystem) { self.units = units }

    public static let welcome = "Welcome to the advanced tutorial. It shows you the newer features, one at a time, on a quiet road with no traffic."

    public static let finished = "Advanced tutorial complete! A few more new things to try. Duel Mode and Online Race on the main menu let you race your friends, on one phone or over the internet. The Garage has the Road Train, with two trailers and bigger pay. In Settings you'll find the manual gearbox, and Tiredness and naps. And a four-finger swipe left or right changes songs on the radio. Have fun out there!"

    public func update(dt: Double, session: DrivingSession, actions: [DrivingAction]) -> String? {
        guard !isComplete else { return nil }
        if !started {
            started = true
            sinceSpoken = 0
            return Self.welcome + " " + instruction(step)
        }
        if isDone(dt: dt, session: session, actions: actions) {
            let finished = step
            step = Step(rawValue: step.rawValue + 1) ?? .done
            sinceSpoken = 0
            listening = nil
            held = 0
            if isComplete { return praise(finished) + " " + Self.finished }
            return praise(finished) + " " + instruction(step)
        }
        sinceSpoken += dt
        if listening != nil { return nil }
        if sinceSpoken >= Self.reminderInterval {
            sinceSpoken = 0
            return reminder(session: session)
        }
        return nil
    }

    /// Where the truck is on the looping road, 0..<length.
    private func place(_ s: DrivingSession) -> Double {
        let len = s.road.totalLength
        let p = s.truck.position.truncatingRemainder(dividingBy: len)
        return p < 0 ? p + len : p
    }

    private func isDone(dt: Double, session s: DrivingSession, actions: [DrivingAction]) -> Bool {
        switch step {
        case .drive:
            return s.truck.engine == .running && s.truck.speed > 8
        case .aroundMe:
            // Let the description finish before moving on.
            if let l = listening {
                listening = l + dt
                return l + dt >= Tutorial.listenSeconds
            }
            if actions.contains(.speakAroundMe) { listening = 0 }
            return false
        case .truckStop:
            return s.isRefueling
        case .leaveStop:
            return !s.isAtTruckStop && s.truck.speed > 5
        case .hill:
            let p = place(s)
            if p > Self.hillStart && p < Self.hillEnd && s.truck.engineBraking { sawEngineBrake = true }
            return p > Self.hillEnd + 50 && p < Self.hillEnd + 600
        case .stop:
            held = s.truck.speed < 0.3 ? held + dt : 0
            return held > 1
        case .done:
            return false
        }
    }

    public func instruction(_ step: Step) -> String {
        switch step {
        case .drive:
            return "Start the engine with a three-finger double tap, and drive off. Get up to about \(units.speed(30 / 3.6)) \(units.speedUnitSpoken)."
        case .aroundMe:
            return "First, what's around me. Swipe down with three fingers. On a real road it tells you about traffic, deer, hills, weigh stations and the weather."
        case .truckStop:
            return "Next, a truck stop. There's one just ahead. As you reach it, signal right with a two-finger swipe right, slow down, and stop at the pump. If you go past, don't worry: the road loops around."
        case .leaveStop:
            return "While you're stopped, the tank fills up. On long drives you'll get tired, and stopping at a truck stop gives you a quick nap and a bonus on your next delivery. When you're ready, drive off."
        case .hill:
            return "Now a steep hill, going down. Take your finger off the gas and let the truck roll. The engine brake holds it back: listen for its deep rattle. Use the brakes only if you need to, because on long hills they get hot."
        case .stop:
            return "Now bring the truck to a stop."
        case .done:
            return ""
        }
    }

    private func praise(_ step: Step) -> String {
        switch step {
        case .drive: return "Good."
        case .aroundMe: return "That's it."
        case .truckStop: return "You're at the pump."
        case .leaveStop: return "Back on the road."
        case .hill: return sawEngineBrake ? "Nice and controlled, with the engine brake." : "You made it down."
        case .stop: return "Stopped."
        case .done: return ""
        }
    }

    private func reminder(session s: DrivingSession) -> String {
        switch step {
        case .drive where s.truck.engine != .running: return "Tap twice with three fingers to start the engine."
        case .truckStop where s.truck.speed < 1: return "Signal right with a two-finger swipe right, then drive on slowly to the truck stop and stop there."
        case .hill where s.truck.speed < 2: return "Drive on to the hill, and let the engine brake hold the truck on the way down."
        default: return instruction(step)
        }
    }
}
