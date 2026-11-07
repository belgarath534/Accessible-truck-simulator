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

    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var accumulator: Double = 0
    private let fixedStep = 1.0 / 60

    weak var view: DrivingTouchView?

    init(settings: AppSettings, career: CareerStore, drive: DriveMode) {
        self.settings = settings
        self.career = career
        self.drive = drive
        session = DrivingController.makeSession(drive, settings)
        touch = TouchInterpreter(mode: settings.steeringMode, areaWidth: 800)
        feedback = FeedbackCoordinator(settings: settings)
        super.init()
        hardware.onAction = { [weak self] action in self?.perform(action) }
    }

    private static func makeSession(_ drive: DriveMode, _ settings: AppSettings) -> DrivingSession {
        DrivingSession(goal: drive.goal, cargoMassKg: drive.job?.cargo.massKg ?? 0,
                       timeLimit: drive.job?.timeLimit, assist: settings.assist)
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
        feedback.start()
        hardware.start()

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTime = 0
        UIApplication.shared.isIdleTimerDisabled = true
        feedback.announceIntro(mode: settings.steeringMode, drive: drive)
        MusicPlayer.shared.stop()
        if settings.radioOnStart { MusicPlayer.shared.startRadio() }
    }

    func stop() {
        MusicPlayer.shared.stop()
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
        MusicPlayer.shared.setPaused(true)
        finished = summary
    }

    /// Leaving mid-drive: Free Drive still pays for the distance; an unfinished job pays nothing.
    func quit() {
        if drive == .freeDrive && finished == nil && session.stats.distance > 0 {
            settle(TripSummary(goalName: goal.name, stats: session.stats, stopError: 0))
        }
        stop()
    }

    private func settle(_ summary: TripSummary) {
        let result: Payout?
        switch drive {
        case .practice: result = nil
        case .freeDrive: result = Payout.freeDrive(summary.stats)
        case let .job(job): result = Payout.delivery(job, summary: summary)
        }
        payout = result
        if let result { career.record(result, distance: summary.stats.distance, completing: drive.job) }
    }

    func restart() {
        session = DrivingController.makeSession(drive, settings)
        payout = nil
        feedback.reset()
        touch.reset()
        tilt.recenter()
        if finished != nil {
            finished = nil
            MusicPlayer.shared.setPaused(false)
            lastTime = 0
            accumulator = 0
            feedback.announceIntro(mode: settings.steeringMode, drive: drive)
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

        accumulator += dt
        var events: [SimEvent] = []
        while accumulator >= fixedStep {
            events += session.step(dt: fixedStep, input: input)
            accumulator -= fixedStep
        }
        feedback.handle(events)
        feedback.update(session: session)
        view?.setNeedsDisplay()
        if let summary = session.summary {
            settle(summary)
            if let payout { feedback.announcePayout(payout) }
            touch.reset()
            MusicPlayer.shared.setPaused(true)
            finished = summary
        }
    }
}
