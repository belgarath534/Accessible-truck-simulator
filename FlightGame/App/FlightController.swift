import FlightCore
import QuartzCore
import SwiftUI
import UIKit

/// What to fly: a lesson, a planned flight or free flight.
struct FlightRequest: Identifiable {
    let id = UUID()
    let title: String
    let start: FlightStart
    let goal: FlightGoal
    let lesson: Lesson?
    let briefing: String
    var isTutorial = false

    /// The guided first flight.
    static let tutorial = FlightRequest(title: "Your First Flight", start: .runway("pine"), goal: .tutorial,
                                        lesson: nil, briefing: "", isTutorial: true)
}

/// Runs one flight: the clock, controls, gestures, sound and speech.
final class FlightController: NSObject, ObservableObject {
    @Published private(set) var isPaused = false
    @Published private(set) var finished: FlightSummary?
    /// For the on-screen instruments (sighted players and screenshots).
    @Published private(set) var reading: InstrumentReading

    let request: FlightRequest
    let settings: FlightSettings
    private(set) var session: FlightSession
    private let audio = FlightAudio()
    private let speech = Speech()
    private let yoke = YokeInput()
    private var reader = GestureReader()
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var accumulator = 0.0
    private var brake = false
    private var stick: (id: ObjectIdentifier, start: CGPoint, now: CGPoint)?
    private var touchIDs: [ObjectIdentifier: Int] = [:]
    private var nextTouchID = 1
    private var lastStallSound = -10.0
    /// The guided first flight's teacher (nil on other flights), and what the pilot did this frame.
    private var tutorial: Tutorial?
    private var recentActions: [FlightAction] = []
    weak var view: UIView?

    /// The tutorial always flies with Easy assist.
    private var assist: FlightAssist { request.isTutorial ? .easy : settings.assist }

    init(request: FlightRequest, settings: FlightSettings) {
        self.request = request
        self.settings = settings
        session = FlightSession(start: request.start, goal: request.goal,
                                assist: request.isTutorial ? .easy : settings.assist)
        tutorial = request.isTutorial ? Tutorial() : nil
        reading = session.instruments
        super.init()
    }

    // MARK: Lifecycle

    func start() {
        guard link == nil else { return }
        speech.useVoiceOver = settings.useVoiceOver
        speech.recordedVoices = settings.recordedVoices
        yoke.rangeDegrees = settings.tiltRange
        yoke.invertPitch = settings.invertPitch
        if settings.controlMode == .tilt { yoke.start() }
        audio.start()
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        lastTime = 0
        UIApplication.shared.isIdleTimerDisabled = true
        heavy.prepare()
        if !request.briefing.isEmpty { speech.say(request.briefing, priority: .high) }
    }

