import Foundation
import SimCore

/// Turns simulation events and state into sound, speech and vibration.
final class FeedbackCoordinator {
    let audio = AudioSynth()
    let speech = Announcer()
    let haptics = Haptics()
    private let settings: AppSettings
    private var onRumbleStrip = false
    private var lastSpokenSpeedStep: Int?

    init(settings: AppSettings) {
        self.settings = settings
    }

    private var phrases: Phrases { Phrases(units: settings.units) }

    func start() {
        audio.state.volume = Float(settings.volume)
        audio.state.laneToneEnabled = settings.laneGuidanceTone
        speech.output = settings.speechOutput
        haptics.enabled = settings.haptics
        audio.start()
        haptics.start()
    }

    func stop() {
        speech.stop()
        audio.stop()
        haptics.stop()
    }

    func setPaused(_ paused: Bool) {
        audio.state.muted = paused
        if paused { haptics.update(engineRunning: false, rpmFraction: 0, load: 0, onRumbleStrip: false) }
        speech.speak(paused ? "Paused." : "Resumed.", priority: .high)
    }

    func reset() {
        onRumbleStrip = false
        lastSpokenSpeedStep = nil
        audio.setRumble(nil)
    }

    func announceIntro(mode: TouchSteeringMode) {
        let controls: String
        switch mode {
        case .tilt:
            controls = "Hold your phone sideways like a steering wheel and tilt to steer. Hold the right half of the screen to accelerate, the left half to brake."
        case .joystick:
            controls = "Put one finger anywhere. Slide up to accelerate, down to brake, left or right to steer. Lift your finger to coast."
        }
        speech.speak(
            "Practice loop. Engine off. \(controls) Three-finger double tap starts the engine. Two-finger double tap reads the dashboard. Two-finger swipe down pauses.",
            priority: .high
        )
    }

    func handle(_ events: [SimEvent]) {
        for event in events { handle(event) }
    }

    private func handle(_ event: SimEvent) {
        switch event {
        case .engineStarting:
            speech.speak("Starting engine.", priority: .normal)
        case .engineStarted:
            speech.speak("Engine running.", priority: .normal)
            haptics.tap(intensity: 0.6, sharpness: 0.3)
        case .engineStopped:
            speech.speak("Engine off.", priority: .high)
        case .engineNotRunning:
            speech.speak("The engine is off. Three-finger double tap to start it.", priority: .high)
        case let .gearChanged(gear, _):
            audio.gearShift()
            if settings.announceGears { speech.speak("Gear \(gear)", priority: .low) }
        case let .signalChanged(state):
            speech.speak(phrases.signal(state), priority: .high)
            haptics.tap(intensity: 0.4, sharpness: 0.8)
        case .horn:
            audio.honk()
        case let .rumbleStrip(side):
            onRumbleStrip = side != nil
            audio.setRumble(side)
        case let .curveAhead(curve):
            speech.speak(phrases.curve(curve), priority: .normal)
        case .tooFastForCurve:
            speech.speak("Too fast for this curve!", priority: .high)
            haptics.tap(intensity: 1, sharpness: 0.9)
        case let .crashed(reason):
            audio.crash()
            haptics.crash()
            speech.speak(phrases.crash(reason), priority: .high)
            lastSpokenSpeedStep = 0
        case .outOfFuel:
            speech.speak("Out of fuel.", priority: .high)
        case .lowFuel:
            speech.speak("Fuel low.", priority: .normal)
        case let .dashboard(reading):
            speech.speak(phrases.dashboard(reading), priority: .high)
        case let .roadAhead(curve):
            speech.speak(phrases.roadAhead(curve), priority: .high)
        }
    }

    /// Called every frame with the latest state.
    func update(session: DrivingSession) {
        let truck = session.truck
        audio.update(truck: truck, spec: session.spec)
        haptics.update(
            engineRunning: truck.engine == .running,
            rpmFraction: truck.rpm / session.spec.maxRPM,
            load: truck.engineLoad,
            onRumbleStrip: onRumbleStrip && truck.speed > 1
        )
        announceSpeedIfNeeded(truck.speed)
    }

    /// Calls out the speed every 10 km/h (or mph), with a little hysteresis so it doesn't chatter.
    private func announceSpeedIfNeeded(_ speed: Double) {
        guard settings.announceSpeed else { return }
        let display = Double(settings.units.speed(speed))
        let step = Int((display / 10).rounded(.down))
        guard let last = lastSpokenSpeedStep else { lastSpokenSpeedStep = step; return }
        let crossedUp = step > last
        let crossedDown = step < last && display < Double(last * 10) - 3
        if (crossedUp || crossedDown) && step > 0 {
            lastSpokenSpeedStep = step
            speech.speak("\(step * 10)", priority: .low)
        } else if step == 0 && last != 0 && display < 2 {
            lastSpokenSpeedStep = 0
        }
    }
}
