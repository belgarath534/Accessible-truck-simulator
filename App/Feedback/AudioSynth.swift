import AVFoundation
import SimCore

/// Values written by the game on the main thread and read by the audio render thread.
/// Plain stored values are fine for a prototype: a slightly stale read just means one
/// audio buffer (a few milliseconds) uses the previous value.
final class SynthState {
    var rpm: Float = 0
    var load: Float = 0
    var engineRunning = false
    var cranking = false
    var cylinders: Float = 6
    var maxRPM: Float = 2_100
    var speed: Float = 0
    var rumble: Float = 0
    var laneOffset: Float = 0
    var laneToneEnabled = true
    var signalOn = false
    var hornSeconds: Float = 0
    var crashSeconds: Float = 0
    var shiftSeconds: Float = 0
    var volume: Float = 0.8
    var muted = false
}

private protocol Voice: AnyObject {
    func render(_ out: UnsafeMutablePointer<Float>, frames: Int)
}

private struct Noise {
    var seed: UInt32 = 0x1234_5678
    mutating func next() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }
}

private let twoPi = Float.pi * 2

private func onePoleCoefficient(cutoff: Float, sampleRate: Float) -> Float {
    1 - expf(-twoPi * cutoff / sampleRate)
}

/// A diesel engine built from scratch: firing-frequency harmonics for the body,
/// filtered noise bursts on each combustion for the clatter, and a turbo whistle under load.
private final class EngineVoice: Voice {
    let state: SynthState
    let sr: Float
    var phase: Float = 0, crank: Float = 0, turbo: Float = 0, starter: Float = 0
    var rpm: Float = 0, load: Float = 0, amp: Float = 0, lp: Float = 0, lp2: Float = 0
    var noise = Noise()

    init(state: SynthState, sampleRate: Float) { self.state = state; sr = sampleRate }

    func render(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        let targetAmp: Float = (state.engineRunning || state.cranking) && !state.muted ? 1 : 0
        for i in 0..<frames {
            rpm += (state.rpm - rpm) * 0.0008
            load += (state.load - load) * 0.0006
            amp += (targetAmp - amp) * (targetAmp > amp ? 0.002 : 0.00015)

            let fire = max(rpm, 1) / 60 * state.cylinders / 2
            phase += fire / sr; if phase >= 1 { phase -= 1 }
            crank += max(rpm, 1) / 60 / sr; if crank >= 1 { crank -= 1 }

            var body = sinf(twoPi * phase) * 0.45
            body += sinf(twoPi * 2 * phase) * 0.30
            body += sinf(twoPi * 3 * phase) * 0.18
            body += sinf(twoPi * 4 * phase) * (0.08 + 0.06 * load)
            body += sinf(twoPi * crank) * 0.25

            // Combustion clatter: a noise burst at the start of every firing, brighter under load.
            let env = expf(-phase * 9)
            let cutoff = 500 + 2_600 * load + rpm * 0.4
            let c = onePoleCoefficient(cutoff: cutoff, sampleRate: sr)
            lp += (noise.next() * env - lp) * c
            lp2 += (lp - lp2) * c
            let knock = lp2 * (0.8 + 1.4 * load)

            turbo += (1_600 + rpm * 1.3) / sr; if turbo >= 1 { turbo -= 1 }
            let whistle = sinf(twoPi * turbo) * 0.02 * load * (rpm / state.maxRPM)

            var s = body * (0.28 + 0.22 * load) + knock + whistle
            if state.cranking {
                starter += 110 / sr; if starter >= 1 { starter -= 1 }
                s += (starter * 2 - 1) * 0.10 + noise.next() * 0.03
            }
            out[i] = s * amp * state.volume * 0.7
        }
    }
}

/// Tyre roar and wind, rising with speed.
private final class RoadVoice: Voice {
    let state: SynthState
    let sr: Float
    var lp1: Float = 0, lp2: Float = 0, speed: Float = 0
    var noise = Noise(seed: 0x9E37_79B9)

    init(state: SynthState, sampleRate: Float) { self.state = state; sr = sampleRate }

    func render(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames {
            speed += (state.speed - speed) * 0.001
            let level = min(1, speed / 25)
            let c = onePoleCoefficient(cutoff: 200 + speed * 25, sampleRate: sr)
            lp1 += (noise.next() - lp1) * c
            lp2 += (lp1 - lp2) * c
            out[i] = state.muted ? 0 : lp2 * level * 0.9 * state.volume
        }
    }
}

/// Rumble strip: rapid thumps whose rate follows speed. Panned to the side the truck is drifting toward.
private final class RumbleVoice: Voice {
    let state: SynthState
    let sr: Float
    var phase: Float = 0, amp: Float = 0, lp: Float = 0
    var noise = Noise(seed: 0xDEAD_BEEF)

    init(state: SynthState, sampleRate: Float) { self.state = state; sr = sampleRate }

    func render(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        let target = state.muted ? 0 : state.rumble * min(1, state.speed / 4)
        let rate = max(state.speed, 0.5) / 0.3
        let c = onePoleCoefficient(cutoff: 400, sampleRate: sr)
        for i in 0..<frames {
            amp += (target - amp) * 0.003
            phase += rate / sr; if phase >= 1 { phase -= 1 }
            lp += (noise.next() - lp) * c
            let thump = (lp * 3 + sinf(twoPi * phase)) * expf(-phase * 5)
            out[i] = thump * amp * 0.6 * state.volume
        }
    }
}

/// Optional lane guidance: soft beeps in the ear the truck is drifting toward.
/// They speed up and rise in pitch the further from the centre of the lane you are.
private final class LaneVoice: Voice {
    let state: SynthState
    let sr: Float
    var phase: Float = 0, osc: Float = 0

