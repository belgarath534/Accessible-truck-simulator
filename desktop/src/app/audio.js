// All game audio: the synthesizer (in an AudioWorklet) plus recorded engine loops and one-shot sounds.
// The same design as AudioSynth.swift and SampledEngine.swift on iPhone.

import { C } from '../sim/session.js';

const LOOPS = [
  ['engine_idle', 600],
  ['engine_low', 1000],
  ['engine_mid', 1400],
  ['engine_high', 1850],
];
const ONE_SHOTS = ['engine_start', 'engine_stop', 'air_brake', 'horn'];

export class GameAudio {
  constructor() {
    this.ctx = null;
    this.node = null;
    this.buffers = new Map();
    this.layers = [];
    this.sampledAmp = 0;
    this.volume = 0.8;
    this.muted = false;
    this.useSampled = false;
    this.trafficSlots = [null, null, null, null];
    this.pending = {};
  }

  /** Creates the audio graph and loads the recordings. Safe to call more than once. */
  async init() {
    if (this.ctx) return;
    this.ctx = new AudioContext({ latencyHint: 'interactive' });
    this.master = this.ctx.createGain();
    this.master.connect(this.ctx.destination);
    await this.ctx.audioWorklet.addModule(new URL('./worklet.js', import.meta.url));
    this.node = new AudioWorkletNode(this.ctx, 'truck-synth', { numberOfInputs: 0, outputChannelCount: [2] });
    this.node.connect(this.master);
    await Promise.all([...LOOPS.map(([n]) => n), ...ONE_SHOTS].map((n) => this.load(n)));
  }

  async load(name) {
    try {
      const res = await fetch(new URL(`../sounds/${name}.wav`, import.meta.url));
      if (!res.ok) return;
      this.buffers.set(name, await this.ctx.decodeAudioData(await res.arrayBuffer()));
    } catch {
      // Missing recordings just fall back to the synthesizer.
    }
  }

  set(values) {
    Object.assign(this.pending, values);
  }

  trigger(name) {
    this.node?.port.postMessage({ trigger: name });
  }

  /** Sends this frame's changes to the audio thread. Call once per frame. */
  flush() {
    if (!this.node) return;
    this.node.port.postMessage({ set: this.pending });
    this.pending = {};
  }

  /** Starts the sounds for one drive, with this truck's engine voice. */
  start(sound) {
    if (!this.ctx) return;
    this.ctx.resume();
    this.useSampled = !!sound.recorded && this.buffers.has('engine_idle');
    this.set({
      pitch: sound.pitch, roughness: sound.roughness, turbo: sound.turbo, bark: sound.bark, lope: sound.lope,
      useSampledEngine: this.useSampled, hasStartSample: this.buffers.has('engine_start'), muted: false,
      volume: this.volume,
    });
    this.stopLoops();
    if (this.useSampled) {
      for (const [name, rpm] of LOOPS) {
        const buffer = this.buffers.get(name);
        if (!buffer) continue;
        const source = this.ctx.createBufferSource();
        source.buffer = buffer;
        source.loop = true;
        const gain = this.ctx.createGain();
        gain.gain.value = 0;
        source.connect(gain).connect(this.master);
        source.start();
        this.layers.push({ source, gain, rpm });
      }
    }
    this.flush();
  }

  stop() {
    this.stopLoops();
    this.set({
      engineRunning: false, cranking: false, speed: 0, rumble: 0, signalOn: false, pumping: false, siren: false,
      beaconDistance: -1000, muted: true, traffic: [0, 1, 2, 3].map(() => ({ gain: 0 })),
    });
    this.flush();
  }

  stopLoops() {
    for (const l of this.layers) {
      try { l.source.stop(); } catch { /* already stopped */ }
      l.source.disconnect();
    }
    this.layers = [];
    this.sampledAmp = 0;
  }

  setVolume(v) {
    this.volume = v;
    this.set({ volume: v });
  }

  setMuted(m) {
    this.muted = m;
    this.set({ muted: m });
  }

  /** Every frame: the truck's state drives the engine and road sounds. */
  update(truck, spec) {
    const running = truck.engine === 'running';
    this.set({
      rpm: truck.rpm, load: truck.engineLoad, engineRunning: running, cranking: truck.engine === 'starting',
      cylinders: spec.cylinders, maxRPM: spec.maxRPM, speed: truck.speed, signalOn: truck.signal !== 'off',
    });
    this.updateSampled(truck.rpm, truck.engineLoad, running);
  }

