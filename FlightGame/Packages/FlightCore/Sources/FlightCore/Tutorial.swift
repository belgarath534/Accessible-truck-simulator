import Foundation

/// The guided first flight: one thing at a time, each part of the plane explained when you first use it.
/// The teacher waits until you've done each step, reminds you if you're stuck, and lets you retry after a crash.
public struct Tutorial: Sendable {
    public enum Step: Int, CaseIterable, Sendable {
        case engine, throttleUp, throttleIdle, instruments, takeoffRoll, rotate, climb, levelOff
        case turn, levelWings, descend, flapsDown, flapsUp, stallTalk, navigation, autopilot, done
    }

    public private(set) var step: Step = .engine
    private var announced = false
    private var stepTime = 0.0
    private var held = 0.0
    private var doneFor: Double?
    private var lastReminder = 0.0
    private var startHeading = 0.0

    public init() {}

    public var isComplete: Bool { step == .done }

    public static let retryText = "That was a crash, and that's fine. This is how pilots learn in simulators. Let's try again."

    public static let completionMessage = "Tutorial complete! You started the engine, took off, climbed, turned, used the flaps and the autopilot. Next: Flight School lesson 3 teaches landing. Everything you learned is in Ground School and How to Fly on the main menu."

    /// What the teacher says when a step begins.
    public static func instruction(_ step: Step) -> String {
        switch step {
        case .engine:
            return "Welcome to your first flight. I'm your instructor, and I'll explain everything as we go. Hold the phone sideways in both hands, like a steering wheel. You're sitting in a small plane at the start of a runway. First, the engine. It spins the propeller on the nose, and the propeller pulls the plane forward. Tap twice with three fingers to start it."
        case .throttleUp:
            return "Engine running. Next, the throttle. It's the plane's gas pedal: more throttle, more power. Swipe up once with one finger to add 10 percent."
        case .throttleIdle:
            return "Hear the engine speed up? The plane starts to creep forward. Now swipe down with one finger to bring the throttle back to idle."
        case .instruments:
            return "Good. A pilot checks the instruments all the time. Tap twice with two fingers to hear yours: speed, height, direction and more."
        case .takeoffRoll:
            return "Now the takeoff. Wings lift the plane when air flows over them fast enough, so we speed up along the runway. Swipe up with two fingers for full throttle. If you hear beeping on one side, you're drifting that way: turn the phone like a steering wheel away from the beeps, to stay in the middle."
        case .rotate:
            return "Fast enough to fly! Gently tilt the top of the phone back toward you. That lifts the nose, and the wings carry us up."
        case .climb:
            return "We're flying! You just used the elevator, a flap on the tail that points the nose up or down. Nose up climbs but slows you down. Nose down descends and speeds you up. Those rising beeps mean we're climbing. Keep the phone tilted back a little and climb to 1,000 feet."
        case .levelOff:
            return "1,000 feet. Now level off. Ease the phone forward to where you held it at the start, until the climbing beeps stop. Then swipe down with one finger three times, to bring the throttle to 70 percent. That's cruise power."
        case .turn:
            return "Nice and level. Now a turn. Planes turn by leaning, like a bike. Small flaps on the wings, called ailerons, roll the plane. Turn the phone like a steering wheel to the right and hold it there. You'll hear a tone from the low wing. Keep turning until I say stop."
        case .levelWings:
            return "Stop the turn. Turn the phone back to level, until the wing tone goes quiet."
        case .descend:
            return "Wings level. Now let's go down. To descend, pilots reduce power. Swipe down with one finger until the throttle is at 30 percent, then tip the phone forward a little. A low hum means we're descending."
        case .flapsDown:
            return "We're descending. Now, the flaps. Flaps are panels on the back edge of the wings that slide out and down. They let the plane fly slower without falling, which is exactly what you want for landing. Swipe right with two fingers to lower the flaps one step."
        case .flapsUp:
            return "Flaps 1. Feel the plane slow down. Flaps are for landing, so let's put them away again. Swipe left with two fingers."
        case .stallTalk:
            return "Flaps up. One warning every pilot learns: the stall. If the plane flies too slowly, the wings stop lifting, and it drops. You'll hear a harsh horn before that happens. The cure is always the same: nose down, and more power."
        case .navigation:
            return "Now, finding your way. Tap once with three fingers to hear where the nearest airport is. The short beep you hear every second or two comes from its direction."
        case .autopilot:
            return "Last one: the autopilot. It holds your height and direction, so you can rest your hands. Swipe up with three fingers to switch it on."
        case .done:
            return completionMessage
        }
    }

