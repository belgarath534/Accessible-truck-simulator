import Foundation

/// A guided first drive: one skill at a time, each step waits until the player has done it.
///
/// Feed it every frame with `update`; it returns what to say (praise plus the next instruction, or a
/// reminder when the player hasn't done the step yet). Pure logic, so the steps can be unit-tested.
public final class Tutorial {
    public enum Step: Int, CaseIterable, Sendable {
        case startEngine
        case accelerate
        case stayInLane
        case dashboard
        case roadAhead
        case signalOn
        case signalOff
        case curve
        case horn
        case brake
        case done
    }

    /// Speed the accelerate step asks for (about 30 km/h or 20 mph).
    public static let targetSpeed: Double = 8.3
    /// Seconds of driving near the middle of the lane for the lane step.
    public static let laneSeconds: Double = 15
    /// How long to wait before repeating an instruction that hasn't been done.
    public static let reminderInterval: Double = 25

    public private(set) var step: Step = .startEngine
    public var isComplete: Bool { step == .done }

    let mode: TouchSteeringMode
    let units: UnitSystem
    private var started = false
    private var sinceSpoken: Double = 0
    private var laneTime: Double = 0
    private var inCurve = false
    private var stoppedTime: Double = 0
    /// Seconds since the player did a step whose result is spoken (dashboard, GPS); nil until then.
    private var listening: Double?
    /// Time to let the dashboard or GPS reading finish before the next instruction.
    public static let listenSeconds: Double = 6

    public init(mode: TouchSteeringMode, units: UnitSystem) {
        self.mode = mode
        self.units = units
    }

    /// Steps the tutorial. `actions` are the gestures the player made since the last call.
    /// Returns text to speak, or nil.
    public func update(dt: Double, session: DrivingSession, actions: [DrivingAction]) -> String? {
        guard !isComplete else { return nil }
        if !started {
            started = true
            sinceSpoken = 0
            return Tutorial.welcome + " " + instruction(step)
        }
        if isDone(step, dt: dt, session: session, actions: actions) {
            let finished = step
            step = Step(rawValue: step.rawValue + 1) ?? .done
            sinceSpoken = 0
            resetProgress()
            if isComplete { return praise(finished) + " " + Tutorial.finished }
            return praise(finished) + " " + instruction(step)
        }
        sinceSpoken += dt
        if listening != nil { return nil } // done; waiting for the reading to finish
        if sinceSpoken >= Tutorial.reminderInterval {
            sinceSpoken = 0
            return reminder(step, session: session)
        }
        return nil
    }

    private func resetProgress() {
        laneTime = 0
        inCurve = false
        stoppedTime = 0
        listening = nil
    }

    /// For steps whose result is spoken: done a few seconds after the gesture, so the reading isn't cut off.
    private func heard(_ action: DrivingAction, in actions: [DrivingAction], dt: Double) -> Bool {
        if let t = listening {
            listening = t + dt
        } else if actions.contains(action) {
            listening = 0
        }
        return (listening ?? 0) >= Tutorial.listenSeconds
    }

    private func isDone(_ step: Step, dt: Double, session: DrivingSession, actions: [DrivingAction]) -> Bool {
        let truck = session.truck
        switch step {
        case .startEngine:
            return truck.engine == .running
        case .accelerate:
            return truck.speed >= Tutorial.targetSpeed
        case .stayInLane:
            if truck.speed > 3 && abs(session.laneGuidanceOffset) < 0.6 { laneTime += dt }
            return laneTime >= Tutorial.laneSeconds
        case .dashboard:
            return heard(.speakDashboard, in: actions, dt: dt)
        case .roadAhead:
            return heard(.speakRoadAhead, in: actions, dt: dt)
        case .signalOn:
            return truck.signal != .off
        case .signalOff:
            return truck.signal == .off
        case .curve:
            // Done once the truck has driven into a curve and out the other side.
            let curving = abs(session.road.curvature(at: truck.position)) > 0.0005
            if curving { inCurve = true }
            return inCurve && !curving
        case .horn:
            return actions.contains(.horn)
        case .brake:
            if truck.speed < 0.3 { stoppedTime += dt } else { stoppedTime = 0 }
            return stoppedTime >= 1
        case .done:
            return false
        }
    }