    init(state: SynthState, sampleRate: Float) { self.state = state; sr = sampleRate }

    func render(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        let deviation = abs(state.laneOffset) - 0.25
        let active = state.laneToneEnabled && deviation > 0 && state.speed > 1 && !state.muted
        let rate = 1.5 + deviation * 10
        let freq = 600 + deviation * 700
        for i in 0..<frames {
            guard active else { out[i] = 0; phase = 0; continue }
            phase += rate / sr; if phase >= 1 { phase -= 1 }
            let t = phase / rate // seconds since the beep started
            osc += freq / sr; if osc >= 1 { osc -= 1 }
            out[i] = t < 0.045 ? sinf(twoPi * osc) * 0.16 * (1 - t / 0.045) * state.volume : 0
        }
    }
}

/// One-shot effects: indicator clicks, horn, gear-change air hiss, crash.
private final class FXVoice: Voice {
    let state: SynthState
    let sr: Float
    var signalPhase: Float = 0, hornA: Float = 0, hornB: Float = 0, clickOsc: Float = 0, lp: Float = 0
    var noise = Noise(seed: 0x0BAD_F00D)

    init(state: SynthState, sampleRate: Float) { self.state = state; sr = sampleRate }

    func render(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        let dt = 1 / sr
        for i in 0..<frames {
            var s: Float = 0
            if state.signalOn {
                signalPhase += dt / 0.8; if signalPhase >= 1 { signalPhase -= 1 }
                let half = signalPhase < 0.5
                let t = (half ? signalPhase : signalPhase - 0.5) * 0.8
                if t < 0.015 {
                    clickOsc += (half ? 2_200 : 1_600) / sr; if clickOsc >= 1 { clickOsc -= 1 }
                    s += sinf(twoPi * clickOsc) * 0.35 * (1 - t / 0.015)
                }
            } else {
                signalPhase = 0
            }
            if state.hornSeconds > 0 {
                state.hornSeconds -= dt
                hornA += 185 / sr; if hornA >= 1 { hornA -= 1 }
                hornB += 233 / sr; if hornB >= 1 { hornB -= 1 }
                let a = sinf(twoPi * hornA) + sinf(twoPi * hornA * 3) * 0.3 + sinf(twoPi * hornA * 5) * 0.15
                let b = sinf(twoPi * hornB) + sinf(twoPi * hornB * 3) * 0.3 + sinf(twoPi * hornB * 5) * 0.15
                s += (a + b) * 0.22 * min(1, state.hornSeconds * 20)
            }
            if state.shiftSeconds > 0 {
                state.shiftSeconds -= dt
                let n = noise.next()
                lp += (n - lp) * 0.2
                s += (n - lp) * 0.25 * (state.shiftSeconds / 0.25)
            }
            if state.crashSeconds > 0 {
                state.crashSeconds -= dt
                let env = state.crashSeconds / 1.5
                s += noise.next() * env * env * 0.9 + sinf(twoPi * 45 * state.crashSeconds) * env * 0.6
            }
            out[i] = state.muted ? 0 : s * state.volume
        }
    }
}

/// All game audio. Everything is synthesized, so the prototype needs no sound files.
final class AudioSynth {
    let state = SynthState()
    private let engine = AVAudioEngine()
    private var rumbleNode: AVAudioSourceNode?
    private var laneNode: AVAudioSourceNode?
    private var voices: [AnyObject] = []
    private var configObserver: NSObjectProtocol?

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)

        let sampleRate = session.sampleRate > 0 ? session.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        let sr = Float(sampleRate)

        let engineVoice = EngineVoice(state: state, sampleRate: sr)
        let road = RoadVoice(state: state, sampleRate: sr)
        let rumble = RumbleVoice(state: state, sampleRate: sr)
        let lane = LaneVoice(state: state, sampleRate: sr)
        let fx = FXVoice(state: state, sampleRate: sr)
        voices = [engineVoice, road, rumble, lane, fx]

        func attach(_ voice: Voice) -> AVAudioSourceNode {
            let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
                let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    voice.render(data, frames: Int(frameCount))
                }
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            return node
        }
        _ = attach(engineVoice)
        _ = attach(road)
        rumbleNode = attach(rumble)
        laneNode = attach(lane)
        _ = attach(fx)

        engine.prepare()
        try? engine.start()

        // Restart if the route changes (e.g. headphones plugged in).
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            try? self?.engine.start()
        }
    }

    func stop() {
        engine.stop()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
    }

    /// Called every frame with the latest truck state.
    func update(truck: TruckState, spec: TruckSpec) {
        state.rpm = Float(truck.rpm)
        state.load = Float(truck.engineLoad)
        state.engineRunning = truck.engine == .running
        if case .starting = truck.engine { state.cranking = true } else { state.cranking = false }
        state.cylinders = Float(spec.cylinders)
        state.maxRPM = Float(spec.maxRPM)
        state.speed = Float(truck.speed)
        state.laneOffset = Float(truck.lateralOffset)
        state.signalOn = truck.signal != .off
        laneNode?.pan = Float(max(-1, min(1, truck.lateralOffset / DrivingSession.rumbleOffset)))
    }

    func setRumble(_ side: Side?) {
        state.rumble = side == nil ? 0 : 1
        if let side { rumbleNode?.pan = side == .left ? -0.9 : 0.9 }
    }

    func honk() { state.hornSeconds = 0.7 }
    func crash() { state.crashSeconds = 1.5 }
    func gearShift() { state.shiftSeconds = 0.25 }
}
