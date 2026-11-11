import BeatCore
import QuartzCore
import SwiftUI

/// Runs one song: starts the audio, judges your moves against the song clock, and gives feedback.
@MainActor
final class PlayController: ObservableObject {
    enum Phase: Equatable { case loading, playing, finished, stopped }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var lastJudgement: Judgement?
    @Published private(set) var combo = 0
    @Published private(set) var score = 0
    @Published private(set) var newBest = false

    let chart: Chart
    private(set) var judge: Judge
    private let settings: GameSettings
    private let audio = AudioOut.shared
    private let haptics = Haptics()
    private var startUptime: TimeInterval = 0
    private var link: CADisplayLink?
    private var fx: [Judgement: AVAudioPCMBufferBox] = [:]
    private var lastSpokenCombo = 0

    /// Misses are only called this long after the hit window, so a slow tap still counts.
    private static let missGrace = 0.25

    init(song: Song, difficulty: Difficulty, settings: GameSettings) {
        chart = Chart(song: song, difficulty: difficulty)
        judge = Judge(chart: chart)
        self.settings = settings
    }

    func start() {
        guard phase == .loading else { return }
        haptics.prepare()
        for j in [Judgement.perfect, .good, .miss] {
            fx[j] = AVAudioPCMBufferBox(audio.pcm(mono: audio.synth.hitSound(j)))
        }
        Speaker.say("\(chart.song.title), \(chart.difficulty.name). Listen after each bell, then repeat. Here we go.")
        let chart = self.chart, synth = audio.synth
        Task {
            let rendered = await Task.detached(priority: .userInitiated) { synth.render(chart) }.value
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard phase == .loading, let buffer = audio.pcm(rendered) else { return }
            startUptime = audio.play(buffer)
            phase = .playing
            let proxy = LinkProxy { [weak self] in self?.tick() }
            let link = CADisplayLink(target: proxy, selector: #selector(LinkProxy.fire))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    private func songTime(_ uptime: TimeInterval) -> Double { uptime - startUptime - settings.calibration }

    private func tick() {
        guard phase == .playing else { return }
        let t = songTime(CACurrentMediaTime())
        for _ in judge.update(time: t - Self.missGrace) { feedback(.miss) }
        if t > chart.song.duration + 0.4 { finish() }
    }

    func move(_ move: Move, at uptime: TimeInterval) {
        guard phase == .playing else { return }
        if let result = judge.input(move, at: songTime(uptime)) { feedback(result.judgement) }
    }

    private func feedback(_ j: Judgement) {
        lastJudgement = j
        combo = judge.combo
        score = judge.score
        if settings.haptics { haptics.play(j) }
        if settings.hitSounds { audio.playFX(fx[j == .wrongMove ? .miss : j]?.buffer) }
        // A quick shout-out every 10 in a row.
        if combo >= 10, combo % 10 == 0, combo != lastSpokenCombo {
            lastSpokenCombo = combo
            Speaker.say("\(combo) combo")
        }
    }

    private func finish() {
        link?.invalidate()
        link = nil
        phase = .finished
        newBest = settings.recordScore(judge.score, song: chart.song, difficulty: chart.difficulty)
        Speaker.say("Song complete. " + judge.spokenResults + (newBest ? " New best score!" : ""))
    }

    /// Two-finger tap: stop the song.
    func stop() {
        guard phase == .playing || phase == .loading else { return }
        link?.invalidate()
        link = nil
        audio.stopSong()
        phase = .stopped
        Speaker.say("Song stopped.")
    }

    func leave() {
        link?.invalidate()
        link = nil
        audio.stopSong()
        if phase != .finished { phase = .stopped }
    }
}

/// CADisplayLink needs an Objective-C target.
final class LinkProxy: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

import AVFoundation

/// Holds an audio buffer in a dictionary.
struct AVAudioPCMBufferBox {
    let buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer?) { self.buffer = buffer }
}