  /** Recorded loops: equal-power crossfade between the two nearest recordings, sped up to follow RPM. */
  updateSampled(rpm, load, running) {
    if (!this.layers.length) return;
    this.sampledAmp += ((running ? 1 : 0) - this.sampledAmp) * (running ? 0.15 : 0.06);
    const sorted = [...this.layers].sort((a, b) => a.rpm - b.rpm);
    const r = Math.max(rpm, 1);
    const gains = sorted.map(() => 0);
    if (r <= sorted[0].rpm) gains[0] = 1;
    else if (r >= sorted.at(-1).rpm) gains[gains.length - 1] = 1;
    else {
      for (let i = 0; i < sorted.length - 1; i++) {
        if (r >= sorted[i].rpm && r <= sorted[i + 1].rpm) {
          const t = (r - sorted[i].rpm) / (sorted[i + 1].rpm - sorted[i].rpm);
          gains[i] = Math.cos((t * Math.PI) / 2);
          gains[i + 1] = Math.sin((t * Math.PI) / 2);
          break;
        }
      }
    }
    const level = (0.6 + 0.4 * load) * this.sampledAmp * (this.muted ? 0 : this.volume);
    const now = this.ctx.currentTime;
    sorted.forEach((layer, i) => {
      layer.source.playbackRate.setTargetAtTime(Math.min(2, Math.max(0.5, r / layer.rpm)), now, 0.02);
      layer.gain.gain.setTargetAtTime(gains[i] * level, now, 0.02);
    });
  }

  /** Lane guidance follows the lane you mean to be in. */
  setLaneGuidance(offset) {
    this.set({ laneOffset: offset, lanePan: Math.max(-1, Math.min(1, offset / C.rumbleOffset)) });
  }

  setLaneTone(on) {
    this.set({ laneToneEnabled: on });
  }

  setRumble(side) {
    this.set(side ? { rumble: 1, rumblePan: side === 'left' ? -0.9 : 0.9 } : { rumble: 0 });
  }

  /** Places each nearby vehicle in the stereo field, louder when close, pitched up while approaching. */
  updateTraffic(sounds) {
    const free = [0, 1, 2, 3];
    const assignment = new Map();
    this.trafficSlots.forEach((id, slot) => {
      const s = id != null && sounds.find((x) => x.id === id);
      if (s) {
        assignment.set(slot, s);
        free.splice(free.indexOf(slot), 1);
      }
    });
    for (const s of sounds) {
      if ([...assignment.values()].some((a) => a.id === s.id)) continue;
      if (!free.length) break;
      assignment.set(free.shift(), s);
    }
    const traffic = [0, 1, 2, 3].map((slot) => {
      const s = assignment.get(slot);
      if (!s) {
        this.trafficSlots[slot] = null;
        return { gain: 0 };
      }
      this.trafficSlots[slot] = s.id;
      const d = Math.max(3, Math.hypot(s.distance, s.lateral));
      return {
        gain: (s.kind === 'truck' ? 1.3 : 1) / (1 + (d / 22) ** 2),
        pitch: Math.min(1.25, Math.max(0.8, 343 / (343 - s.closingSpeed))),
        speed: Math.abs(s.closingSpeed),
        truck: s.kind === 'truck',
        behind: s.distance < -4,
        pan: Math.max(-1, Math.min(1, (s.lateral / Math.max(5, Math.abs(s.distance))) * 1.5)),
      };
    });
    this.set({ traffic });
  }

  play(name, volume = 1) {
    const buffer = this.buffers.get(name);
    if (!buffer || !this.ctx || this.muted) return false;
    const source = this.ctx.createBufferSource();
    source.buffer = buffer;
    const gain = this.ctx.createGain();
    gain.gain.value = volume * this.volume;
    source.connect(gain).connect(this.master);
    source.start();
    return true;
  }

  engineStarting() { this.play('engine_start'); }
  engineStopped() { this.play('engine_stop'); }
  airBrake() { this.play('air_brake', 0.8); }
  honk() { if (!this.play('horn', 0.55)) this.trigger('horn'); }
  gearShift() { this.trigger('shift'); }
  crash() { this.trigger('crash'); }
  policeRadio() { this.trigger('policeRadio'); }
  oncomingCarHorn() { this.trigger('carHorn'); }
}
