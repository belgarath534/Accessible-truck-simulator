// The truck engine voice: each truck gets its own character from a handful of settings.
//
//   cylinders  firing rate (4 buzz, 6 smooth, 8 burble, 12 scream)
//   pitch      overall pitch: below 1 bigger and deeper
//   tilt       brightness: low = raspy and bright, high = dull and muffled
//   formant    exhaust resonance in Hz, and formantQ how sharp it is (boomy, throaty, nasal)
//   uneven     uneven firing: 0 even, 1 a lumpy V8 burble
//   sub        low crankshaft rumble
//   tone       the top of the sound in Hz: low = muffled and deep, high = sharp and raspy
//   roughness, turbo, bark, lope, whine  clatter, turbo whistle, exhaust bark, lumpy idle, gear whine
//
// Shared by the Windows version (this file) and mirrored in the iPhone version (AudioSynth.swift).

const TWO_PI = Math.PI * 2;
const UNEVEN = [0.25, -0.35, 0.3, -0.2, 0.15, -0.4, 0.35, -0.1];

class Noise {
  constructor(seed) { this.seed = seed >>> 0 || 1; }
  next() {
    let x = this.seed;
    x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0;
    this.seed = x;
    return (x / 4294967295) * 2 - 1;
  }
}

/** A band-pass filter (constant 0 dB peak), for the exhaust resonance. */
class BandPass {
  constructor() { this.x1 = 0; this.x2 = 0; this.y1 = 0; this.y2 = 0; this.set(48000, 300, 2); }
  set(sr, freq, q) {
    const w = (TWO_PI * Math.min(freq, sr * 0.45)) / sr;
    const alpha = Math.sin(w) / (2 * q);
    const a0 = 1 + alpha;
    this.b0 = alpha / a0; this.b2 = -alpha / a0;
    this.a1 = (-2 * Math.cos(w)) / a0; this.a2 = (1 - alpha) / a0;
  }
  process(x) {
    const y = this.b0 * x + this.b2 * this.x2 - this.a1 * this.y1 - this.a2 * this.y2;
    this.x2 = this.x1; this.x1 = x; this.y2 = this.y1; this.y1 = y;
    return y;
  }
}

export const DEFAULT_VOICE = {
  cylinders: 6, pitch: 1, tilt: 1, formant: 300, formantQ: 2, uneven: 0, sub: 0.3,
  roughness: 0.3, turbo: 0.3, bark: 0.2, lope: 0.1, whine: 0, electric: false, tone: 3000,
};

export class EngineVoice {
  constructor(sampleRate, voice = DEFAULT_VOICE, seed = 0x1234567) {
    this.sr = sampleRate;
    this.noise = new Noise(seed);
    this.bp = new BandPass();
    this.setVoice(voice);
    this.phase = 0; this.crank = 0; this.halfCrank = 0; this.turboPh = 0; this.whinePh = 0;
    this.k = 0; this.cycleAmp = 1; this.rpm = 0; this.load = 0; this.amp = 0; this.lp = 0; this.lp2 = 0;
    this.motor = 0; this.motor2 = 0; this.inverter = 0; this.hum = 0; this.counter = 0;
    this.tone1 = 0; this.tone2 = 0;
  }

  setVoice(v) {
    this.v = { ...DEFAULT_VOICE, ...v };
    // Harmonic weights for the brightness, normalised.
    this.weights = [];
    let sum = 0;
    for (let h = 1; h <= 10; h++) { const w = h ** -this.v.tilt; this.weights.push(w); sum += w; }
    this.weights = this.weights.map((w) => w / sum * 1.6);
  }

