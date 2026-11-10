import Foundation
import UIKit
import SimCore

/// Turns simulation events and state into sound, speech and vibration.
final class FeedbackCoordinator {
    let audio = AudioSynth()
    let speech = Announcer()
    let haptics = Haptics()
    private let settings: AppSettings
    private var onRumbleStrip = false
    private var lastSpokenSpeedStep: Int?
    private var wasMoving = false
    /// Litres in the tank at the start, for the low-fuel warning; set before start().
    var startingFuel: Double?
    /// Town name for the Free Drive intro; set before start().
    var freeDriveTown = "Millbrook"
    /// The current truck's engine voice; set before start().
    var engineSound: EngineSound = .recorded
    /// The current truck's fuel use compared with a typical truck; set before start().
    var fuelEfficiency = 1.0
    /// The current truck's idle and top RPM (for its engine recording); set before start().
    var idleRPM: Double = 600
    var maxRPM: Double = 2_100
    /// Today's weather; set before start() and on restart.
    var weather: Weather = .clear {
        didSet { audio.setWeather(weather) }
    }
    /// The horn from the horn shop (its recording's name); set before start().
    var hornFile = "horn"
    /// The name the player gave this truck, if any; set before start().
    var truckNickname: String?
    /// Turbo Mode is on; set before start().
    var turbo = false
    /// Day or night; set before start().
    var timeOfDay: TimeOfDay = .day

    init(settings: AppSettings) {
        self.settings = settings
    }

    private var phrases: Phrases { Phrases(units: settings.units, electric: engineSound.electric) }

    func start() {
        audio.state.volume = Float(settings.volume)
        audio.state.laneToneEnabled = settings.laneGuidanceTone
        speech.output = settings.speechOutput
        haptics.enabled = settings.haptics
        speech.onSpeakingChanged = { speaking in
            DispatchQueue.main.async { MusicPlayer.shared.setDucked(speaking) }
        }
        // The App Store screenshot simulator on the build Mac has no working sound device,
        // and starting audio there aborts the app. Screenshots don't need sound.
        if !ScreenshotMode.isOn { audio.start(sound: engineSound, idleRPM: Float(idleRPM), maxRPM: Float(maxRPM), horn: hornFile) }
        haptics.start()
    }

    func stop() {
        speech.stop()
        if !ScreenshotMode.isOn { audio.stop() }
        haptics.stop()
    }

    func phrasesForUI() -> Phrases { phrases }

    /// Reads out the pay after a delivery (VoiceOver reads the results screen itself).
    func announcePayout(_ payout: Payout) {
        guard !UIAccessibility.isVoiceOverRunning else { return }
        speech.speak(phrases.payout(payout), priority: .normal)
    }

    func finishFreeDrive(_ summary: TripSummary, payout: Payout?) {
        audio.setMuted(true)
        haptics.update(engineRunning: false, rpmFraction: 0, load: 0, onRumbleStrip: false)
        if UIAccessibility.isVoiceOverRunning {
            speech.speak("Drive ended.", priority: .high)
        } else {
            speech.speak("Drive ended. " + phrases.tripResults(summary.stats) + " " + (payout.map(phrases.payout) ?? ""),
                         priority: .high)
        }
    }

    func setPaused(_ paused: Bool) {
        audio.setMuted(paused)
        if paused { haptics.update(engineRunning: false, rpmFraction: 0, load: 0, onRumbleStrip: false) }
        // With VoiceOver on, VoiceOver reads the pause menu itself; don't talk over it.
        if !UIAccessibility.isVoiceOverRunning || !paused {
            speech.speak(paused ? "Paused." : "Resumed.", priority: .high)
        }
    }

    func reset() {
        audio.setMuted(false)
        onRumbleStrip = false
        lastSpokenSpeedStep = nil
        audio.setRumble(nil)
    }

