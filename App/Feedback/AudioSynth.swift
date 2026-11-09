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
    /// Fuel pump running (truck stop).
    var pumping = false
    /// Police siren behind the truck.
    var siren = false
    /// Metres to the drop-off for the beacon (negative = past it); -1000 = off.
    var beaconDistance: Float = -1_000
    /// Seconds left of a police radio crackle (passing a parked police car).
    var crackleSeconds: Float = 0
    /// Seconds left of an oncoming car's horn.
    var carHornSeconds: Float = 0
    /// Traffic: up to four nearby vehicles, one sound each.
    // Fixed blocks of memory, not Swift arrays: the game writes them while the audio thread reads them, and
    // an array being changed and read at the same moment makes iOS stop the app ("simultaneous access").
    let trafficGain = SynthState.block(Float(0))
    let trafficPitch = SynthState.block(Float(1))
    let trafficSpeed = SynthState.block(Float(0))
    let trafficIsTruck = SynthState.block(false)
    let trafficBehind = SynthState.block(false)

    private static func block<T>(_ value: T) -> UnsafeMutablePointer<T> {
        let p = UnsafeMutablePointer<T>.allocate(capacity: 4)
        p.initialize(repeating: value, count: 4)
        return p
    }
    var crashSeconds: Float = 0
    var shiftSeconds: Float = 0
    var volume: Float = 0.8
    var muted = false
    /// Recorded engine loops are playing, so the synthesized engine stays quiet.
    var useSampledEngine = false
    /// A recorded starter sound exists, so the synthesized starter stays quiet too.
    var hasStartSample = false
    // The truck's engine voice (see EngineSound in SimCore).
    var pitch: Float = 1
    var roughness: Float = 0.3
    var turboAmount: Float = 0.3
    var bark: Float = 0.2
    var lope: Float = 0.1
    /// Electric truck: a motor whine instead of an engine.
    var electric = false
    /// Rain: 0 dry, about 0.6 rain, 1 storm.
    var rain: Float = 0
    /// Seconds left of a thunderclap.
    var thunderSeconds: Float = 0
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
    var phase: Float = 0, crank: Float = 0, halfCrank: Float = 0, turbo: Float = 0, starter: Float = 0
    var cycleAmp: Float = 1
    var rpm: Float = 0, load: Float = 0, amp: Float = 0, lp: Float = 0, lp2: Float = 0
    var motor: Float = 0, motor2: Float = 0, inverter: Float = 0, hum: Float = 0
    var noise = Noise()

    init(state: SynthState, sampleRate: Float) { self.state = state; sr = sampleRate }

    func render(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        let synthOn = state.useSampledEngine
            ? (state.cranking && !state.hasStartSample)
            : (state.engineRunning || state.cranking)
        let targetAmp: Float = synthOn && !state.muted ? 1 : 0
        for i in 0..<frames {
            rpm += (state.rpm - rpm) * 0.0008
            load += (state.load - load) * 0.0006
            amp += (targetAmp - amp) * (targetAmp > amp ? 0.002 : 0.00015)

            if state.electric {
                // Electric motor: a whine that rises with motor speed, a faint inverter whine under power,
                // and a soft hum so you can tell it's switched on while standing still.
                let f = max(rpm, 0) / 60 * 6
                motor += f / sr; if motor >= 1 { motor -= 1 }
                motor2 += f * 2.5 / sr; if motor2 >= 1 { motor2 -= 1 }
                inverter += (1_900 + rpm * 0.35) / sr; if inverter >= 1 { inverter -= 1 }
                hum += 100 / sr; if hum >= 1 { hum -= 1 }
                let spin = min(1, rpm / state.maxRPM * 1.6)
                var e = sinf(twoPi * motor) * 0.32 + sinf(twoPi * motor2) * 0.12
                e *= spin * (0.55 + 0.45 * load)
                e += sinf(twoPi * inverter) * 0.035 * load
                e += sinf(twoPi * hum) * 0.05
                out[i] = e * amp * state.volume * 0.7
                continue
            }

            let fire = max(rpm, 1) / 60 * state.cylinders / 2 * state.pitch
            phase += fire / sr
            if phase >= 1 {
                phase -= 1
                // Rough engines fire unevenly: each combustion is a little louder or softer.
                cycleAmp = 1 + state.roughness * noise.next() * 0.4
            }
            crank += max(rpm, 1) / 60 * state.pitch / sr; if crank >= 1 { crank -= 1 }
            halfCrank += max(rpm, 1) / 120 * state.pitch / sr; if halfCrank >= 1 { halfCrank -= 1 }

            var body = sinf(twoPi * phase) * 0.45
            body += sinf(twoPi * 2 * phase) * 0.30
            body += sinf(twoPi * 3 * phase) * 0.18
            body += sinf(twoPi * 4 * phase) * (0.08 + 0.06 * load)
            // Bigger (lower-pitched) engines carry more low rumble.
            body += sinf(twoPi * crank) * 0.25 * (1.6 - 0.6 * state.pitch)
            body *= cycleAmp

            // Combustion clatter: a noise burst at the start of every firing, brighter under load.
            let env = expf(-phase * 9)
            let cutoff = 500 + 2_600 * load + rpm * 0.4
            let c = onePoleCoefficient(cutoff: cutoff, sampleRate: sr)
            lp += (noise.next() * env - lp) * c
            lp2 += (lp - lp2) * c
            let knock = lp2 * (0.8 + 1.4 * load) * (0.4 + 1.2 * state.roughness) * cycleAmp

            turbo += (1_600 + rpm * 1.3) / sr; if turbo >= 1 { turbo -= 1 }
            let whistle = sinf(twoPi * turbo) * 0.06 * state.turboAmount * (0.3 + 0.7 * load) * (rpm / state.maxRPM)

            var s = body * (0.28 + 0.22 * load) + knock + whistle
            // Lumpy idle: the sound rocks once every two crank turns near idle.
            let nearIdle = max(0, 1 - (rpm - 600) / 500)
            s *= 1 + state.lope * 0.4 * nearIdle * sinf(twoPi * halfCrank)
            // Barking exhaust: drive the tone harder into soft saturation.
            if state.bark > 0 {
                let drive = 1 + state.bark * 2.5
                s = tanhf(s * drive) / (0.6 + 0.4 * drive)
            }
            if state.cranking && !state.electric {
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
/// One nearby vehicle: tyre roar and engine hum, with Doppler pitch, getting muffled once it's behind you.
private final class TrafficVoice: Voice {
    let state: SynthState
    let sr: Float
    let slot: Int
    var gain: Float = 0, lp1: Float = 0, lp2: Float = 0, hum: Float = 0, hum2: Float = 0, muffle: Float = 0
    var noise: Noise

    init(state: SynthState, sampleRate: Float, slot: Int) {
        self.state = state
        sr = sampleRate
        self.slot = slot
        noise = Noise(seed: 0x5EED_0000 &+ UInt32(slot) &* 7_919)
    }

    func render(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        let targetGain = state.muted ? 0 : state.trafficGain[slot]
        let pitch = state.trafficPitch[slot]
        let speed = state.trafficSpeed[slot]
        let truck = state.trafficIsTruck[slot]
        let tyreCut = (300 + speed * 40) * pitch
        let c = onePoleCoefficient(cutoff: tyreCut, sampleRate: sr)
        let muffleTarget: Float = state.trafficBehind[slot] ? 1 : 0
        let humFreq = (truck ? 52 : 95) * pitch * (0.7 + speed / 40)
        for i in 0..<frames {
            gain += (targetGain - gain) * 0.002
            muffle += (muffleTarget - muffle) * 0.0005
            lp1 += (noise.next() - lp1) * c
            lp2 += (lp1 - lp2) * c * (1 - 0.7 * muffle)
            hum += humFreq / sr; if hum >= 1 { hum -= 1 }
            hum2 += humFreq * 2.01 / sr; if hum2 >= 1 { hum2 -= 1 }
            let engine = sinf(twoPi * hum) * (truck ? 0.35 : 0.2) + sinf(twoPi * hum2) * 0.1
            out[i] = (lp2 * 1.6 + engine) * gain * state.volume
        }
    }
}

/// Weather: rain on the cab roof, wipers, tyre spray on the wet road, and thunder.
private final class WeatherVoice: Voice {
    let state: SynthState
    let sr: Float
    var lp: Float = 0, hp: Float = 0, dropEnv: Float = 0, dropLP: Float = 0
    var sprayLP: Float = 0, sprayHP: Float = 0
    var wiperPhase: Float = 0, wiperLP: Float = 0
    var thunderLP: Float = 0, thunderLP2: Float = 0, thunderLength: Float = 4
    var noise = Noise(seed: 0x7A1D_0001)

    init(state: SynthState, sampleRate: Float) { self.state = state; sr = sampleRate }

    func render(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        let rain = state.rain
        let thunderOn = state.thunderSeconds > 0
        if (rain <= 0 && !thunderOn) || state.muted {
            for i in 0..<frames { out[i] = 0 }
            return
        }
        let dt = 1 / sr
        let wiperPeriod: Float = rain > 0.8 ? 0.9 : 1.4
        let wipersOn = state.engineRunning || state.cranking
        let speed = state.speed
        for i in 0..<frames {
            var s: Float = 0
            if rain > 0 {
                // Steady rain: soft hiss on the roof.
                let n = noise.next()
                lp += (n - lp) * 0.25
                hp += (lp - hp) * 0.02
                s += (lp - hp) * 0.22 * rain
                // Individual drops tapping the cab.
                if noise.next() > 1 - 0.0009 * rain { dropEnv = 1 }
                dropEnv *= 0.995
                dropLP += (noise.next() - dropLP) * 0.5
                s += dropLP * dropEnv * 0.18 * rain
                // Tyres hissing through water, rising with speed.
                let wet = min(1, speed / 20) * rain
                sprayLP += (n - sprayLP) * 0.5
                sprayHP += (sprayLP - sprayHP) * 0.08
                s += (sprayLP - sprayHP) * 0.3 * wet
                // Wipers: a swish each way.
                if wipersOn {
                    wiperPhase += dt / wiperPeriod; if wiperPhase >= 1 { wiperPhase -= 1 }
                    let half = wiperPhase < 0.5 ? wiperPhase * 2 : (wiperPhase - 0.5) * 2
                    let env = sinf(Float.pi * min(1, half / 0.6))
                    wiperLP += (noise.next() - wiperLP) * 0.06
                    s += wiperLP * env * env * 0.35
                }
            }
            if state.thunderSeconds > 0 {
                state.thunderSeconds -= dt
                // A deep rumble that rolls in fast and fades slowly.
                let t = 1 - state.thunderSeconds / thunderLength
                let env = min(1, t * 8) * expf(-t * 3) * (0.7 + 0.3 * noise.next())
                thunderLP += (noise.next() - thunderLP) * 0.01
                thunderLP2 += (thunderLP - thunderLP2) * 0.02
                s += thunderLP2 * env * 9
            }
            out[i] = s * state.volume
        }
    }
}

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
    var pumpPhase: Float = 0, pumpLP: Float = 0
    var sirenTime: Float = 0, sirenPhase: Float = 0, sirenAmp: Float = 0
    var beaconClock: Float = 0, beaconOsc: Float = 0
    var carHornA: Float = 0, carHornB: Float = 0, carHornLP: Float = 0
    var crackleHP: Float = 0, crackleLP: Float = 0, crackleTone: Float = 0
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
            if state.pumping {
                // Fuel pump: an electric motor hum with liquid rushing.
                pumpPhase += 118 / sr; if pumpPhase >= 1 { pumpPhase -= 1 }
                let n = noise.next()
                pumpLP += (n - pumpLP) * 0.05
                s += (sinf(twoPi * pumpPhase) * 0.12 + sinf(twoPi * pumpPhase * 2) * 0.05 + pumpLP * 0.5) * 0.8
            }
            // Drop-off beacon, like a parking sensor: faster beeps as you get closer, steady at the drop-off,
            // and a lower tone once you're past it.
            let bd = state.beaconDistance
            if bd > -999 && !state.muted {
                let past = bd < 0
                let freq: Float = past ? 520 : 1_040
                beaconOsc += freq / sr; if beaconOsc >= 1 { beaconOsc -= 1 }
                let tone = sinf(twoPi * beaconOsc) * 0.14
                if abs(bd) <= 12 {
                    s += tone
                } else {
                    let interval = 0.08 + min(1, abs(bd) / 150) * 0.7
                    beaconClock += dt; if beaconClock >= interval { beaconClock -= interval }
                    if beaconClock < 0.06 { s += tone * (1 - beaconClock / 0.06) }
                }
            } else {
                beaconClock = 0
            }
            // An oncoming car's horn: two quick toots.
            if state.carHornSeconds > 0 {
                state.carHornSeconds -= dt
                let on = state.carHornSeconds > 0.55 || (state.carHornSeconds < 0.4 && state.carHornSeconds > 0.05)
                if on {
                    carHornA += 415 / sr; if carHornA >= 1 { carHornA -= 1 }
                    carHornB += 520 / sr; if carHornB >= 1 { carHornB -= 1 }
                    let sq = (carHornA < 0.5 ? 1 : -1) * 0.5 + (carHornB < 0.5 ? 1 : -1) * 0.5
                    carHornLP += (Float(sq) - carHornLP) * 0.25
                    s += carHornLP * 0.22
                }
            }
            // Police siren: a wail sweeping up and down, fading in and out.
            sirenAmp += ((state.siren ? 1 : 0) - sirenAmp) * 0.0005
            if sirenAmp > 0.001 {
                sirenTime += dt
                let sweep = 0.5 - 0.5 * cosf(twoPi * sirenTime / 3.2)
                sirenPhase += (650 + 700 * sweep) / sr; if sirenPhase >= 1 { sirenPhase -= 1 }
                let tone = sinf(twoPi * sirenPhase) + 0.35 * sinf(twoPi * 2 * sirenPhase) + 0.15 * sinf(twoPi * 3 * sirenPhase)
                s += tone * 0.16 * sirenAmp
            } else {
                sirenTime = 0
            }
            // Police radio crackle: band-passed static with a short squelch tone.
            if state.crackleSeconds > 0 {
                state.crackleSeconds -= dt
                let n = noise.next()
                crackleLP += (n - crackleLP) * 0.35
                crackleHP += (crackleLP - crackleHP) * 0.05
                let band = (crackleLP - crackleHP) * (noise.next() > 0.6 ? 1.6 : 0.5)
                crackleTone += 1_150 / sr; if crackleTone >= 1 { crackleTone -= 1 }
                let squelch = state.crackleSeconds > 0.45 ? sinf(twoPi * crackleTone) * 0.12 : 0
                s += (band * 0.45 + squelch) * min(1, state.crackleSeconds * 8)
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
    private var sampled: SampledEngine?
    /// The air horn recording, used by every truck.
    private var hornPlayer: AVAudioPlayerNode?
    private var trafficNodes: [AVAudioSourceNode] = []
    /// Which vehicle id each traffic sound slot is playing.
    private var trafficSlots: [Int?] = [nil, nil, nil, nil]
    private var hornBuffer: AVAudioPCMBuffer?
    private var configObserver: NSObjectProtocol?
    // Recorded weather: rain (light or storm), wipers and wet tyres loop; thunder plays once.
    private var weatherLoops: [String: (player: AVAudioPlayerNode, buffer: AVAudioPCMBuffer)] = [:]
    private var thunderShot: (player: AVAudioPlayerNode, buffer: AVAudioPCMBuffer)?
    private var weather: Weather = .clear
    private var hasWeatherRecordings: Bool { weatherLoops.count == 4 }
    // Living world: looping ambience (towns, night, dawn, construction) that fades in and out, and one-shot effects.
    static let ambienceNames = ["amb_night", "amb_dawn", "amb_construction", "amb_town_millbrook", "amb_town_cedar_falls",
                                "amb_town_ridgeport", "amb_town_ironton", "amb_town_bayview"]
    static let effectNames = ["fx_deer", "fx_toll"]
    private var ambienceLoops: [String: (player: AVAudioPlayerNode, buffer: AVAudioPCMBuffer)] = [:]
    private var ambienceLevel: [String: Float] = [:]
    private var ambienceTarget: [String: Float] = [:]
    private var effects: [String: (player: AVAudioPlayerNode, buffer: AVAudioPCMBuffer)] = [:]

    func start(sound: EngineSound = .recorded, idleRPM: Float = 600, maxRPM: Float = 2_100) {
        state.pitch = Float(sound.pitch)
        state.roughness = Float(sound.roughness)
        state.turboAmount = Float(sound.turbo)
        state.bark = Float(sound.bark)
        state.lope = Float(sound.lope)
        state.electric = sound.electric
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
        let weather = WeatherVoice(state: state, sampleRate: sr)
        voices = [engineVoice, road, rumble, lane, fx, weather]

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
        trafficNodes = (0..<4).map { attach(TrafficVoice(state: state, sampleRate: sr, slot: $0)) }
        _ = attach(fx)
        _ = attach(weather)

        if sound.recorded {
            sampled = SampledEngine(engine: engine)
        } else if let loop = sound.loopFile {
            sampled = SampledEngine(engine: engine, loop: loop, idleRPM: idleRPM, maxRPM: maxRPM)
        } else {
            sampled = nil
        }
        if let buffer = SampledEngine.load("horn") {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            hornPlayer = player
            hornBuffer = buffer
        }
        for name in ["weather_rain_light", "weather_rain_storm", "weather_wipers", "weather_wet_tires", "weather_thunder"] {
            guard let buffer = SampledEngine.load(name) else { continue }
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            player.volume = 0
            if name == "weather_thunder" { thunderShot = (player, buffer) } else { weatherLoops[name] = (player, buffer) }
        }
        for name in AudioSynth.ambienceNames + AudioSynth.effectNames {
            guard let buffer = SampledEngine.load(name) else { continue }
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            player.volume = 0
            if name.hasPrefix("fx_") { effects[name] = (player, buffer) } else { ambienceLoops[name] = (player, buffer) }
        }
        state.useSampledEngine = sampled != nil
        state.hasStartSample = sampled?.has("engine_start") ?? false

        engine.prepare()
        try? engine.start()
        sampled?.startLoops()
        setWeather(self.weather)

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
        sampled?.update(rpm: state.rpm, load: state.load, running: state.engineRunning,
                        volume: state.muted ? 0 : state.volume)
        updateWeatherVolumes()
        updateAmbience()
    }

    /// What ambience should play, and how loud (0...1). Loops not named fade out.
    func setAmbience(_ targets: [String: Float]) { ambienceTarget = targets }

    /// Fades each ambience loop toward its target, starting and stopping players as needed.
    private func updateAmbience() {
        guard engine.isRunning else { return }
        for (name, loop) in ambienceLoops {
            let target = state.muted ? 0 : (ambienceTarget[name] ?? 0)
            var level = ambienceLevel[name] ?? 0
            level += (target - level) * 0.02
            if abs(level - target) < 0.002 { level = target }
            ambienceLevel[name] = level
            if level > 0.001 && !loop.player.isPlaying {
                loop.player.scheduleBuffer(loop.buffer, at: nil, options: .loops)
                loop.player.play()
            } else if level <= 0.001 && target == 0 && loop.player.isPlaying {
                loop.player.stop()
            }
            loop.player.volume = level * state.volume
        }
    }

    /// Plays a one-shot effect, panned (-1 left ... 1 right).
    func playEffect(_ name: String, volume: Float = 1, pan: Float = 0) {
        guard let fx = effects[name], !state.muted else { return }
        fx.player.stop()
        fx.player.volume = state.volume * volume
        fx.player.pan = pan
        fx.player.scheduleBuffer(fx.buffer, at: nil)
        fx.player.play()
    }

    /// Drives the engine sound directly (garage preview), without a simulation.
    func setPreview(rpm: Float, load: Float, running: Bool, maxRPM: Float, cylinders: Float) {
        state.rpm = rpm
        state.load = load
        state.engineRunning = running
        state.maxRPM = maxRPM
        state.cylinders = cylinders
        sampled?.update(rpm: rpm, load: load, running: running, volume: state.muted ? 0 : state.volume)
    }

    func engineStarting() { sampled?.play("engine_start", volume: state.volume) }
    func engineStopped() { sampled?.play("engine_stop", volume: state.volume) }
    func airBrake() { sampled?.play("air_brake", volume: state.volume * 0.8) }

    func setRumble(_ side: Side?) {
        state.rumble = side == nil ? 0 : 1
        if let side { rumbleNode?.pan = side == .left ? -0.9 : 0.9 }
    }

    func honk() {
        guard let player = hornPlayer, let buffer = hornBuffer, !state.muted else {
            state.hornSeconds = 0.7
            return
        }
        player.stop()
        player.volume = state.volume * 0.55
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }
    func crash() { state.crashSeconds = 1.5 }
    /// Mutes or unmutes everything at once, recordings included (pause, results screen).
    func setMuted(_ muted: Bool) {
        state.muted = muted
        sampled?.update(rpm: state.rpm, load: state.load, running: state.engineRunning, volume: muted ? 0 : state.volume)
        if muted {
            for (_, loop) in weatherLoops { loop.player.volume = 0 }
            for (_, loop) in ambienceLoops { loop.player.volume = 0 }
        } else {
            updateWeatherVolumes()
        }
    }

    func thunder() {
        guard let shot = thunderShot, !state.muted else {
            state.thunderSeconds = 4
            return
        }
        shot.player.stop()
        shot.player.volume = state.volume * 0.9
        shot.player.scheduleBuffer(shot.buffer, at: nil)
        shot.player.play()
    }

    func setWeather(_ weather: Weather) {
        self.weather = weather
        guard hasWeatherRecordings, engine.isRunning else {
            // No recordings (or not started yet): the synthesized rain.
            state.rain = weather == .storm ? 1 : (weather == .rain ? 0.6 : 0)
            return
        }
        state.rain = 0
        for (_, loop) in weatherLoops { loop.player.stop(); loop.player.volume = 0 }
        guard weather != .clear else { return }
        let rain = weather == .storm ? "weather_rain_storm" : "weather_rain_light"
        for name in [rain, "weather_wipers", "weather_wet_tires"] {
            guard let loop = weatherLoops[name] else { continue }
            loop.player.scheduleBuffer(loop.buffer, at: nil, options: .loops)
            loop.player.play()
        }
        updateWeatherVolumes()
    }

    /// Rain steady, wipers while the engine runs, tyre spray louder with speed.
    private func updateWeatherVolumes() {
        guard hasWeatherRecordings, weather != .clear else { return }
        let on: Float = state.muted ? 0 : state.volume
        let storm = weather == .storm
        weatherLoops[storm ? "weather_rain_storm" : "weather_rain_light"]?.player.volume = on * (storm ? 0.85 : 0.6)
        weatherLoops["weather_wipers"]?.player.volume = (state.engineRunning || state.cranking) ? on * 0.45 : 0
        weatherLoops["weather_wet_tires"]?.player.volume = on * min(1, state.speed / 20) * (storm ? 0.8 : 0.6)
    }
    func policeRadio() { state.crackleSeconds = 0.6 }
    func oncomingCarHorn() { state.carHornSeconds = 0.9 }

    /// Lane guidance follows the lane you mean to be in (your lane, or the passing lane after signalling).
    func setLaneGuidance(offset: Double) {
        state.laneOffset = Float(offset)
        laneNode?.pan = Float(max(-1, min(1, offset / DrivingSession.rumbleOffset)))
    }

    /// Places each nearby vehicle in the stereo field, louder when close, pitched up while approaching.
    func updateTraffic(_ sounds: [TrafficSound]) {
        // Keep vehicles in the slots they already had, so sounds don't jump between voices.
        var free = Array(0..<4)
        var assignment: [Int: TrafficSound] = [:]
        for (slot, id) in trafficSlots.enumerated() {
            if let id, let s = sounds.first(where: { $0.id == id }) {
                assignment[slot] = s
                free.removeAll { $0 == slot }
            }
        }
        for s in sounds where !assignment.values.contains(where: { $0.id == s.id }) {
            guard let slot = free.first else { break }
            free.removeFirst()
            assignment[slot] = s
        }
        for slot in 0..<4 {
            guard let s = assignment[slot] else {
                trafficSlots[slot] = nil
                state.trafficGain[slot] = 0
                continue
            }
            trafficSlots[slot] = s.id
            let d = max(3, (s.distance * s.distance + s.lateral * s.lateral).squareRoot())
            state.trafficGain[slot] = Float((s.kind == .truck ? 1.3 : 1.0) / (1 + pow(d / 22, 2)))
            state.trafficPitch[slot] = Float(min(1.25, max(0.8, 343 / (343 - s.closingSpeed))))
            state.trafficSpeed[slot] = Float(abs(s.closingSpeed))
            state.trafficIsTruck[slot] = s.kind == .truck
            state.trafficBehind[slot] = s.distance < -4
            if trafficNodes.indices.contains(slot) { trafficNodes[slot].pan = Float(max(-1, min(1, s.lateral / max(5, abs(s.distance)) * 1.5))) }
        }
    }
    func gearShift() { state.shiftSeconds = 0.25 }
}
