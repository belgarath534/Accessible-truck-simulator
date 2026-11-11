import AVFoundation
import BeatCore

/// Plays the song and short sound effects, and knows exactly when the song starts.
@MainActor
final class AudioOut {
    static let shared = AudioOut()

    private let engine = AVAudioEngine()
    private let songPlayer = AVAudioPlayerNode()
    private let fxPlayer = AVAudioPlayerNode()
    let format: AVAudioFormat
    let synth: Synth

    private init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        synth = Synth(sampleRate: 44_100)
        engine.attach(songPlayer)
        engine.attach(fxPlayer)
        engine.connect(songPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(fxPlayer, to: engine.mainMixerNode, format: format)
    }

    private func ensureRunning() {
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            try? engine.start()
        }
        if !fxPlayer.isPlaying { fxPlayer.play() }
    }

    func pcm(_ b: StereoBuffer) -> AVAudioPCMBuffer? {
        guard b.frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(b.frames)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(b.frames)
        b.left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: b.frames) }
        b.right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: b.frames) }
        return buffer
    }

    func pcm(mono sound: [Float], pan: Float = 0, gain: Float = 1) -> AVAudioPCMBuffer? {
        var b = StereoBuffer(frames: sound.count, sampleRate: format.sampleRate)
        b.add(sound, at: 0, pan: pan, gain: gain)
        return pcm(b)
    }

    /// Starts a song a moment from now. Returns the system uptime at which its first sample reaches your ears.
    func play(_ buffer: AVAudioPCMBuffer) -> TimeInterval {
        ensureRunning()
        songPlayer.stop()
        songPlayer.scheduleBuffer(buffer, at: nil, options: [])
        let startHost = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.25)
        songPlayer.play(at: AVAudioTime(hostTime: startHost))
        return AVAudioTime.seconds(forHostTime: startHost) + AVAudioSession.sharedInstance().outputLatency
    }

    func stopSong() { songPlayer.stop() }

    func playFX(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }
        ensureRunning()
        fxPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    func playCue(_ move: Move) {
        let c = synth.cue(move)
        playFX(pcm(mono: c.sound, pan: c.pan))
    }
}