    func announceIntro(mode: TouchSteeringMode, drive: DriveMode) {
        let controls: String
        switch mode {
        case .tilt:
            controls = "Hold your phone sideways, at any angle. Lower the right end to steer right, the left end to steer left. Hold the right half of the screen to accelerate, the left half to brake."
        case .joystick:
            controls = "Put one finger anywhere. Slide up to accelerate, down to brake, left or right to steer. Lift your finger to coast."
        }
        var trip: String
        switch drive {
        case .tutorial:
            trip = "Tutorial."
        case .practice:
            trip = "Practice Drive: \(settings.units.distance(Road.practiceLoop.totalLength)) to the drop-off. Stop there to finish. Practice drives don't pay."
        case .freeDrive:
            trip = "Free Drive from \(freeDriveTown). Roam the map: at each junction you'll hear the choices; signal left or right to turn, or no signal to go straight. You earn \(Phrases.money(Int(Payout.freeDriveRatePerKm))) per kilometer. Pause and choose End Drive to get paid."
        case let .job(job):
            trip = phrases.jobIntro(job) + " Stop at the drop-off to deliver."
            if let fuel = startingFuel,
               fuel < CareerState.fuelNeeded(forDistance: job.distance, cargoKg: job.cargo.massKg) * fuelEfficiency {
                trip += engineSound.electric
                    ? " Warning: you may not have enough charge. Listen for truck stops and charge on the way."
                    : " Warning: you may not have enough fuel. Listen for truck stops and fill up on the way."
            }
        }
        if let name = truckNickname, drive != .tutorial { trip = "\(name) is ready to roll. " + trip }
        if let forecast = weather.announcement { trip += " " + forecast }
        if turbo { trip += " " + phrases.turboIntro }
        if drive != .tutorial && drive != .practice, let time = timeOfDay.announcement { trip += " " + time }
        speech.speak(
            "\(trip) Engine off. \(controls) Three-finger double tap starts the engine. Two-finger double tap reads the dashboard. Two-finger swipe down pauses.",
            priority: .high
        )
    }

    func handle(_ events: [SimEvent]) {
        for event in events { handle(event) }
    }