  /** One sample. rpm, load 0...1, on = running (or cranking), maxRPM for the turbo and the electric whine. */
  sample(rpmIn, loadIn, on, maxRPM = 2100) {
    const v = this.v;
    const sr = this.sr;
    this.rpm += (rpmIn - this.rpm) * 0.0008;
    this.load += (loadIn - this.load) * 0.0006;
    const target = on ? 1 : 0;
    this.amp += (target - this.amp) * (target > this.amp ? 0.002 : 0.00015);
    if (this.amp < 1e-5 && !on) return 0;
    const load = this.load;

    if (v.electric) {
      const rpm = Math.max(this.rpm, 0);
      const f = (rpm / 60) * 6;
      this.motor = (this.motor + f / sr) % 1;
      this.motor2 = (this.motor2 + (f * 2.5) / sr) % 1;
      this.inverter = (this.inverter + (1900 + rpm * 0.35) / sr) % 1;
      this.hum = (this.hum + 100 / sr) % 1;
      const spin = Math.min(1, (rpm / maxRPM) * 1.6);
      let e = (Math.sin(TWO_PI * this.motor) * 0.32 + Math.sin(TWO_PI * this.motor2) * 0.12) * spin * (0.55 + 0.45 * load);
      e += Math.sin(TWO_PI * this.inverter) * 0.035 * load + Math.sin(TWO_PI * this.hum) * 0.05;
      return e * this.amp * 0.9;
    }

    const rpm = Math.max(this.rpm, 1);
    // Re-tune the exhaust resonance now and then (it follows the revs a little).
    if ((this.counter++ & 63) === 0) {
      this.bp.set(sr, v.formant * v.pitch * (0.85 + 0.35 * Math.min(1, rpm / maxRPM)), v.formantQ);
    }
    const fire = (rpm / 60) * (v.cylinders / 2) * v.pitch;
    this.phase += fire / sr;
    if (this.phase >= 1) {
      this.phase -= 1;
      this.k = (this.k + 1) % 8;
      // Uneven firing (V8 burble) and rough combustion: each firing a little louder or softer.
      this.cycleAmp = 1 + v.uneven * UNEVEN[this.k] * 1.6 + v.roughness * this.noise.next() * 0.4;
    }
    this.crank = (this.crank + ((rpm / 60) * v.pitch) / sr) % 1;
    this.halfCrank = (this.halfCrank + ((rpm / 120) * v.pitch) / sr) % 1;

    const p = this.phase;
    let harm = 0;
    for (let h = 0; h < 10; h++) harm += Math.sin(TWO_PI * (h + 1) * p) * this.weights[h];
    // Each firing is a punch that fades.
    const punch = Math.exp(-p * (2.5 + 3 * load));
    let body = harm * (0.55 + 0.45 * punch) * this.cycleAmp;
    body += Math.sin(TWO_PI * this.crank) * v.sub * 0.6;

    // Combustion clatter.
    const c = 1 - Math.exp((-TWO_PI * (500 + 2600 * load + rpm * 0.4)) / sr);
    this.lp += (this.noise.next() * Math.exp(-p * 9) - this.lp) * c;
    this.lp2 += (this.lp - this.lp2) * c;
    const knock = this.lp2 * (0.8 + 1.4 * load) * (0.3 + 1.2 * v.roughness) * this.cycleAmp;

    let s = body * (0.3 + 0.25 * load) + knock;
    // The exhaust: mostly the resonance, a little of the raw sound, then the truck's tone (muffled or sharp).
    s = s * 0.3 + this.bp.process(s) * 2.4;
    const tc = 1 - Math.exp((-TWO_PI * v.tone * (0.7 + 0.5 * load)) / sr);
    this.tone1 += (s - this.tone1) * tc;
    this.tone2 += (this.tone1 - this.tone2) * tc;
    s = this.tone2 * 1.3;

    this.turboPh = (this.turboPh + (1600 + rpm * 1.3) / sr) % 1;
    s += Math.sin(TWO_PI * this.turboPh) * 0.07 * v.turbo * (0.3 + 0.7 * load) * (rpm / maxRPM);
    if (v.whine > 0) {
      this.whinePh = (this.whinePh + (rpm * 0.62) / sr) % 1;
      s += Math.sin(TWO_PI * this.whinePh) * 0.05 * v.whine * Math.min(1, rpm / 1200);
    }
    const nearIdle = Math.max(0, 1 - (rpm - 600) / 500);
    s *= 1 + v.lope * 0.5 * nearIdle * Math.sin(TWO_PI * this.halfCrank);
    if (v.bark > 0) {
      const drive = 1 + v.bark * 3;
      s = Math.tanh(s * drive) / (0.6 + 0.4 * drive);
    }
    return s * this.amp * 0.7;
  }
}

/** Each truck's voice. */
export const VOICES = {
  farm_runner: { cylinders: 4, pitch: 1.45, tilt: 0.75, formant: 620, formantQ: 3, uneven: 0.1, sub: 0.1, roughness: 0.65, turbo: 0, bark: 0.4, lope: 0.3, tone: 3500 },
  workhorse: { cylinders: 6, pitch: 1.05, tilt: 1.0, formant: 300, formantQ: 2, uneven: 0.15, sub: 0.35, roughness: 0.95, turbo: 0, bark: 0.45, lope: 0.75, tone: 2400 },
  city_hauler: { cylinders: 4, pitch: 1.35, tilt: 0.8, formant: 950, formantQ: 4, uneven: 0, sub: 0.1, roughness: 0.25, turbo: 0.8, bark: 0.2, lope: 0.05, whine: 0.3, tone: 5500 },
  mountain_goat: { cylinders: 6, pitch: 0.95, tilt: 1.1, formant: 210, formantQ: 5, uneven: 0.2, sub: 0.4, roughness: 0.55, turbo: 0.4, bark: 0.9, lope: 0.4, tone: 1800 },
  road_king: { cylinders: 8, pitch: 0.82, tilt: 1.15, formant: 160, formantQ: 3, uneven: 0.6, sub: 0.6, roughness: 0.35, turbo: 0.9, bark: 0.6, lope: 0.35, tone: 1300 },
  highway_star: { cylinders: 6, pitch: 0.92, tilt: 1.45, formant: 420, formantQ: 1.5, uneven: 0, sub: 0.25, roughness: 0.1, turbo: 1, bark: 0.25, lope: 0.05, whine: 0.2, tone: 1600 },
  long_hauler: { cylinders: 6, pitch: 0.66, tilt: 1.75, formant: 110, formantQ: 2, uneven: 0.05, sub: 0.85, roughness: 0.15, turbo: 0.35, bark: 0.2, lope: 0.15, tone: 550 },
  iron_bull: { cylinders: 8, pitch: 0.72, tilt: 1.05, formant: 140, formantQ: 6, uneven: 0.95, sub: 0.7, roughness: 0.5, turbo: 0.7, bark: 1, lope: 0.75, tone: 1500 },
  titan: { cylinders: 12, pitch: 0.82, tilt: 0.55, formant: 1150, formantQ: 3, uneven: 0, sub: 0.35, roughness: 0.15, turbo: 0.5, bark: 0.75, lope: 0.1, tone: 7000 },
  volt: { electric: true },
};
