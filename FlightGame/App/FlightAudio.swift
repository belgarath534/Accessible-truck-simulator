import AVFoundation

/// Values the game writes on the main thread and the audio thread reads. A slightly stale read only means one
/// audio buffer (a few milliseconds) uses the previous value.
final class SoundState {
    var engineOn = false
    var cranking = false
    var rpm: Float = 0
    var maxRPM: Float = 2_600
    var throttle: Float = 0
    var airspeed: Float = 0
    var onGround = true
    /// Metres right of the runway centreline on the ground (nil-ish: 0 when unknown).
    var centreline: Float = 0
    var centrelineActive = false
    var verticalSpeed: Float = 0
    var bank: Float = 0
    var varioOn = true
    var bankToneOn = true
    /// Beacon: direction to the airport relative to the nose (degrees, + right), or nan when off.
    var beaconBearing: Float = .nan
    var beaconClose = false
    /// Landing guidance: metres right of the centreline and above the glide path, or nan when off.
    var approachLateral: Float = .nan
    var approachAbove: Float = 0
    var stallWarning = false
    var paused = false
    // One-shot sounds: seconds left.
    var thumpSeconds: Float = 0
    var crashSeconds: Float = 0
    var flapSeconds: Float = 0
    /// Recorded loops are playing, so the made-up engine, wind and rumble stay quiet.
    var sampledEngine = false
    var sampledWind = false
    var sampledRumble = false
}

/// All the flight's sound, made live: no recordings needed.
final class FlightAudio {
    let state = SoundState()
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    /// Recorded loops, each with its own speed (pitch) and volume.
    private struct Layer { let player: AVAudioPlayerNode; let speed: AVAudioUnitVarispeed }
    private var engineLayer: Layer?
    private var windLayer: Layer?
    private var rumbleLayer: Layer?

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let synth = Synth(state: state, sampleRate: Float(format.sampleRate))
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            synth.render(left: l, right: r, frames: Int(frameCount))
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        engineLayer = loop("engine_prop")
        windLayer = loop("wind_loop")
        rumbleLayer = loop("runway_rumble")
        state.sampledEngine = engineLayer != nil
        state.sampledWind = windLayer != nil
        state.sampledRumble = rumbleLayer != nil
    }

    private func loop(_ name: String) -> Layer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return nil }
        let player = AVAudioPlayerNode(), speed = AVAudioUnitVarispeed()
        engine.attach(player)
        engine.attach(speed)
        engine.connect(player, to: speed, format: buffer.format)
        engine.connect(speed, to: engine.mainMixerNode, format: buffer.format)
        player.volume = 0
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        return Layer(player: player, speed: speed)
    }

    func start() {
        if !engine.isRunning { try? engine.start() }
        for layer in [engineLayer, windLayer, rumbleLayer].compactMap({ $0 }) where !layer.player.isPlaying {
            layer.player.play()
        }
    }

    func stop() { engine.stop() }

    /// Called every frame: the recorded loops follow the engine, the airspeed and the wheels.
    func updateLayers() {
        let s = state
        let quiet = s.paused
        if let e = engineLayer {
            let running = s.engineOn && !quiet
            let fraction = max(0, min(1.2, s.rpm / max(s.maxRPM, 1)))
            e.speed.rate = 0.55 + 0.6 * fraction
            let target: Float = running ? 0.35 + 0.5 * s.throttle : 0
            e.player.volume += (target - e.player.volume) * 0.15
        }
        if let w = windLayer {
            let target: Float = quiet ? 0 : min(0.7, powf(s.airspeed / 65, 2) * 0.7)
            w.speed.rate = 0.7 + min(0.8, s.airspeed / 80)
            w.player.volume += (target - w.player.volume) * 0.1
        }
        if let r = rumbleLayer {
            let target: Float = (quiet || !s.onGround) ? 0 : min(0.8, s.airspeed / 30 * 0.8)
            r.speed.rate = 0.8 + min(0.7, s.airspeed / 40)
            r.player.volume += (target - r.player.volume) * 0.2
        }
    }
}

private struct Noise {
    var seed: UInt32 = 0x9E37_79B9
    mutating func next() -> Float {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }
}