    private func handle(_ event: SimEvent) {
        switch event {
        case .engineStarting:
            audio.engineStarting()
            speech.speak(engineSound.electric ? "Powering up." : "Starting engine.", priority: .normal)
        case .engineStarted:
            speech.speak(engineSound.electric ? "Ready to drive." : "Engine running.", priority: .normal)
            haptics.tap(intensity: 0.6, sharpness: 0.3)
        case .engineStopped:
            audio.engineStopped()
            speech.speak(engineSound.electric ? "Power off." : "Engine off.", priority: .high)
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
        case let .deerAhead(distance):
            audio.playEffect("fx_deer", volume: 0.8)
            speech.speak(phrases.deerAhead(distance), priority: .high)
            haptics.tap(intensity: 1, sharpness: 0.6)
        case let .deerGone(scared):
            if scared { audio.playEffect("fx_deer", volume: 0.5) }
            speech.speak(phrases.deerGone(scared: scared), priority: .normal)
        case let .enteredConstruction(limit):
            speech.speak(phrases.enteredConstruction(speedLimit: limit), priority: .high)
        case let .leftConstruction(limit):
            speech.speak(phrases.leftConstruction(speedLimit: limit), priority: .normal)
        case let .tollBoothAhead(distance):
            speech.speak(phrases.tollBoothAhead(distance), priority: .normal)
        case let .tollPaid(cost):
            audio.playEffect("fx_toll", volume: 0.8)
            speech.speak(phrases.tollPaid(cost), priority: .normal)
        case let .ranToll(fine):
            audio.airBrake()
            speech.speak(phrases.ranToll(fine), priority: .high)
            haptics.tap(intensity: 1, sharpness: 0.8)
        case let .weighStationAhead(distance):
            speech.speak(phrases.weighStationAhead(distance), priority: .high)
        case let .weighedIn(cargoKg, fine):
            haptics.tap(intensity: 0.6, sharpness: 0.4)
            speech.speak(phrases.weighedIn(cargoKg: cargoKg, fine: fine), priority: .high)
        case let .skippedWeighStation(fine, tooFast):
            audio.airBrake()
            speech.speak(phrases.skippedWeighStation(fine: fine, tooFast: tooFast), priority: .high)
            haptics.tap(intensity: 1, sharpness: 0.8)
        case let .turboSpeed(speed):
            speech.speak(phrases.turboSpeed(speed), priority: .high)
            haptics.tap(intensity: 0.8, sharpness: 1)
        case .thunder:
            audio.thunder()
            haptics.tap(intensity: 0.5, sharpness: 0.1)
        case let .rumbleStrip(side):
            onRumbleStrip = side != nil
            audio.setRumble(side)
        case let .curveAhead(curve):
            speech.speak(phrases.curve(curve), priority: .normal)
        case let .navInstruction(instruction):
            // Queued, so it follows the road-ahead summary instead of cutting it off.
            speech.speak(phrases.navInstruction(instruction), priority: .normal)
        case let .junctionAhead(choices, distance):
            speech.speak(phrases.junctionAhead(choices, distance: distance), priority: .normal)
        case let .tookRoad(roadName, toward, length, _):
            speech.speak(phrases.tookRoad(roadName: roadName, toward: toward, length: length), priority: .normal)
        case let .signalMismatch(instruction, signal):
            speech.speak(phrases.signalMismatch(instruction, signal: signal), priority: .high)
            haptics.tap(intensity: 0.9, sharpness: 0.7)
        case let .rerouted(remaining):
            speech.speak(phrases.rerouted(remaining), priority: .high)
        case .missedDropOff:
            speech.speak(phrases.missedDropOff, priority: .high)
        case let .enteredTown(name, limit):
            speech.speak(phrases.enteredTown(name, speedLimit: limit), priority: .normal)
        case let .leftTown(name, limit):
            speech.speak(phrases.leftTown(name, speedLimit: limit), priority: .normal)
        case let .changedLane(toLeft, oncoming):
            speech.speak(phrases.changedLane(toLeft: toLeft, oncoming: oncoming), priority: .normal)
        case .wrongSideOfRoad:
            speech.speak(phrases.wrongSideOfRoad, priority: .high)
            haptics.tap(intensity: 1, sharpness: 1)
        case let .vehicleAhead(distance, speed, kind):
            speech.speak(phrases.vehicleAhead(distance: distance, speed: speed, kind: kind), priority: .high)
        case .tooClose:
            speech.speak(phrases.tooClose, priority: .high)
            haptics.tap(intensity: 0.9, sharpness: 0.9)
        case .oncomingHorn:
            audio.oncomingCarHorn()
        case .passedPolice:
            audio.policeRadio()
        case let .policeChase(speed, limit):
            speech.speak(phrases.policeChase(speed: speed, limit: limit), priority: .high)
            haptics.tap(intensity: 1, sharpness: 0.8)
        case let .speedingTicket(speed, limit, fine):
            speech.speak(phrases.speedingTicket(speed: speed, limit: limit, fine: fine), priority: .high)
        case let .fledPolice(fine):
            speech.speak(phrases.fledPolice(fine), priority: .high)
        case let .onShoulder(side):
            speech.speak(phrases.onShoulder(side), priority: .high)
            haptics.tap(intensity: 0.8, sharpness: 0.3)
        case .tooFastForCurve:
            speech.speak("Too fast for this curve!", priority: .high)
            haptics.tap(intensity: 1, sharpness: 0.9)
        case let .crashed(reason):
            audio.crash()
            haptics.crash()
            speech.speak(phrases.crash(reason), priority: .high)
            lastSpokenSpeedStep = 0
        case .outOfFuel:
            speech.speak(engineSound.electric ? "Battery empty." : "Out of fuel.", priority: .high)
        case let .fuelLow(fraction, nextStop, urgent):
            speech.speak(phrases.fuelLow(fraction: fraction, nextStop: nextStop, urgent: urgent), priority: urgent ? .high : .normal)
            if urgent { haptics.tap(intensity: 0.9, sharpness: 0.6) }
        case let .truckStopAhead(distance):
            speech.speak(phrases.truckStopAhead(distance), priority: .normal)
        case .pulledIntoTruckStop:
            speech.speak(phrases.pulledIntoTruckStop, priority: .high)
        case let .missedTruckStop(tooFast):
            speech.speak(phrases.missedTruckStop(tooFast: tooFast), priority: .high)
        case .refuelStarted:
            speech.speak(phrases.refuelStarted, priority: .high)
        case let .refueled(liters, cost):
            speech.speak(phrases.refueled(liters: liters, cost: cost), priority: .high)
            haptics.tap(intensity: 0.5, sharpness: 0.5)
        case .leftTruckStop:
            speech.speak(phrases.leftTruckStop, priority: .normal)
        case let .towed(cost, fuelCost):
            speech.speak(phrases.towed(cost: cost, fuelCost: fuelCost), priority: .high)
        case let .dashboard(reading):
            speech.speak(phrases.dashboard(reading), priority: .high)
        case let .roadAhead(curve, remaining, timeLeft, truckStop):
            speech.speak(phrases.roadAhead(curve, remaining: remaining, timeLeft: timeLeft, truckStop: truckStop),
                         priority: .high)
        case let .timeLeft(seconds):
            speech.speak(phrases.timeLeft(seconds), priority: .normal)
        case .lateForDelivery:
            speech.speak(phrases.lateForDelivery, priority: .high)
        case let .tripProgress(remaining):
            speech.speak(phrases.tripProgress(remaining: remaining), priority: .normal)
        case let .destinationAhead(distance):
            speech.speak(phrases.destinationAhead(distance), priority: .high)
            haptics.tap(intensity: 0.7, sharpness: 0.5)
        case .atDestination:
            speech.speak(phrases.atDestination, priority: .high)
            haptics.tap(intensity: 1, sharpness: 0.5)
        case let .stoppedShort(remaining):
            speech.speak(phrases.stoppedShort(remaining), priority: .normal)
        case let .arrived(summary):
            audio.setMuted(true)
            haptics.update(engineRunning: false, rpmFraction: 0, load: 0, onRumbleStrip: false)
            haptics.tap(intensity: 1, sharpness: 0.2)
            // VoiceOver reads the results screen itself; without it, the game reads them out.
            if UIAccessibility.isVoiceOverRunning {
                speech.speak("Delivered!", priority: .high)
            } else {
                speech.speak(phrases.arrived(summary), priority: .high)
            }
        }
    }

