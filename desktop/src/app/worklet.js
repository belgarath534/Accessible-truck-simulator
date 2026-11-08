// The real-time audio thread: renders the synthesizer.
import { Synth } from './synth.js';

class TruckSynthProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.synth = new Synth(sampleRate);
    this.port.onmessage = (e) => {
      const { set, trigger } = e.data;
      if (set) this.synth.set(set);
      if (trigger) this.synth.trigger(trigger);
    };
  }

  process(_inputs, outputs) {
    const out = outputs[0];
    const left = out[0];
    const right = out[1] ?? out[0];
    this.synth.render(left, right, left.length);
    return true;
  }
}

registerProcessor('truck-synth', TruckSynthProcessor);
