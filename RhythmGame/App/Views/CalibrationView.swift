import BeatCore
import QuartzCore
import SwiftUI

/// Tap along to 16 clicks; the game measures how late your taps land and uses that from then on.
struct CalibrationView: View {
    @EnvironmentObject private var settings: GameSettings
    @Environment(\.dismiss) private var dismiss
    @State private var running = false
    @State private var startUptime: TimeInterval = 0
    @State private var taps: [TimeInterval] = []
    @State private var message = "Tap Start, then tap anywhere on the screen with each click. Four clicks to get the feel, then twelve to measure."

    static let bpm = 100.0
    static let clicks = 16
    static let warmUp = 4

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if running {
                Text("Tap with each click").font(.largeTitle.bold()).accessibilityHidden(true)
                TouchPad(label: "Calibration pad",
                         hint: "Tap with each click. Two-finger tap to cancel.",
                         onMove: { move, time in if move == .tap { taps.append(time) } },
                         onStop: { cancel() })
                    .ignoresSafeArea()
            } else {
                List {
                    Section {
                        Text(message)
                        Text("Current offset: \(Int((settings.calibration * 1000).rounded())) milliseconds.")
                        Button("Start") { start() }
                    } footer: {
                        Text("Calibrate again whenever you switch between the phone speaker, wired headphones and Bluetooth.")
                    }
                }
            }
        }
        .navigationTitle("Calibrate Timing")
    }

    private var beat: Double { 60 / Self.bpm }

    private func start() {
        let audio = AudioOut.shared
        var buffer = StereoBuffer(frames: Int((Double(Self.clicks + 1) * beat + 0.5) * audio.format.sampleRate),
                                  sampleRate: audio.format.sampleRate)
        for i in 0..<Self.clicks {
            buffer.add(audio.synth.click(accent: i % 4 == 0), at: Double(i) * beat)
        }
        guard let pcm = audio.pcm(buffer) else { return }
        taps = []
        running = true
        startUptime = audio.play(pcm)
        let total = Double(Self.clicks) * beat + 0.8
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.3) { finish() }
    }

    private func cancel() {
        AudioOut.shared.stopSong()
        running = false
        message = "Canceled. Nothing changed."
        Speaker.say(message)
    }

    private func finish() {
        guard running else { return }
        running = false
        // Each tap compared with the nearest click, after the warm-up clicks.
        let offsets: [Double] = taps.compactMap { uptime in
            let t = uptime - startUptime
            let n = (t / beat).rounded()
            guard n >= Double(Self.warmUp), n < Double(Self.clicks) else { return nil }
            let off = t - n * beat
            return abs(off) < beat * 0.4 ? off : nil
        }.sorted()
        guard offsets.count >= 6 else {
            message = "Not enough taps to measure. Try again, and tap with every click."
            Speaker.say(message)
            return
        }
        let median = offsets[offsets.count / 2]
        settings.calibration = median
        let ms = Int((median * 1000).rounded())
        message = ms >= 0 ? "Done. Your taps land \(ms) milliseconds after the sound. Saved." : "Done. Your taps land \(-ms) milliseconds before the sound. Saved."
        Speaker.say(message)
    }
}
