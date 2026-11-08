// All synthesized game sound, rendered sample by sample. A port of AudioSynth.swift.
// Runs inside an AudioWorklet (real-time audio thread); also importable in Node for tests.
//
// The game sets `state` about 60 times a second; one-shot sounds are started with `trigger(name)`.

const TWO_PI = Math.PI * 2;

function onePole(cutoff, sampleRate) {
  return 1 - Math.exp((-TWO_PI * cutoff) / sampleRate);
}

/** Fast xorshift noise in -1...1. */
class Noise {
  constructor(seed = 0x12345678) {
    this.seed = seed >>> 0 || 1;
  }
  next() {
    let x = this.seed;
    x ^= x << 13;
    x >>>= 0;
    x ^= x >>> 17;
    x ^= x << 5;
    x >>>= 0;
    this.seed = x;
    return (x / 4294967295) * 2 - 1;
  }
}

/** Equal-power stereo gains for a pan in -1 (left) ... 1 (right). */
function panGains(pan) {
  const a = ((Math.max(-1, Math.min(1, pan)) + 1) * Math.PI) / 4;
  return [Math.cos(a), Math.sin(a)];
}

export function defaultState() {
  return {
    rpm: 0,
    load: 0,
    engineRunning: false,
    cranking: false,
    cylinders: 6,
    maxRPM: 2100,
    speed: 0,
    rumble: 0,
    rumblePan: 0.9,
    laneOffset: 0,
    lanePan: 0,
    laneToneEnabled: true,
    signalOn: false,
    pumping: false,
    siren: false,
    beaconDistance: -1000,
    volume: 0.8,
    muted: false,
    useSampledEngine: false,
    hasStartSample: false,
    pitch: 1,
    roughness: 0.3,
    turbo: 0.3,
    bark: 0.2,
    lope: 0.1,
    // Traffic: up to four vehicles.
    traffic: [0, 1, 2, 3].map(() => ({ gain: 0, pitch: 1, speed: 0, truck: false, behind: false, pan: 0 })),
  };
}

/** A diesel engine built from scratch: firing harmonics, combustion clatter and a turbo whistle. */
class EngineVoice {
  constructor(state, sr) {
    this.s = state;
    this.sr = sr;
    this.phase = 0; this.crank = 0; this.halfCrank = 0; this.turbo = 0; this.starter = 0;
    this.cycleAmp = 1; this.rpm = 0; this.load = 0; this.amp = 0; this.lp = 0; this.lp2 = 0;
    this.noise = new Noise(0x1234567);
  }

  sample() {
    const s = this.s;
    const sr = this.sr;
    const synthOn = s.useSampledEngine ? s.cranking && !s.hasStartSample : s.engineRunning || s.cranking;
    const targetAmp = synthOn && !s.muted ? 1 : 0;
    this.rpm += (s.rpm - this.rpm) * 0.0008;
    this.load += (s.load - this.load) * 0.0006;
    this.amp += (targetAmp - this.amp) * (targetAmp > this.amp ? 0.002 : 0.00015);
    if (this.amp < 1e-5 && targetAmp === 0) return 0;
    const rpm = Math.max(this.rpm, 1);
    const load = this.load;

    const fire = (rpm / 60) * (s.cylinders / 2) * s.pitch;
    this.phase += fire / sr;
    if (this.phase >= 1) {
      this.phase -= 1;
      // Rough engines fire unevenly.
      this.cycleAmp = 1 + s.roughness * this.noise.next() * 0.4;
    }
    this.crank += ((rpm / 60) * s.pitch) / sr;
    if (this.crank >= 1) this.crank -= 1;
    this.halfCrank += ((rpm / 120) * s.pitch) / sr;
    if (this.halfCrank >= 1) this.halfCrank -= 1;

    const p = this.phase;
    let body = Math.sin(TWO_PI * p) * 0.45 + Math.sin(TWO_PI * 2 * p) * 0.3 + Math.sin(TWO_PI * 3 * p) * 0.18;
    body += Math.sin(TWO_PI * 4 * p) * (0.08 + 0.06 * load);
    body += Math.sin(TWO_PI * this.crank) * 0.25 * (1.6 - 0.6 * s.pitch);
    body *= this.cycleAmp;

    // Combustion clatter: a noise burst at each firing, brighter under load.
    const env = Math.exp(-p * 9);
    const c = onePole(500 + 2600 * load + rpm * 0.4, sr);
    this.lp += (this.noise.next() * env - this.lp) * c;
    this.lp2 += (this.lp - this.lp2) * c;
    const knock = this.lp2 * (0.8 + 1.4 * load) * (0.4 + 1.2 * s.roughness) * this.cycleAmp;

    this.turbo += (1600 + rpm * 1.3) / sr;
    if (this.turbo >= 1) this.turbo -= 1;
    const whistle = Math.sin(TWO_PI * this.turbo) * 0.06 * s.turbo * (0.3 + 0.7 * load) * (rpm / s.maxRPM);

    let out = body * (0.28 + 0.22 * load) + knock + whistle;
    const nearIdle = Math.max(0, 1 - (rpm - 600) / 500);
    out *= 1 + s.lope * 0.4 * nearIdle * Math.sin(TWO_PI * this.halfCrank);
    if (s.bark > 0) {
      const drive = 1 + s.bark * 2.5;
      out = Math.tanh(out * drive) / (0.6 + 0.4 * drive);
    }
    if (s.cranking) {
      this.starter += 110 / sr;
      if (this.starter >= 1) this.starter -= 1;
      out += (this.starter * 2 - 1) * 0.1 + this.noise.next() * 0.03;
    }
    return out * this.amp * s.volume * 0.7;
  }
}

