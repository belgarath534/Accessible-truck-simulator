import QuartzCore
import SimCore
import SwiftUI
import UIKit

/// Runs one driving session: the game loop, input from every source, and feedback.
final class DrivingController: NSObject, ObservableObject {
    @Published private(set) var isPaused = false
    /// Set when the trip is finished; the results screen shows it.
    @Published private(set) var finished: TripSummary?
    /// Trip status for the pause menu, refreshed when pausing.
    @Published private(set) var tripStatus = ""
    /// What the finished drive earned (nil for practice).
    @Published private(set) var payout: Payout?

    let settings: AppSettings
    let career: CareerStore
    let drive: DriveMode
    var goal: TripGoal { drive.goal }
    private(set) var session: DrivingSession
    let touch: TouchInterpreter
    private let tilt = TiltSteering()
    private let hardware = HardwareInput()
    private let feedback: FeedbackCoordinator
    /// The guided first drive's teacher (nil for other drives).
    private var tutorial: Tutorial?
    /// Gestures since the last frame, for the tutorial.
    private var recentActions: [DrivingAction] = []
    /// When the tutorial finished, to show the results after its last words.
    private var tutorialFinishedAt: CFTimeInterval?

    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var accumulator: Double = 0
    private let fixedStep = 1.0 / 60

    weak var view: DrivingTouchView?

    init(settings: AppSettings, career: CareerStore, drive: DriveMode) {
        self.settings = settings
        self.career = career
        self.drive = drive
        session = DrivingController.makeSession(drive, settings, career.truck, fuel: career.fuelLiters,
                                                town: career.state.currentTown)
        touch = TouchInterpreter(mode: settings.steeringMode, areaWidth: 800)
        feedback = FeedbackCoordinator(settings: settings)
        super.init()
        tutorial = makeTutorial()
        hardware.onAction = { [weak self] action in self?.perform(action) }
    }

    private func makeTutorial() -> Tutorial? {
        drive == .tutorial ? Tutorial(mode: settings.steeringMode, units: settings.units) : nil
    }

    private static func makeSession(_ drive: DriveMode, _ settings: AppSettings, _ truck: TruckSpec,
                                    fuel: Double, town: String) -> DrivingSession {
        // Jobs and Free Drive happen on the map; Practice Drive stays on the practice loop.
        let navigator: Navigator?
        switch drive {
        case .practice, .tutorial: navigator = nil
        case .freeDrive: navigator = Navigator(map: .standard, origin: town, destination: nil)
        case let .job(job):
            navigator = job.destination.flatMap { Navigator(map: .standard, origin: job.origin ?? town, destination: $0) }
        }
        let session = DrivingSession(spec: truck, goal: drive.goal, cargoMassKg: drive.job?.cargo.massKg ?? 0,
                                     timeLimit: drive.job?.timeLimit,
                                     startingFuel: drive == .tutorial ? nil : fuel, // the tutorial is on the house
                                     navigator: navigator,
                                     assist: settings.assist)
        // Traffic on the map; the practice loop stays quiet for learning.
        session.trafficEnabled = settings.traffic && navigator != nil
        return session
    }

    /// Leaving or restarting a drive that didn't finish: keep the fuel level and charge any fuel or tow costs.
    private func closeOutUnfinished() {
        guard drive != .tutorial else { return }
        career.saveFuel(session.truck.fuelLiters)
        let costs = Payout.expenses(session.stats)
        let trip = TripResult(job: nil, summary: nil, stats: session.stats)
        if !costs.isEmpty { career.charge(Payout(lines: costs), trip: trip) }
        // Anything earned is announced by the next drive, or by the menu after quitting.
    }

    /// Free Drive's pay so far (nil for other drives).
    var freeDriveEarnings: Int? {
        drive == .freeDrive ? Payout.freeDrive(session.stats).total : nil
    }

    // MARK: Lifecycle