    /// A short nudge when a step is taking a while.
    public static func reminder(_ step: Step) -> String {
        switch step {
        case .engine: return "Tap twice with three fingers to start the engine."
        case .throttleUp: return "Swipe up once with one finger."
        case .throttleIdle: return "Swipe down with one finger until the throttle is at idle."
        case .instruments: return "Tap twice with two fingers to hear the instruments."
        case .takeoffRoll: return "Swipe up with two fingers for full throttle, and steer away from the beeps."
        case .rotate: return "Tilt the top of the phone back toward you to lift off."
        case .climb: return "Keep the phone tilted back a little. Climb to 1,000 feet. Two-finger double tap tells you your height."
        case .levelOff: return "Ease the phone forward until the climb beeps stop, and bring the throttle down to 70 percent with one-finger swipes down."
        case .turn: return "Turn the phone to the right like a steering wheel and hold it."
        case .levelWings: return "Turn the phone back to level until the wing tone stops."
        case .descend: return "Throttle to 30 percent with one-finger swipes down, then tip the phone forward a little."
        case .flapsDown: return "Swipe right with two fingers for flaps. If it says too fast, lift the nose a little to slow down."
        case .flapsUp: return "Swipe left with two fingers to raise the flaps."
        case .stallTalk: return ""
        case .navigation: return "Tap once with three fingers."
        case .autopilot: return "Swipe up with three fingers for the autopilot."
        case .done: return ""
        }
    }

    /// Call every frame with what the pilot just did. Returns lines for the teacher to say.
    public mutating func update(session s: FlightSession, actions: [FlightAction], dt: Double) -> [String] {
        guard step != .done else { return [] }
        var lines: [String] = []
        if !announced {
            announced = true
            stepTime = 0
            held = 0
            doneFor = nil
            lastReminder = 0
            startHeading = s.heading
            lines.append(Self.instruction(step))
        }
        stepTime += dt

        // Finished the step: a short pause (longer after a spoken readout), then on to the next.
        if let d = doneFor {
            doneFor = d + dt
            if d + dt >= settle { advance() }
            return lines
        }

        func hold(_ condition: Bool, for seconds: Double) -> Bool {
            held = condition ? held + dt : 0
            return held >= seconds
        }

        let met: Bool
        switch step {
        case .engine: met = s.engine == .running
        case .throttleUp: met = s.throttle >= 0.05
        case .throttleIdle: met = s.throttle < 0.05
        case .instruments: met = actions.contains(.speakInstruments)
        case .takeoffRoll: met = s.airspeed >= 24 || !s.onGround
        case .rotate: met = !s.onGround && s.altitude > 12
        case .climb: met = Units.feet(s.altitude) >= 1_000
        case .levelOff: met = hold(abs(s.verticalSpeed) < 1.6 && s.throttle <= 0.75, for: 3)
        case .turn: met = abs(Units.turn(from: startHeading, to: s.heading)) >= 80
        case .levelWings: met = hold(abs(s.bank) < 6, for: 2)
        case .descend: met = hold(s.throttle <= 0.45 && s.verticalSpeed < -1, for: 3)
        case .flapsDown: met = s.flaps >= 1
        case .flapsUp: met = s.flaps == 0
        case .stallTalk: met = stepTime > 16
        case .navigation: met = actions.contains(.speakNavigation)
        case .autopilot: met = s.autopilot != nil
        case .done: met = false
        }
        if met {
            doneFor = 0
        } else if stepTime - lastReminder > 28, !Self.reminder(step).isEmpty {
            lastReminder = stepTime
            lines.append(Self.reminder(step))
        }
        return lines
    }

    /// Time between doing the step and the next instruction, so readouts aren't talked over.
    private var settle: Double {
        switch step {
        case .instruments: return 9
        case .navigation: return 8
        case .autopilot: return 4
        case .stallTalk: return 0
        default: return 1.2
        }
    }

