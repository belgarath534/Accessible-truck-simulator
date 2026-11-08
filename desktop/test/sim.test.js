import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DrivingSession } from '../src/sim/session.js';
import { Road, practiceLoop, straight } from '../src/sim/road.js';
import { practiceGoal } from '../src/sim/trip.js';
import { starter, roadKing, workhorse, catalog, horsepower, withID } from '../src/sim/truck.js';
import { Phrases, Units, money } from '../src/sim/phrases.js';
import { Tutorial } from '../src/sim/tutorial.js';

const DT = 1 / 60;
const run = (s, seconds, input = {}) => {
  const events = [];
  for (let i = 0; i < Math.round(seconds / DT); i++) events.push(...s.step(DT, input));
  return events;
};

test('engine starts after cranking, then idles', () => {
  const s = new DrivingSession({ seed: 1 });
  assert.deepEqual(s.perform({ type: 'toggleEngine' }).map((e) => e.type), ['engineStarting']);
  const events = run(s, 2.5);
  assert.ok(events.some((e) => e.type === 'engineStarted'));
  assert.equal(s.truck.engine, 'running');
  assert.ok(Math.abs(s.truck.rpm - starter.idleRPM) < 50);
});

test('accelerates, shifts up and brakes to a stop', () => {
  const s = new DrivingSession({ road: new Road([straight(50000)]), seed: 1 });
  s.perform({ type: 'toggleEngine' });
  run(s, 2.5);
  const events = run(s, 40, { throttle: 1 });
  assert.ok(s.truck.speed > 15, `speed ${s.truck.speed}`);
  assert.ok(s.truck.gearIndex >= 5);
  assert.ok(events.filter((e) => e.type === 'gearChanged' && e.up).length >= 5);
  assert.ok(s.truck.speed <= starter.speedLimiter + 0.5);
  run(s, 20, { brake: 1 });
  assert.equal(s.truck.speed, 0);
});

test('no throttle while the engine is off gives a hint', () => {
  const s = new DrivingSession({ seed: 1 });
  const events = run(s, 1, { throttle: 1 });
  assert.equal(s.truck.speed, 0);
  assert.equal(events.filter((e) => e.type === 'engineNotRunning').length, 1);
});

/** A driver who only uses what a blind player hears (lane beeps with half a second's reaction, curve calls). */
function crashesOnPracticeLoop(assist) {
  const road = practiceLoop();
  const s = new DrivingSession({ road, goal: practiceGoal(road), assist, seed: 3 });
  s.perform({ type: 'toggleEngine' });
  const heard = new Array(30).fill(0);
  let targetSpeed = 22;
  let t = 0;
  while (!s.summary && t < 3000) {
    const y = s.truck.lateralOffset;
    heard.push(Math.abs(y) > 0.25 ? Math.sign(y) : 0);
    const beep = heard.shift();
    const curve = s.road.nextCurve(s.truck.position, 250);
    if (curve) targetSpeed = curve.advisorySpeed;
    else if (s.road.curvature(s.truck.position) === 0) targetSpeed = 22;
    if (s.remaining != null) targetSpeed = Math.min(targetSpeed, Math.sqrt(4 * Math.max(0, s.remaining)));
    const throttle = s.truck.speed < targetSpeed - 1 ? 0.6 : 0;
    const brake = s.truck.speed > targetSpeed + 1 || (s.remaining ?? 1) <= 0 ? 0.5 : 0;
    s.step(DT, { throttle, brake, steer: -beep * 0.8 });
    t += DT;
  }
  return { crashes: s.stats.crashes, finished: !!s.summary };
}

test('simple handling is drivable by ear and the practice drive finishes', () => {
  const simple = crashesOnPracticeLoop('medium');
  const realistic = crashesOnPracticeLoop('off');
  assert.ok(simple.finished);
  assert.ok(simple.crashes <= 1, `medium assist crashes ${simple.crashes}`);
  assert.ok(simple.crashes < Math.max(realistic.crashes, 1) + 1);
});

test('drifting off the road at speed is a crash, then recovered', () => {
  const s = new DrivingSession({ road: new Road([straight(50000)]), seed: 1 });
  s.perform({ type: 'toggleEngine' });
  run(s, 2.5);
  run(s, 15, { throttle: 1 });
  const events = run(s, 5, { throttle: 1, steer: 1 });
  assert.ok(events.some((e) => e.type === 'crashed' && e.reason.kind === 'leftRoad' && e.reason.side === 'right'));
  assert.ok(events.some((e) => e.type === 'rumbleStrip' && e.side === 'right'));
});

test('curves are announced ahead', () => {
  const s = new DrivingSession({ seed: 1 });
  s.perform({ type: 'toggleEngine' });
  run(s, 2.5);
  const events = run(s, 60, { throttle: 0.6, steer: 0 });
  const curves = events.filter((e) => e.type === 'curveAhead');
  assert.ok(curves.length >= 1);
  assert.equal(curves[0].curve.direction, 'right');
});

test('road king pulls harder than the starter', () => {
  const zeroToSixty = (spec) => {
    const s = new DrivingSession({ spec, road: new Road([straight(90000)]), cargoMassKg: 20000, seed: 1 });
    s.perform({ type: 'toggleEngine' });
    run(s, 2);
    let t = 0;
    while (s.truck.speed < 60 / 3.6 && t < 300) { s.step(DT, { throttle: 1 }); t += DT; }
    return t;
  };
  assert.ok(zeroToSixty(roadKing) < zeroToSixty(starter) * 0.85);
});