    func start() {
        guard displayLink == nil else { return }
        tilt.rangeDegrees = settings.tiltRange
        tilt.invert = settings.invertTilt
        if settings.steeringMode == .tilt { tilt.start() }
        feedback.engineSound = session.spec.sound
        feedback.freeDriveTown = career.state.currentTownName
        feedback.startingFuel = session.truck.fuelLiters
        feedback.start()
        hardware.start()

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTime = 0
        UIApplication.shared.isIdleTimerDisabled = true
        // The tutorial speaks its own welcome.
        if tutorial == nil { feedback.announceIntro(mode: settings.steeringMode, drive: drive) }
        MusicPlayer.shared.stop()
        if settings.radioOnStart && !ScreenshotMode.isOn { MusicPlayer.shared.startRadio() }
    }

    func stop() {
        // Runs twice when leaving (quit button, then the screen closing), sometimes after the menu
        // music has already started again: only ever turn off the radio, never the menu music.
        guard displayLink != nil else { return }
        if MusicPlayer.shared.mode == .radio { MusicPlayer.shared.stop() }
        displayLink?.invalidate()
        displayLink = nil
        feedback.stop()
        tilt.stop()
        hardware.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func pause() {
        guard !isPaused, finished == nil else { return }
        tripStatus = feedback.phrasesForUI().tripStatus(goal: goal, stats: session.stats, remaining: session.remaining,
                                                        timeLeft: session.timeLeft, earnedSoFar: freeDriveEarnings)
        isPaused = true
        MusicPlayer.shared.setPaused(true)
        touch.reset()
        feedback.setPaused(true)
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        lastTime = 0
        accumulator = 0
        tilt.recenter()
        feedback.setPaused(false)
        MusicPlayer.shared.setPaused(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let view = self?.view else { return }
            UIAccessibility.post(notification: .screenChanged, argument: view)
        }
    }

    /// Ends a Free Drive and pays for the distance driven.
    func endFreeDrive() {
        guard drive == .freeDrive, finished == nil else { return }
        let summary = TripSummary(goalName: goal.name, stats: session.stats, stopError: 0)
        settle(summary)
        isPaused = false
        feedback.setPaused(false)
        feedback.finishFreeDrive(summary, payout: payout)
        announceAchievements()
        MusicPlayer.shared.setPaused(true)
        finished = summary
    }

    /// Leaving mid-drive: Free Drive still pays for the distance; an unfinished job pays nothing.
    func quit() {
        if finished == nil {
            if drive == .freeDrive && session.stats.distance > 0 {
                settle(TripSummary(goalName: goal.name, stats: session.stats, stopError: 0))
            } else {
                closeOutUnfinished()
            }
        }
        stop()
    }

    private func settle(_ summary: TripSummary) {
        let result: Payout?
        if drive == .tutorial { payout = nil; return }
        career.saveFuel(session.truck.fuelLiters)
        switch drive {
        case .tutorial: result = nil
        case .practice: result = Payout.practice(summary.stats)
        case .freeDrive:
            result = Payout.freeDrive(summary.stats)
            if let town = session.navigator?.lastTown { career.move(to: town) }
        case let .job(job): result = Payout.delivery(job, summary: summary)
        }
        payout = result
        let trip = TripResult(job: drive.job, summary: drive.job == nil ? nil : summary, stats: summary.stats)
        if let result {
            career.record(result, distance: summary.stats.distance, completing: drive.job, trip: trip)
        }
    }

    /// Speaks achievements just earned, after whatever is being said now.
    private func announceAchievements() {
        for achievement in career.takeUnlocked() {
            feedback.speech.speak(achievement.announcement, priority: .normal)
        }
    }

    func restart() {
        if finished == nil { closeOutUnfinished() }
        session = DrivingController.makeSession(drive, settings, career.truck, fuel: career.fuelLiters,
                                                town: career.state.currentTown)
        payout = nil
        tutorial = makeTutorial()
        tutorialFinishedAt = nil
        recentActions = []
        feedback.reset()
        announceAchievements()
        touch.reset()
        tilt.recenter()
        if finished != nil {
            finished = nil
            MusicPlayer.shared.setPaused(false)
            lastTime = 0
            accumulator = 0
            if tutorial == nil { feedback.announceIntro(mode: settings.steeringMode, drive: drive) }
            focusDrivingView()
        } else {
            resume()
        }
    }

    private func focusDrivingView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let view = self?.view else { return }
            UIAccessibility.post(notification: .screenChanged, argument: view)
        }
    }

    // MARK: Input

    func touchesChanged(_ phase: UITouch.Phase, _ touches: Set<UITouch>, in view: UIView) {
        guard !isPaused, finished == nil else { return }
        let now = CACurrentMediaTime()
        touch.areaWidth = Double(view.bounds.width)
        for t in touches {
            let id = ObjectIdentifier(t).hashValue
            let p = t.location(in: view)
            let point = TouchPoint(x: Double(p.x), y: Double(p.y))
            switch phase {
            case .began: touch.began(id: id, at: point, time: now)
            case .moved: touch.moved(id: id, to: point, time: now)
            default: touch.ended(id: id, at: point, time: now)
            }
        }
    }

    func perform(_ action: DrivingAction) {
        if action == .pause {
            guard finished == nil else { return }
            isPaused ? resume() : pause()
            return
        }
        guard !isPaused, finished == nil else { return }
        if tutorial != nil { recentActions.append(action) }
        switch action {
        case .toggleRadio, .nextSong, .previousSong:
            handleRadio(action)
            return
        default:
            break
        }
        feedback.handle(session.perform(action))
    }

    private func handleRadio(_ action: DrivingAction) {
        let music = MusicPlayer.shared
        guard music.hasRadio else {
            feedback.speech.speak("No radio in this truck yet.", priority: .high)
            return
        }
        switch action {
        case .toggleRadio:
            if music.mode == .radio {
                music.stop()
                feedback.speech.speak("Radio off.", priority: .high)
                return
            }
            music.startRadio()
        case .nextSong:
            music.nextSong()
        case .previousSong:
            music.previousSong()
        default:
            return
        }
        feedback.speech.speak("Radio: \(music.currentSongName ?? "on").", priority: .high)
    }

    // MARK: Game loop

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = lastTime == 0 ? fixedStep : min(now - lastTime, 0.1)
        lastTime = now

        for gesture in touch.update(time: now) {
            if let action = GestureMap.action(for: gesture) { perform(action) }
        }
        guard !isPaused, finished == nil else { return }

        var input = touch.input(at: now)
        if settings.steeringMode == .tilt {
            let orientation = view?.window?.windowScene?.interfaceOrientation ?? .landscapeRight
            input.steer = tilt.steer(orientation: orientation)
        }
        input = input.merged(with: hardware.poll())
        if ScreenshotMode.isOn {
            if session.truck.engine == .off { feedback.handle(session.perform(.toggleEngine)) }
            input = ScreenshotMode.autopilot(session)
        }

        accumulator += dt
        var events: [SimEvent] = []
        while accumulator >= fixedStep {
            events += session.step(dt: fixedStep, input: input)
            accumulator -= fixedStep
        }
        feedback.handle(events)
        feedback.update(session: session)
        view?.setNeedsDisplay()
        updateTutorial(dt: dt, now: now)
        if let summary = session.summary {
            settle(summary)
            if let payout { feedback.announcePayout(payout) }
            announceAchievements()
            touch.reset()
            MusicPlayer.shared.setPaused(true)
            finished = summary
        }
    }

    // MARK: Tutorial

    private func updateTutorial(dt: Double, now: CFTimeInterval) {
        guard let tutorial else { return }
        if let line = tutorial.update(dt: dt, session: session, actions: recentActions) {
            feedback.speech.speak(line, priority: .high)
        }
        recentActions = []
        guard tutorial.isComplete else { return }
        if tutorialFinishedAt == nil {
            tutorialFinishedAt = now
            settings.tutorialDone = true
            career.unlock(.tutorial)
            announceAchievements()
        }
        // Let the closing words play before the results screen takes VoiceOver's focus.
        if let at = tutorialFinishedAt, now - at > 9 {
            touch.reset()
            MusicPlayer.shared.setPaused(true)
            finished = TripSummary(goalName: "Tutorial", stats: session.stats, stopError: 0)
        }
    }
}