    func stop() {
        link?.invalidate()
        link = nil
        yoke.stop()
        audio.stop()
        speech.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func pause() {
        guard !isPaused, finished == nil else { return }
        isPaused = true
        audio.state.paused = true
        audio.updateLayers()
        brake = false
        _ = reader.cancelAll()
        stick = nil
        // Nothing keeps talking over the pause menu.
        speech.stop()
        if !UIAccessibility.isVoiceOverRunning { speech.say("Paused.", priority: .high) }
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        audio.state.paused = false
        lastTime = 0
        accumulator = 0
        yoke.recenter()
        speech.say("Resumed. Hold the phone level for a moment.", priority: .high)
        // In the tutorial, the instructor repeats what to do.
        if let step = tutorial?.step, !Tutorial.reminder(step).isEmpty { speech.say(Tutorial.reminder(step)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let v = self?.view else { return }
            UIAccessibility.post(notification: .screenChanged, argument: v)
        }
    }

    func restart() {
        session = FlightSession(start: request.start, goal: request.goal, assist: assist)
        tutorial = request.isTutorial ? Tutorial() : nil
        recentActions = []
        finished = nil
        isPaused = false
        audio.state.paused = false
        audio.state.crashSeconds = 0
        lastTime = 0
        accumulator = 0
        yoke.recenter()
        if !request.briefing.isEmpty { speech.say(request.briefing, priority: .high) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let v = self?.view else { return }
            UIAccessibility.post(notification: .screenChanged, argument: v)
        }
    }

    /// Leaving mid-flight still counts in the logbook if you flew.
    func quit() {
        if finished == nil, session.hasFlown, session.time > 20 {
            let s = FlightSummary(completed: false, crash: nil, landing: nil, touchdownFPM: nil, centrelineOffset: nil,
                                  landedAt: nil, flightTime: session.time, distance: session.distanceFlown,
                                  message: "Flight ended.")
            settings.record(s, lesson: nil)
        }
        stop()
    }

    // MARK: Frame

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        for g in reader.update(time: now) { handle(gesture: g) }
        guard !isPaused, finished == nil else { return }
        if lastTime == 0 { lastTime = now; return }
        let dt = min(0.1, now - lastTime)
        lastTime = now
        accumulator += dt
        let input = currentInput()
        var events: [FlightEvent] = []
        while accumulator >= 1.0 / 60 {
            events += session.step(dt: 1.0 / 60, input: input)
            accumulator -= 1.0 / 60
        }
        for e in events { handle(event: e) }
        runTutorial(dt: dt)
        updateSound()
        reading = session.instruments
        if let summary = session.summary { finish(summary) }
    }

    /// The teacher: says the next thing, and after a crash puts the plane back so you can try again.
    private func runTutorial(dt: Double) {
        guard tutorial != nil else { return }
        if session.summary?.crash != nil {
            let retry = tutorial!.retry()
            session = FlightSession(start: retry.start, goal: .tutorial, assist: .easy)
            if tutorial!.retryEngineRunning { session.startEngineNow() }
            brake = false
            yoke.recenter()
            speech.say(retry.text, priority: .high)
            recentActions = []
            return
        }
        let lines = tutorial!.update(session: session, actions: recentActions, dt: dt)
        recentActions = []
        for line in lines { speech.say(line, priority: .normal) }
        if tutorial!.isComplete {
            settings.tutorialDone = true
            speech.say(Tutorial.completionMessage, priority: .normal)
            session.endFlight(message: Tutorial.completionMessage)
        }
    }

    private func currentInput() -> FlightInput {
        var pitch = 0.0, roll = 0.0
        if settings.controlMode == .tilt {
            let orientation = view?.window?.windowScene?.interfaceOrientation ?? .landscapeRight
            (pitch, roll) = yoke.read(orientation: orientation)
        } else if let s = stick {
            // Like a joystick: push up to lower the nose, pull down to raise it.
            let range: CGFloat = 70
            roll = Double(max(-1, min(1, (s.now.x - s.start.x) / range)))
            pitch = Double(max(-1, min(1, (s.now.y - s.start.y) / range)))
            if settings.invertPitch { pitch = -pitch }
        }
        return FlightInput(pitch: pitch, roll: roll, brake: brake)
    }

    private func updateSound() {
        let st = audio.state
        st.engineOn = session.engine == .running
        if case .starting = session.engine { st.cranking = true } else { st.cranking = false }
        st.rpm = Float(session.rpm)
        st.throttle = Float(session.throttle)
        st.airspeed = Float(session.airspeed)
        st.onGround = session.onGround
        st.centrelineActive = session.runwayOffset != nil
        st.centreline = Float(session.runwayOffset ?? 0)
        st.verticalSpeed = Float(session.verticalSpeed)
        st.bank = Float(session.bank)
        st.varioOn = settings.varioTone
        st.bankToneOn = settings.bankTone
        st.maxRPM = Float(session.spec.maxRPM)
        st.stallWarning = !session.onGround && session.airspeed < session.stallSpeedNow * 1.12 && session.altitude > 3
        if let ap = session.approach {
            st.approachLateral = Float(ap.lateral)
            st.approachAbove = Float(ap.aboveGlidePath)
        } else {
            st.approachLateral = .nan
        }
        let nav = session.navigation
        if session.engine == .running, !(session.onGround && !session.hasFlown) {
            st.beaconBearing = Float(nav.turn)
            st.beaconClose = nav.distance < 6_000
        } else {
            st.beaconBearing = .nan
        }
        audio.updateLayers()
    }

    private func handle(event e: FlightEvent) {
        switch e {
        case .touchdown:
            audio.state.thumpSeconds = 0.6
            heavy.impactOccurred()
        case .crashed:
            audio.state.crashSeconds = 2.5
            notify.notificationOccurred(.error)
        case .flaps:
            audio.state.flapSeconds = 0.7
        case .liftoff:
            light.impactOccurred()
        case .stallWarning:
            if session.time - lastStallSound > 4 { lastStallSound = session.time; light.impactOccurred() }
        default:
            break
        }
        guard let text = Phrases.event(e) else { return }
        let urgent: Bool
        switch e {
        case .stalled, .stallWarning, .crashed, .instruments, .navigation, .overspeed, .steepBank, .goalComplete: urgent = true
        default: urgent = false
        }
        speech.say(text, priority: urgent ? .high : .normal)
    }

    private func finish(_ summary: FlightSummary) {
        finished = summary
        audio.state.stallWarning = false
        settings.record(summary, lesson: summary.completed ? request.lesson?.id : nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.audio.state.paused = true
            self?.audio.updateLayers()
        }
    }

    // MARK: Touches

    func touches(_ phase: UITouch.Phase, _ touches: Set<UITouch>, in view: UIView) {
        guard !isPaused, finished == nil else { return }
        for t in touches {
            let key = ObjectIdentifier(t)
            let p = t.location(in: view)
            // Touch stick: a finger that lands on the left half is the stick, not a gesture.
            if settings.controlMode == .touchStick {
                if phase == .began, stick == nil, p.x < view.bounds.midX {
                    stick = (key, p, p)
                    continue
                }
                if let s = stick, s.id == key {
                    if phase == .moved { stick?.now = p }
                    if phase == .ended || phase == .cancelled { stick = nil }
                    continue
                }
            }
            switch phase {
            case .began:
                let id = nextTouchID
                nextTouchID += 1
                touchIDs[key] = id
                for g in reader.began(id: id, x: p.x, y: p.y, time: t.timestamp) { handle(gesture: g) }
            case .moved:
                if let id = touchIDs[key] { reader.moved(id: id, x: p.x, y: p.y, time: t.timestamp) }
            case .ended, .cancelled:
                if let id = touchIDs.removeValue(forKey: key) {
                    for g in reader.ended(id: id, x: p.x, y: p.y, time: t.timestamp) { handle(gesture: g) }
                }
            default:
                break
            }
        }
    }

    private func handle(gesture g: GestureReader.Gesture) {
        guard let command = GestureMap.command(for: g) else { return }
        switch command {
        case let .action(a): perform(a)
        case .pause: pause()
        case .recenter:
            yoke.recenter()
            speech.say("Level set. Hold still for a moment.", priority: .high)
        case let .brakes(on):
            guard session.onGround else { return }
            brake = on
            speech.say(on ? "Brakes." : "Brakes off.", priority: .normal)
        }
    }

    /// From gestures, buttons, VoiceOver's magic tap.
    func perform(_ action: FlightAction) {
        guard !isPaused, finished == nil else { return }
        if tutorial != nil { recentActions.append(action) }
        for e in session.perform(action) { handle(event: e) }
    }
}