    // MARK: Words

    static let welcome = "Welcome to the tutorial. I'll teach you to drive one step at a time, and wait for you at each step. There's no traffic here, and crashes don't cost anything."
    static let finished = "That's everything you need. Tutorial complete! Next, take a job from the Job Board to start earning money. Two-finger swipe down opens the pause menu any time you need it."

    private var accelerateWords: String {
        mode == .tilt ? "hold your finger on the right half of the screen" : "put one finger on the screen and slide it up"
    }

    private var brakeWords: String {
        mode == .tilt ? "hold your finger on the left half of the screen" : "slide your finger down"
    }

    private var steerWords: String {
        mode == .tilt
            ? "To steer, tilt the phone like a steering wheel: lower the right end to go right, the left end to go left."
            : "To steer, slide your finger left or right."
    }

    private var targetSpeedWords: String {
        units == .metric ? "30 kilometers per hour" : "20 miles per hour"
    }

    public func instruction(_ step: Step) -> String {
        switch step {
        case .startEngine:
            let hold = mode == .tilt ? " Hold your phone sideways, like a steering wheel." : ""
            return "First, start the engine.\(hold) Tap the screen twice with three fingers."
        case .accelerate:
            return "Now let's move. To accelerate, \(accelerateWords). The engine gets louder as you speed up and the gears change by themselves. Get up to \(targetSpeedWords)."
        case .stayInLane:
            return "Now stay in your lane. \(steerWords) If you drift, you'll hear a beeping tone on that side; steer away from it, gently. Go too far and you'll hear the rumble strip. Keep the truck in the middle of the lane for 15 seconds."
        case .dashboard:
            return "Good driving. Keep going. Now read your dashboard: tap the screen twice with two fingers. You'll hear your speed, gear and fuel."
        case .roadAhead:
            return "Next, ask the GPS what's ahead: tap the screen once with three fingers. It tells you about the next curve and how far you have to go."
        case .signalOn:
            return "Turn signals choose your way at junctions on the map. Swipe right with two fingers to turn on the right signal."
        case .signalOff:
            return "Hear the ticking? That's your signal. To cancel it, tap once with two fingers."
        case .curve:
            return "Curves are announced before you reach them, with how sharp they are. Slow down before sharp ones, and steer with the curve. Keep driving and get through the next curve."
        case .horn:
            return "Nice curve. Now the horn: swipe up with two fingers."
        case .brake:
            return "Last step: stop the truck. To brake, \(brakeWords), until you've stopped completely. At a delivery you stop on the drop-off the same way."
        case .done:
            return Tutorial.finished
        }
    }

    private func praise(_ step: Step) -> String {
        switch step {
        case .startEngine: return "Engine running."
        case .accelerate: return "Great, you're up to speed."
        case .stayInLane: return "Well done, nice and steady."
        case .dashboard, .roadAhead: return "That's it."
        case .signalOn: return "Signal on."
        case .signalOff: return "Signal off."
        case .curve: return "You made it through."
        case .horn: return "Loud and clear."
        case .brake: return "Stopped. Well done!"
        case .done: return ""
        }
    }

    private func reminder(_ step: Step, session: DrivingSession) -> String {
        switch step {
        case .accelerate where session.truck.engine != .running:
            return "The engine is off. Tap twice with three fingers to start it."
        case .stayInLane where session.truck.speed < 3:
            return "Keep moving: \(accelerateWords). Then keep the truck in the middle of the lane."
        case .curve where session.truck.speed < 3:
            return "Keep driving to reach the next curve: \(accelerateWords)."
        default:
            return "Reminder: " + instruction(step)
        }
    }
}
