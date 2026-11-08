import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Synth } from '../src/app/synth.js';

const rms = (a) => Math.sqrt(a.reduce((s, x) => s + x * x, 0) / a.length);

function render(synth, seconds) {
  const n = Math.round(synth.sampleRate * seconds);
  const l = new Float32Array(n);
  const r = new Float32Array(n);
  synth.render(l, r, n);
  return { l, r };
}

test('silent when nothing is happening', () => {
  const s = new Synth(48000);
  const { l, r } = render(s, 0.2);
  assert.equal(rms(l), 0);
  assert.equal(rms(r), 0);
});

test('a running engine makes sound, without NaN or clipping', () => {
  const s = new Synth(48000);
  s.set({ engineRunning: true, rpm: 1200, load: 0.6, speed: 15 });
  const { l } = render(s, 1);
  assert.ok(rms(l) > 0.01, `rms ${rms(l)}`);
  assert.ok(l.every((x) => Number.isFinite(x) && Math.abs(x) <= 1));
});

test('lane beeps play in the ear the truck drifts toward', () => {
  const s = new Synth(48000);
  s.set({ speed: 10, laneOffset: 0.8, lanePan: 0.9 });
  s.state.speed = 10;
  s.road.speed = 0; // isolate the beeps from the tyre roar
  s.set({ speed: 10 });
  const { l, r } = render(s, 1);
  // The road roar is in both ears equally; the beep tips the balance right.
  assert.ok(rms(r) > rms(l) * 1.2, `left ${rms(l)} right ${rms(r)}`);
});

test('one-shot effects play and end', () => {
  const s = new Synth(48000);
  s.trigger('crash');
  const a = render(s, 0.5);
  assert.ok(rms(a.l) > 0.05);
  render(s, 1.2);
  const b = render(s, 0.2);
  assert.equal(rms(b.l), 0);
});
