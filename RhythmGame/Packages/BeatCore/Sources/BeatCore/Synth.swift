import Foundation

/// Stereo audio as two arrays of samples (-1...1).
public struct StereoBuffer: Sendable {
    public var left: [Float]
    public var right: [Float]
    public let sampleRate: Double

    public init(frames: Int, sampleRate: Double) {
        left = Array(repeating: 0, count: frames)
        right = Array(repeating: 0, count: frames)
        self.sampleRate = sampleRate
    }

    public var frames: Int { left.count }

    /// Mixes a mono sound in at a time, panned (-1 left ... 1 right).
    public mutating func add(_ sound: [Float], at time: Double, pan: Float = 0, gain: Float = 1) {
        let start = Int((time * sampleRate).rounded())
        let l = gain * min(1, 1 - pan), r = gain * min(1, 1 + pan)
        for (i, s) in sound.enumerated() {
            let f = start + i
            guard f >= 0 else { continue }
            guard f < frames else { break }
            left[f] += s * l
            right[f] += s * r
        }
    }

    /// Soft limiting so loud spots don't crackle.
    public mutating func limit() {
        for i in 0..<frames {
            left[i] = tanhf(left[i])
            right[i] = tanhf(right[i])
        }
    }
}

/// Drum, bass and cue sounds, made with a bit of math.
public struct Synth: Sendable {
    public let sampleRate: Double
    public init(sampleRate: Double = 44_100) { self.sampleRate = sampleRate }

    private func frames(_ seconds: Double) -> Int { Int(seconds * sampleRate) }

    /// Simple repeatable noise.
    private func noise(_ n: Int, seed: UInt64) -> [Float] {
        var rng = SeededRandom(seed: seed)
        return (0..<n).map { _ in Float(Double(rng.next() % 20_000) / 10_000 - 1) }
    }

    public func kick() -> [Float] {
        let n = frames(0.35)
        var phase = 0.0
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            let freq = 45 + 110 * exp(-t * 30)
            phase += 2 * .pi * freq / sampleRate
            return Float(sin(phase) * exp(-t * 9)) * 0.9
        }
    }

    public func snare() -> [Float] {
        let n = frames(0.22)
        let hiss = noise(n, seed: 7)
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            let body = sin(2 * .pi * 190 * t) * exp(-t * 25)
            return Float(body * 0.4) + hiss[i] * Float(exp(-t * 18)) * 0.45
        }
    }

    public func hat() -> [Float] {
        let n = frames(0.06)
        let hiss = noise(n, seed: 11)
        var last: Float = 0
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            // Crude high-pass: the difference between neighbours.
            let s = hiss[i] - last
            last = hiss[i]
            return s * Float(exp(-t * 60)) * 0.18
        }
    }

    public func bass(midi: Int, length: Double) -> [Float] {
        let freq = 440 * pow(2, Double(midi - 69) / 12)
        let n = frames(length)
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            let env = min(1, t * 200) * exp(-t * 3)
            let tone = sin(2 * .pi * freq * t) + 0.3 * sin(4 * .pi * freq * t)
            return Float(tone * env) * 0.32
        }
    }

    private func tone(_ freq: Double, seconds: Double, decay: Double, gain: Double) -> [Float] {
        (0..<frames(seconds)).map { i in
            let t = Double(i) / sampleRate
            return Float(sin(2 * .pi * freq * t) * min(1, t * 400) * exp(-t * decay) * gain)
        }
    }

    /// The cue sound for each move: different pitch, shape and side, so they work on a speaker or headphones.
    public func cue(_ move: Move) -> (sound: [Float], pan: Float) {
        switch move {
        case .tap:
            // Wooden knock.
            let a = tone(1_150, seconds: 0.09, decay: 55, gain: 0.7), b = tone(1_730, seconds: 0.09, decay: 70, gain: 0.3)
            return (zip(a, b).map(+), 0)
        case .left:
            return (tone(440, seconds: 0.16, decay: 18, gain: 0.7), -0.85)
        case .right:
            return (tone(990, seconds: 0.16, decay: 18, gain: 0.6), 0.85)
        case .up:
            var phase = 0.0
            let n = frames(0.16)
            var sound: [Float] = []
            sound.reserveCapacity(n)
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let freq: Double = 520 + 900 * t / 0.16
                phase += 2 * Double.pi * freq / sampleRate
                let env: Double = min(1, t * 300) * min(1, (0.16 - t) * 60)
                sound.append(Float(sin(phase) * env * 0.55))
            }
            return (sound, 0)
        }
    }

    /// A short click, for calibration.
    public func click(accent: Bool) -> [Float] { tone(accent ? 1_600 : 1_100, seconds: 0.05, decay: 80, gain: 0.8) }

    /// Feedback when you hit or miss.
    public func hitSound(_ j: Judgement) -> [Float] {
        switch j {
        case .perfect: return tone(2_400, seconds: 0.05, decay: 90, gain: 0.25)
        case .good: return tone(1_800, seconds: 0.05, decay: 90, gain: 0.18)
        case .wrongMove, .miss: return tone(110, seconds: 0.14, decay: 25, gain: 0.45)
        }
    }

    /// The whole song: drums, bass and every cue in the listen bars.
    public func render(_ chart: Chart, cueVolume: Float = 1) -> StereoBuffer {
        let song = chart.song
        var out = StereoBuffer(frames: frames(song.duration + 1), sampleRate: sampleRate)
        let k = kick(), s = snare(), h = hat()
        for bar in 0..<song.bars {
            let barStart = Double(bar) * song.barLength
            let outro = bar >= song.bars - Song.outroBars
            for step in 0..<16 {
                let t = barStart + Double(step) * song.stepLength
                if Array(song.kick)[step] == "x" { out.add(k, at: t) }
                if Array(song.snare)[step] == "x" { out.add(s, at: t, gain: 0.9) }
                if Array(song.hat)[step] == "x", !outro { out.add(h, at: t, pan: 0.2) }
            }
            let root = song.bassline[bar % song.bassline.count]
            out.add(bass(midi: root, length: song.beatLength * 1.8), at: barStart)
            out.add(bass(midi: root + 7, length: song.beatLength * 1.5), at: barStart + song.beatLength * 2.5, gain: 0.8)
        }
        // A soft low bell at the start of each listen bar, so you always know where you are.
        let bell = tone(330, seconds: 0.5, decay: 6, gain: 0.25)
        for start in chart.callBarStarts { out.add(bell, at: start, gain: 0.8 * cueVolume) }
        for note in chart.notes {
            let c = cue(note.move)
            out.add(c.sound, at: note.cueTime, pan: c.pan, gain: 1.1 * cueVolume)
        }
        out.limit()
        return out
    }
}