/** Tyre roar and wind, rising with speed. */
class RoadVoice {
  constructor(state, sr) {
    this.s = state; this.sr = sr; this.lp1 = 0; this.lp2 = 0; this.speed = 0; this.noise = new Noise(0x9e3779b9);
  }
  sample() {
    const s = this.s;
    this.speed += (s.speed - this.speed) * 0.001;
    if (this.speed < 0.01 || s.muted) return 0;
    const level = Math.min(1, this.speed / 25);
    const c = onePole(200 + this.speed * 25, this.sr);
    this.lp1 += (this.noise.next() - this.lp1) * c;
    this.lp2 += (this.lp1 - this.lp2) * c;
    return this.lp2 * level * 0.9 * s.volume;
  }
}

/** Rumble strip: rapid thumps whose rate follows speed. */
class RumbleVoice {
  constructor(state, sr) {
    this.s = state; this.sr = sr; this.phase = 0; this.amp = 0; this.lp = 0; this.noise = new Noise(0xdeadbeef);
    this.c = onePole(400, sr);
  }
  sample() {
    const s = this.s;
    const target = s.muted ? 0 : s.rumble * Math.min(1, s.speed / 4);
    this.amp += (target - this.amp) * 0.003;
    if (this.amp < 1e-5) return 0;
    const rate = Math.max(s.speed, 0.5) / 0.3;
    this.phase += rate / this.sr;
    if (this.phase >= 1) this.phase -= 1;
    this.lp += (this.noise.next() - this.lp) * this.c;
    const thump = (this.lp * 3 + Math.sin(TWO_PI * this.phase)) * Math.exp(-this.phase * 5);
    return thump * this.amp * 0.6 * s.volume;
  }
}

/** Lane guidance: soft beeps in the ear the truck is drifting toward, faster and higher the further off centre. */
class LaneVoice {
  constructor(state, sr) {
    this.s = state; this.sr = sr; this.phase = 0; this.osc = 0;
  }
  sample() {
    const s = this.s;
    const deviation = Math.abs(s.laneOffset) - 0.25;
    if (!(s.laneToneEnabled && deviation > 0 && s.speed > 1 && !s.muted)) {
      this.phase = 0;
      return 0;
    }
    const rate = 1.5 + deviation * 10;
    const freq = 600 + deviation * 700;
    this.phase += rate / this.sr;
    if (this.phase >= 1) this.phase -= 1;
    const t = this.phase / rate;
    this.osc += freq / this.sr;
    if (this.osc >= 1) this.osc -= 1;
    return t < 0.045 ? Math.sin(TWO_PI * this.osc) * 0.16 * (1 - t / 0.045) * s.volume : 0;
  }
}

/** One nearby vehicle: tyre roar and engine hum with Doppler, muffled once it's behind you. */
class TrafficVoice {
  constructor(state, sr, slot) {
    this.s = state; this.sr = sr; this.slot = slot;
    this.gain = 0; this.lp1 = 0; this.lp2 = 0; this.hum = 0; this.hum2 = 0; this.muffle = 0;
    this.noise = new Noise(0x5eed0000 + slot * 7919);
  }
  sample() {
    const s = this.s;
    const v = s.traffic[this.slot];
    const targetGain = s.muted ? 0 : v.gain;
    this.gain += (targetGain - this.gain) * 0.002;
    if (this.gain < 1e-5) return 0;
    this.muffle += ((v.behind ? 1 : 0) - this.muffle) * 0.0005;
    const c = onePole((300 + v.speed * 40) * v.pitch, this.sr);
    this.lp1 += (this.noise.next() - this.lp1) * c;
    this.lp2 += (this.lp1 - this.lp2) * c * (1 - 0.7 * this.muffle);
    const humFreq = (v.truck ? 52 : 95) * v.pitch * (0.7 + v.speed / 40);
    this.hum += humFreq / this.sr;
    if (this.hum >= 1) this.hum -= 1;
    this.hum2 += (humFreq * 2.01) / this.sr;
    if (this.hum2 >= 1) this.hum2 -= 1;
    const engine = Math.sin(TWO_PI * this.hum) * (v.truck ? 0.35 : 0.2) + Math.sin(TWO_PI * this.hum2) * 0.1;
    return (this.lp2 * 1.6 + engine) * this.gain * s.volume;
  }
}