    private mutating func advance() {
        step = Step(rawValue: step.rawValue + 1) ?? .done
        announced = false
    }

    /// After a crash: where to put the plane, whether its engine is already running, and what to say.
    /// On the ground you go back to the takeoff; in the air you get the plane back at 2,500 feet.
    public mutating func retry() -> (start: FlightStart, text: String) {
        let ground = step.rawValue <= Step.rotate.rawValue
        if ground {
            if step.rawValue > Step.takeoffRoll.rawValue { step = .takeoffRoll }
        } else if step == .flapsUp {
            step = .flapsDown
        }
        announced = false
        let text = Self.retryText
        return (ground ? .runway("pine") : .air(x: 2_000, y: 3_000, altitude: 760, heading: 90, speed: 50, throttle: 0.65, flaps: 0), text)
    }

    /// Whether the retry plane should have its engine running already.
    public var retryEngineRunning: Bool { step.rawValue > Step.engine.rawValue }
}

/// Ground School: every part of the plane, in plain words.
public enum GroundSchool {
    public struct Topic: Hashable, Sendable {
        public let title: String
        public let text: String
    }

    public static let parts: [Topic] = [
        Topic(title: "Engine and propeller", text: "The engine spins the propeller on the nose. The propeller pulls the plane forward through the air, like a fan pulling itself along."),
        Topic(title: "Throttle", text: "The plane's gas pedal. More throttle means more power: you speed up or climb. Less throttle means less power: you slow down or descend. Full throttle for takeoff, about 70 percent to cruise, about 30 percent to come down."),
        Topic(title: "Wings", text: "Wings lift the plane, but only when air flows over them fast enough. That's why a plane needs a runway: it has to get up to flying speed first."),
        Topic(title: "Yoke", text: "The plane's steering wheel, and in this game, your phone. Tilt it back to raise the nose, forward to lower it, and turn it left or right to lean the plane."),
        Topic(title: "Elevator", text: "A flap on the tail that points the nose up or down. Tilting the phone back or forward moves it. Nose up climbs and slows you down. Nose down descends and speeds you up."),
        Topic(title: "Ailerons", text: "Small flaps near the wing tips. Turning the phone moves them: one wing rises and the other drops. That lean is called a bank, and a banked plane turns, like a bike leaning into a corner."),
        Topic(title: "Flaps", text: "Panels on the back edge of the wings that slide out and down. They let the plane fly slower without falling, and they add drag to help you slow down. Use them for landing: flaps 1 on the way in, flaps 2 close to the runway. Raise them after takeoff. They can only go down below 85 knots."),
        Topic(title: "Wheels and brakes", text: "On the ground the plane rolls on three wheels. Turning the phone steers the nose wheel. Holding one finger still on the screen works the brakes."),
        Topic(title: "Autopilot", text: "A helper that holds your height and direction so you can rest. Move the controls firmly and it hands the plane back."),
    ]

    public static let ideas: [Topic] = [
        Topic(title: "Airspeed, in knots", text: "How fast you move through the air. One knot is a bit more than one mile per hour. This plane lifts off at about 55 knots, cruises at about 105, and lands at about 65."),
        Topic(title: "Altitude, in feet", text: "Your height above the ground. A normal flight here cruises at 2,000 to 3,000 feet."),
        Topic(title: "Heading", text: "The direction the nose points, as three numbers like a compass: 360 is north, 090 east, 180 south, 270 west."),
        Topic(title: "Stall", text: "If the plane flies too slowly, the wings stop lifting and it drops. A harsh horn warns you first. The cure is always the same: nose down, more power."),
        Topic(title: "Runway numbers", text: "A runway is named for the direction you land on it, without the last zero. Runway 9 points to heading 090, east."),
        Topic(title: "A whole flight", text: "Start the engine. Full throttle. Stay on the centerline. Lift the nose at 55 knots. Climb, then level off and reduce power. Follow the beacon to the airport. Reduce power and descend. Lower the flaps. Follow the landing tones to the runway. Just above the ground, lift the nose a little and cut the power. Brake to a stop."),
    ]
}