test('truck catalog', () => {
  assert.deepEqual(catalog.map((t) => t.id), ['old_reliable', 'workhorse', 'road_king']);
  assert.ok(horsepower(roadKing) > horsepower(starter));
  assert.ok(horsepower(workhorse) < horsepower(starter));
  assert.equal(withID('nonsense').id, 'old_reliable');
});

test('truck stop: signal right, slow down, stop at the pump, fill up', () => {
  const road = practiceLoop();
  const s = new DrivingSession({ road, startingFuel: 100, seed: 1 });
  s.truck.position = road.truckStops[0] - 300;
  s.perform({ type: 'toggleEngine' });
  run(s, 2.5);
  s.perform({ type: 'signal', side: 'right' });
  let events = [];
  for (let i = 0; i < 60 * 40 && !events.some((e) => e.type === 'pulledIntoTruckStop'); i++) {
    events.push(...s.step(DT, { throttle: s.truck.speed < 10 ? 0.4 : 0 }));
  }
  assert.ok(events.some((e) => e.type === 'pulledIntoTruckStop'), events.map((e) => e.type).join());
  events = [...run(s, 12, { brake: 1 }), ...run(s, 15)];
  assert.ok(events.some((e) => e.type === 'refuelStarted'));
  const refuel = events.find((e) => e.type === 'refueled');
  assert.ok(refuel);
  assert.ok(Math.abs(s.truck.fuelLiters - starter.fuelCapacityLiters) < 0.1);
  assert.equal(s.stats.fuelCost, refuel.cost);
});

test('traffic spawns and passes when enabled', () => {
  const s = new DrivingSession({ road: new Road([straight(50000)], { loops: false }), seed: 5 });
  s.trafficEnabled = true;
  s.perform({ type: 'toggleEngine' });
  run(s, 2.5);
  let seen = 0;
  for (let i = 0; i < 60 * 120; i++) {
    s.step(DT, { throttle: s.truck.speed < 15 ? 0.6 : 0, steer: -s.laneGuidanceOffset * 0.8 });
    seen = Math.max(seen, s.trafficSounds.length);
  }
  assert.ok(seen >= 1);
});

test('phrases', () => {
  assert.equal(money(12450), '$12,450');
  assert.equal(money(-300), 'minus $300');
  assert.equal(new Units('metric').distance(1234), '1.2 kilometers');
  assert.equal(new Units('metric').distance(2000), '2 kilometers');
  assert.equal(new Units('metric').distance(234), '250 meters');
  assert.equal(new Units('imperial').distance(1609.34), '1 mile');
  assert.equal(new Units('imperial').distance(100), '350 feet');
  const p = new Phrases('metric');
  assert.equal(
    p.curve({ severity: 'sharp', direction: 'left', distance: 200, advisorySpeed: 20 / 3.6 }),
    'Sharp left curve in 200 meters, slow to 20.',
  );
  assert.equal(p.signal('left'), 'Left signal.');
  assert.match(p.dashboard(new DrivingSession({ seed: 1 }).dashboard), /^0 kilometers per hour, engine off, fuel 100 percent/);
});

function driveTutorial(s, t, seconds, { throttle = 0.6, brake = 0, actions = [], until } = {}) {
  const said = [];
  let pending = actions;
  for (let i = 0; i < Math.round(seconds / DT); i++) {
    for (const a of pending) s.perform(a);
    s.step(DT, { throttle: s.truck.speed < 12 ? throttle : 0, brake, steer: -s.laneGuidanceOffset * 0.8 });
    const line = t.update(DT, s, pending);
    if (line) said.push(line);
    pending = [];
    if (until && t.step === until) break;
  }
  return said;
}

test('tutorial walks through every step', () => {
  const s = new DrivingSession({ seed: 7 });
  const t = new Tutorial();
  const first = driveTutorial(s, t, 0.1, { throttle: 0 });
  assert.match(first[0], /^Welcome/);
  assert.match(first[0], /press N/);
  driveTutorial(s, t, 5, { throttle: 0, actions: [{ type: 'toggleEngine' }], until: 'accelerate' });
  assert.equal(t.step, 'accelerate');
  driveTutorial(s, t, 40, { until: 'stayInLane' });
  driveTutorial(s, t, 30, { until: 'dashboard' });
  assert.equal(t.step, 'dashboard');
  driveTutorial(s, t, 3, { actions: [{ type: 'speakDashboard' }] });
  assert.equal(t.step, 'dashboard', 'waits for the reading');
  driveTutorial(s, t, 4);
  assert.equal(t.step, 'roadAhead');
  driveTutorial(s, t, 7, { actions: [{ type: 'speakRoadAhead' }] });
  assert.equal(t.step, 'signalOn');
  driveTutorial(s, t, 0.5, { actions: [{ type: 'signal', side: 'right' }] });
  assert.equal(t.step, 'signalOff');
  driveTutorial(s, t, 0.5, { actions: [{ type: 'cancelSignal' }] });
  assert.equal(t.step, 'curve');
  driveTutorial(s, t, 300, { until: 'horn' });
  assert.equal(t.step, 'horn');
  driveTutorial(s, t, 0.5, { actions: [{ type: 'horn' }] });
  assert.equal(t.step, 'brake');
  const end = driveTutorial(s, t, 30, { throttle: 0, brake: 1, until: 'done' });
  assert.ok(t.isComplete);
  assert.match(end.at(-1), /Tutorial complete/);
});

test('tutorial reminds when nothing happens', () => {
  const s = new DrivingSession({ seed: 1 });
  const t = new Tutorial();
  const said = driveTutorial(s, t, 60, { throttle: 0 });
  assert.equal(t.step, 'startEngine');
  assert.equal(said.filter((x) => x.startsWith('Reminder')).length, 2);
});