/** One-shot effects and alerts: signal clicks, synth horn, shifts, pump, beacon, car horn, siren, radio, crash. */
class FXVoice {
  constructor(state, sr) {
    this.s = state; this.sr = sr; this.dt = 1 / sr;
    this.signalPhase = 0; this.hornA = 0; this.hornB = 0; this.clickOsc = 0; this.lp = 0;
    this.pumpPhase = 0; this.pumpLP = 0;
    this.sirenTime = 0; this.sirenPhase = 0; this.sirenAmp = 0;
    this.beaconClock = 0; this.beaconOsc = 0;
    this.carHornA = 0; this.carHornB = 0; this.carHornLP = 0;
    this.crackleHP = 0; this.crackleLP = 0; this.crackleTone = 0;
    this.hornSeconds = 0; this.shiftSeconds = 0; this.crashSeconds = 0; this.carHornSeconds = 0; this.crackleSeconds = 0;
    this.noise = new Noise(0x0badf00d);
  }

  trigger(name) {
    if (name === 'horn') this.hornSeconds = 0.7;
    else if (name === 'shift') this.shiftSeconds = 0.25;
    else if (name === 'crash') this.crashSeconds = 1.5;
    else if (name === 'carHorn') this.carHornSeconds = 0.9;
    else if (name === 'policeRadio') this.crackleSeconds = 0.6;
  }

