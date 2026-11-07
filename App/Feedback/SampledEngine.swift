import AVFoundation

/// Recorded engine sound, used instead of the synthesized engine when the recordings are in the app.
///
/// Put files in App/Sounds (m4a, wav, caf or mp3):
///   engine_idle, engine_low, engine_mid, engine_high   seamless loops recorded at steady RPM
///   engine_start, engine_stop, air_brake, horn          one-shot sounds (each optional)
///
/// The loops are blended by RPM (each one is loudest near its own RPM) and sped up or slowed down
/// so the pitch follows the engine smoothly between them.
final class SampledEngine {
    /// Loop name and the RPM it was recorded at. Adjust if a recording sounds too high or low.
    static let loops: [(name: String, rpm: Float)] = [
        ("engine_idle", 600), ("engine_low", 1_000), ("engine_mid", 1_400), ("engine_high", 1_850),
    ]
    static let oneShotNames = ["engine_start", "engine_stop", "air_brake", "horn"]

    private struct Layer {
        let player: AVAudioPlayerNode
        let varispeed: AVAudioUnitVarispeed
        let rpm: Float
        let buffer: AVAudioPCMBuffer
    }

    private var layers: [Layer] = []
    private var oneShots: [String: (player: AVAudioPlayerNode, buffer: AVAudioPCMBuffer)] = [:]
    private var amp: Float = 0

    /// Returns nil unless at least the idle loop is in the app.
    init?(engine: AVAudioEngine) {
        for (name, rpm) in SampledEngine.loops {
            guard let buffer = SampledEngine.load(name) else { continue }
            let player = AVAudioPlayerNode()
            let varispeed = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(varispeed)
            engine.connect(player, to: varispeed, format: buffer.format)
            engine.connect(varispeed, to: engine.mainMixerNode, format: buffer.format)
            player.volume = 0
            layers.append(Layer(player: player, varispeed: varispeed, rpm: rpm, buffer: buffer))
        }
        guard layers.contains(where: { $0.rpm == SampledEngine.loops[0].rpm }) else {
            layers.forEach { engine.detach($0.player); engine.detach($0.varispeed) }
            return nil
        }
        for name in SampledEngine.oneShotNames {
            guard let buffer = SampledEngine.load(name) else { continue }
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            oneShots[name] = (player, buffer)
        }
    }

    static func load(_ name: String) -> AVAudioPCMBuffer? {
        for ext in ["m4a", "wav", "caf", "mp3"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) ?? Bundle.main.url(
                forResource: name, withExtension: ext, subdirectory: "Sounds") else { continue }
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil else { continue }
            return buffer
        }
        return nil
    }

    /// Call after the audio engine has started.
    func startLoops() {
        for layer in layers {
            layer.player.scheduleBuffer(layer.buffer, at: nil, options: .loops)
            layer.player.play()
        }
    }

    func has(_ oneShot: String) -> Bool { oneShots[oneShot] != nil }

    /// Plays a one-shot sound. Returns false if that recording isn't in the app.
    @discardableResult
    func play(_ name: String, volume: Float) -> Bool {
        guard let shot = oneShots[name] else { return false }
        shot.player.stop()
        shot.player.volume = volume
        shot.player.scheduleBuffer(shot.buffer, at: nil)
        shot.player.play()
        return true
    }

    /// Call every frame.
    func update(rpm: Float, load: Float, running: Bool, volume: Float) {
        amp += ((running ? 1 : 0) - amp) * (running ? 0.15 : 0.06)
        let sorted = layers.sorted { $0.rpm < $1.rpm }
        guard let first = sorted.first, let last = sorted.last else { return }
        let r = max(rpm, 1)
        var gains = [Float](repeating: 0, count: sorted.count)
        if r <= first.rpm {
            gains[0] = 1
        } else if r >= last.rpm {
            gains[sorted.count - 1] = 1
        } else if let i = sorted.indices.dropLast().first(where: { r >= sorted[$0].rpm && r <= sorted[$0 + 1].rpm }) {
            // Equal-power crossfade between the two nearest recordings.
            let t = (r - sorted[i].rpm) / (sorted[i + 1].rpm - sorted[i].rpm)
            gains[i] = cos(t * .pi / 2)
            gains[i + 1] = sin(t * .pi / 2)
        }
        let level = (0.6 + 0.4 * load) * amp * volume
        for (i, layer) in sorted.enumerated() {
            layer.varispeed.rate = min(2, max(0.5, r / layer.rpm))
            layer.player.volume = gains[i] * level
        }
    }
}