private let twoPi = Float.pi * 2

private final class Synth {
    let s: SoundState
    let sr: Float
    var noise = Noise()
    // Smoothed values.
    var rpm: Float = 0, engAmp: Float = 0, wind: Float = 0, rumble: Float = 0
    // Phases and filters.
    var engPhase: Float = 0, bladePhase: Float = 0, crankPhase: Float = 0
    var lpEngine: Float = 0, lpWind: Float = 0, lpRumble: Float = 0, lpThump: Float = 0
    var lineTone: Float = 0, linePulse: Float = 0
    var varioPhase: Float = 0, varioBeat: Float = 0
    var bankPhase: Float = 0
    var beaconPhase: Float = 0, beaconClock: Float = 0
    var guidePhase: Float = 0, guideClock: Float = 0
    var hornPhase: Float = 0, hornBeat: Float = 0
    var flapPhase: Float = 0, thumpPhase: Float = 0

    init(state: SoundState, sampleRate: Float) { s = state; sr = sampleRate }

    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        let dt = 1 / sr
        let paused = s.paused
        for i in 0..<frames {
            var l: Float = 0, r: Float = 0
            if paused { left[i] = 0; right[i] = 0; continue }

            // Engine: four cylinders firing twice a turn, a two-blade propeller beating the air.
            rpm += (s.rpm - rpm) * 0.0005
            // With the recorded propeller playing, the made-up engine only does the starter.
            let synthEngine = !s.sampledEngine || (s.cranking && !s.engineOn)
            let targetAmp: Float = synthEngine && (s.engineOn || s.cranking) ? 0.16 + 0.22 * s.throttle : 0
            engAmp += (targetAmp - engAmp) * 0.0004
            if engAmp > 0.0005 {
                var f = max(rpm, 1) / 60 * 2
                if s.cranking && !s.engineOn {
                    crankPhase += 7 * dt; if crankPhase >= 1 { crankPhase -= 1 }
                    f = 18 + 6 * sinf(twoPi * crankPhase)
                }
                engPhase += f * dt; if engPhase >= 1 { engPhase -= 1 }
                bladePhase += f * dt; if bladePhase >= 1 { bladePhase -= 1 }
                let saw = engPhase * 2 - 1
                let raw = saw * 0.6 + sinf(twoPi * engPhase * 2) * 0.3 + noise.next() * 0.25
                lpEngine += (raw - lpEngine) * 0.08
                let blade = 0.75 + 0.25 * sinf(twoPi * bladePhase)
                let e = lpEngine * engAmp * blade
                l += e; r += e
            }

            // Wind over the airframe.
            let windTarget = s.sampledWind ? 0 : min(0.3, powf(s.airspeed / 70, 2) * 0.3)
            wind += (windTarget - wind) * 0.0005
            if wind > 0.0005 {
                let k = min(0.5, (300 + s.airspeed * 25) / sr * twoPi)
                lpWind += (noise.next() - lpWind) * k
                l += lpWind * wind; r += lpWind * wind * 0.95
            }

            // Wheels on the runway.
            let rumbleTarget: Float = s.onGround && !s.sampledRumble ? min(0.22, s.airspeed / 40 * 0.22) : 0
            rumble += (rumbleTarget - rumble) * 0.001
            if rumble > 0.0005 {
                lpRumble += (noise.next() - lpRumble) * 0.02
                l += lpRumble * rumble * 2; r += lpRumble * rumble * 2
            }

            // Centreline: a pulsing tone from the side you're drifting toward. Silent when centred.
            if s.centrelineActive, s.onGround, s.airspeed > 2, abs(s.centreline) > 3 {
                let amount = min(1, (abs(s.centreline) - 3) / 14)
                linePulse += 5 * dt; if linePulse >= 1 { linePulse -= 1 }
                lineTone += (500 + amount * 300) * dt; if lineTone >= 1 { lineTone -= 1 }
                let v = sinf(twoPi * lineTone) * (linePulse < 0.5 ? 1 : 0) * (0.06 + 0.16 * amount)
                if s.centreline > 0 { r += v; l += v * 0.15 } else { l += v; r += v * 0.15 }
            }

            // Variometer: rising beeps when climbing, a low falling tone when descending.
            if s.varioOn, !s.onGround {
                let vs = s.verticalSpeed
                if vs > 0.5 {
                    varioBeat += (1.5 + vs * 1.2) * dt; if varioBeat >= 1 { varioBeat -= 1 }
                    varioPhase += (650 + vs * 70) * dt; if varioPhase >= 1 { varioPhase -= 1 }
                    let v = sinf(twoPi * varioPhase) * (varioBeat < 0.45 ? 0.05 : 0)
                    l += v; r += v
                } else if vs < -1.2 {
                    varioPhase += max(180, 420 + vs * 25) * dt; if varioPhase >= 1 { varioPhase -= 1 }
                    let v = sinf(twoPi * varioPhase) * min(0.05, (-vs - 1.2) * 0.012)
                    l += v; r += v
                }
            }

            // Bank: a soft tone from the low wing, higher the steeper.
            if s.bankToneOn, !s.onGround, abs(s.bank) > 5 {
                let b = min(abs(s.bank), 60)
                bankPhase += (260 + b * 7) * dt; if bankPhase >= 1 { bankPhase -= 1 }
                let v = sinf(twoPi * bankPhase) * (0.02 + b / 60 * 0.06)
                if s.bank > 0 { r += v; l += v * 0.1 } else { l += v; r += v * 0.1 }
            }

            // Landing guidance: beeps from the side to steer toward; higher pitch = too low, climb.
            if !s.approachLateral.isNaN {
                guideClock += 2.2 * dt; if guideClock >= 1 { guideClock -= 1 }
                let f = max(350, min(1_150, 720 - s.approachAbove * 7))
                guidePhase += f * dt; if guidePhase >= 1 { guidePhase -= 1 }
                let on: Float = guideClock < 0.3 ? 1 : 0
                let v = sinf(twoPi * guidePhase) * on * 0.11
                let pan = max(-1, min(1, -s.approachLateral / 120))
                l += v * min(1, 1 - pan); r += v * min(1, 1 + pan)
            } else if !s.beaconBearing.isNaN {
                // Beacon toward the airport: a short beep from its side; high when ahead, low when behind.
                beaconClock += (s.beaconClose ? 1.2 : 0.6) * dt; if beaconClock >= 1 { beaconClock -= 1 }
                let ahead = abs(s.beaconBearing) < 90
                beaconPhase += (ahead ? 880 : 440) * dt; if beaconPhase >= 1 { beaconPhase -= 1 }
                let on: Float = beaconClock < 0.07 ? 1 : 0
                let v = sinf(twoPi * beaconPhase) * on * 0.1
                let pan = sinf(s.beaconBearing * .pi / 180)
                l += v * min(1, 1 - pan); r += v * min(1, 1 + pan)
            }

            // Stall horn.
            if s.stallWarning {
                hornBeat += 3 * dt; if hornBeat >= 1 { hornBeat -= 1 }
                hornPhase += 430 * dt; if hornPhase >= 1 { hornPhase -= 1 }
                let v: Float = (hornPhase < 0.5 ? 0.12 : -0.12) * (hornBeat < 0.6 ? 1 : 0)
                l += v; r += v
            }

            // One-shots.
            if s.flapSeconds > 0 {
                s.flapSeconds -= dt
                flapPhase += 140 * dt; if flapPhase >= 1 { flapPhase -= 1 }
                let v = (flapPhase * 2 - 1) * 0.04
                l += v; r += v
            }
            if s.thumpSeconds > 0 {
                s.thumpSeconds -= dt
                thumpPhase += 55 * dt; if thumpPhase >= 1 { thumpPhase -= 1 }
                lpThump += (noise.next() - lpThump) * 0.05
                let v = (sinf(twoPi * thumpPhase) * 0.5 + lpThump) * min(1, s.thumpSeconds * 3)
                l += v; r += v
            }
            if s.crashSeconds > 0 {
                s.crashSeconds -= dt
                let v = noise.next() * min(0.7, s.crashSeconds * 0.4)
                l += v; r += noise.next() * min(0.7, s.crashSeconds * 0.4)
            }

            left[i] = tanhf(l)
            right[i] = tanhf(r)
        }
    }
}