  sample() {
    const s = this.s;
    const sr = this.sr;
    const dt = this.dt;
    let out = 0;
    if (s.signalOn) {
      this.signalPhase += dt / 0.8;
      if (this.signalPhase >= 1) this.signalPhase -= 1;
      const half = this.signalPhase < 0.5;
      const t = (half ? this.signalPhase : this.signalPhase - 0.5) * 0.8;
      if (t < 0.015) {
        this.clickOsc += (half ? 2200 : 1600) / sr;
        if (this.clickOsc >= 1) this.clickOsc -= 1;
        out += Math.sin(TWO_PI * this.clickOsc) * 0.35 * (1 - t / 0.015);
      }
    } else {
      this.signalPhase = 0;
    }
    if (this.hornSeconds > 0) {
      this.hornSeconds -= dt;
      this.hornA += 185 / sr; if (this.hornA >= 1) this.hornA -= 1;
      this.hornB += 233 / sr; if (this.hornB >= 1) this.hornB -= 1;
      const tone = (ph) => Math.sin(TWO_PI * ph) + Math.sin(TWO_PI * ph * 3) * 0.3 + Math.sin(TWO_PI * ph * 5) * 0.15;
      out += (tone(this.hornA) + tone(this.hornB)) * 0.22 * Math.min(1, this.hornSeconds * 20);
    }
    if (this.shiftSeconds > 0) {
      this.shiftSeconds -= dt;
      const n = this.noise.next();
      this.lp += (n - this.lp) * 0.2;
      out += (n - this.lp) * 0.25 * (this.shiftSeconds / 0.25);
    }
    if (s.pumping) {
      this.pumpPhase += 118 / sr; if (this.pumpPhase >= 1) this.pumpPhase -= 1;
      this.pumpLP += (this.noise.next() - this.pumpLP) * 0.05;
      out += (Math.sin(TWO_PI * this.pumpPhase) * 0.12 + Math.sin(TWO_PI * this.pumpPhase * 2) * 0.05 + this.pumpLP * 0.5) * 0.8;
    }
    // Drop-off beacon, like a parking sensor.
    const bd = s.beaconDistance;
    if (bd > -999 && !s.muted) {
      const freq = bd < 0 ? 520 : 1040;
      this.beaconOsc += freq / sr; if (this.beaconOsc >= 1) this.beaconOsc -= 1;
      const tone = Math.sin(TWO_PI * this.beaconOsc) * 0.14;
      if (Math.abs(bd) <= 12) {
        out += tone;
      } else {
        const interval = 0.08 + Math.min(1, Math.abs(bd) / 150) * 0.7;
        this.beaconClock += dt; if (this.beaconClock >= interval) this.beaconClock -= interval;
        if (this.beaconClock < 0.06) out += tone * (1 - this.beaconClock / 0.06);
      }
    } else {
      this.beaconClock = 0;
    }
    // An oncoming car's horn: two quick toots.
    if (this.carHornSeconds > 0) {
      this.carHornSeconds -= dt;
      const h = this.carHornSeconds;
      if (h > 0.55 || (h < 0.4 && h > 0.05)) {
        this.carHornA += 415 / sr; if (this.carHornA >= 1) this.carHornA -= 1;
        this.carHornB += 520 / sr; if (this.carHornB >= 1) this.carHornB -= 1;
        const sq = (this.carHornA < 0.5 ? 1 : -1) * 0.5 + (this.carHornB < 0.5 ? 1 : -1) * 0.5;
        this.carHornLP += (sq - this.carHornLP) * 0.25;
        out += this.carHornLP * 0.22;
      }
    }
    // Police siren.
    this.sirenAmp += ((s.siren ? 1 : 0) - this.sirenAmp) * 0.0005;
    if (this.sirenAmp > 0.001) {
      this.sirenTime += dt;
      const sweep = 0.5 - 0.5 * Math.cos((TWO_PI * this.sirenTime) / 3.2);
      this.sirenPhase += (650 + 700 * sweep) / sr; if (this.sirenPhase >= 1) this.sirenPhase -= 1;
      const ph = this.sirenPhase;
      out += (Math.sin(TWO_PI * ph) + 0.35 * Math.sin(TWO_PI * 2 * ph) + 0.15 * Math.sin(TWO_PI * 3 * ph)) * 0.16 * this.sirenAmp;
    } else {
      this.sirenTime = 0;
    }
    // Police radio crackle.
    if (this.crackleSeconds > 0) {
      this.crackleSeconds -= dt;
      const n = this.noise.next();
      this.crackleLP += (n - this.crackleLP) * 0.35;
      this.crackleHP += (this.crackleLP - this.crackleHP) * 0.05;
      const band = (this.crackleLP - this.crackleHP) * (this.noise.next() > 0.6 ? 1.6 : 0.5);
      this.crackleTone += 1150 / sr; if (this.crackleTone >= 1) this.crackleTone -= 1;
      const squelch = this.crackleSeconds > 0.45 ? Math.sin(TWO_PI * this.crackleTone) * 0.12 : 0;
      out += (band * 0.45 + squelch) * Math.min(1, this.crackleSeconds * 8);
    }
    if (this.crashSeconds > 0) {
      this.crashSeconds -= dt;
      const env = this.crashSeconds / 1.5;
      out += this.noise.next() * env * env * 0.9 + Math.sin(TWO_PI * 45 * this.crashSeconds) * env * 0.6;
    }
    return s.muted ? 0 : out * s.volume;
  }
}

export class Synth {
  constructor(sampleRate) {
    this.sampleRate = sampleRate;
    this.state = defaultState();
    const s = this.state;
    this.engine = new EngineVoice(s, sampleRate);
    this.road = new RoadVoice(s, sampleRate);
    this.rumble = new RumbleVoice(s, sampleRate);
    this.lane = new LaneVoice(s, sampleRate);
    this.traffic = [0, 1, 2, 3].map((i) => new TrafficVoice(s, sampleRate, i));
    this.fx = new FXVoice(s, sampleRate);
  }

  set(values) {
    for (const [k, v] of Object.entries(values)) {
      if (k === 'traffic') v.forEach((t, i) => Object.assign(this.state.traffic[i], t));
      else this.state[k] = v;
    }
  }

  trigger(name) {
    this.fx.trigger(name);
  }

  /** Fills left and right buffers (Float32Array) with `frames` samples. */
  render(left, right, frames) {
    const s = this.state;
    const [rL, rR] = panGains(s.rumblePan);
    const [lL, lR] = panGains(s.lanePan);
    const tPans = s.traffic.map((t) => panGains(t.pan));
    for (let i = 0; i < frames; i++) {
      const centre = this.engine.sample() + this.road.sample() + this.fx.sample();
      const rumble = this.rumble.sample();
      const lane = this.lane.sample();
      let l = centre + rumble * rL + lane * lL;
      let r = centre + rumble * rR + lane * lR;
      for (let j = 0; j < 4; j++) {
        const t = this.traffic[j].sample();
        if (t !== 0) {
          l += t * tPans[j][0];
          r += t * tPans[j][1];
        }
      }
      // Gentle limiter so stacked sounds never clip harshly.
      left[i] = Math.tanh(l);
      right[i] = Math.tanh(r);
    }
  }
}