    /// Town sounds near towns, crickets at night, birds at dawn, machines in work zones.
    private func ambience(_ session: DrivingSession) -> [String: Float] {
        var out: [String: Float] = [:]
        let zone = session.road.speedZone(at: session.truck.position)
        if session.inConstructionZone {
            out["amb_construction"] = 0.55
        } else if let zone {
            let id = zone.name.lowercased().replacingOccurrences(of: " ", with: "_")
            out["amb_town_" + id] = 0.5
        }
        switch session.timeOfDay {
        case .night: out["amb_night"] = zone == nil ? 0.35 : 0.15
        case .dawn: out["amb_dawn"] = zone == nil ? 0.35 : 0.15
        case .day, .dusk: break
        }
        // Rain drowns out the countryside.
        if session.weather != .clear { out["amb_night"] = nil; out["amb_dawn"] = nil }
        return out
    }

    /// Called every frame with the latest state.
    func update(session: DrivingSession) {
        let truck = session.truck
        audio.update(truck: truck, spec: session.spec)
        audio.setLaneGuidance(offset: session.laneGuidanceOffset)
        audio.updateTraffic(session.trafficSounds)
        audio.setAmbience(ambience(session))
        audio.state.pumping = session.isRefueling
        audio.state.siren = session.sirenOn
        // Drop-off beacon: beeps speed up over the last 150 m, a steady tone right at the drop-off.
        if session.summary == nil, let r = session.remaining, r < 150, r > -60 {
            audio.state.beaconDistance = Float(r)
        } else {
            audio.state.beaconDistance = -1_000
        }
        haptics.update(
            engineRunning: truck.engine == .running,
            rpmFraction: truck.rpm / session.spec.maxRPM,
            load: truck.engineLoad,
            onRumbleStrip: onRumbleStrip && truck.speed > 1
        )
        announceSpeedIfNeeded(truck.speed)
        // Air brakes hiss when the truck comes to a stop.
        if truck.speed > 3 { wasMoving = true }
        if wasMoving && truck.speed < 0.2 {
            wasMoving = false
            audio.airBrake()
        }
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
