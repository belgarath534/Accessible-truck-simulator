// A guided first drive: one skill at a time, each step waits until the player has done it.
// Same steps as the iPhone tutorial, worded for the keyboard (and game controllers).

export const STEPS = [
  'startEngine', 'accelerate', 'stayInLane', 'dashboard', 'roadAhead',
  'signalOn', 'signalOff', 'curve', 'horn', 'brake', 'done',
];

export const KEYBOARD = {
  hold: '',
  engine: 'press N',
  accelerate: 'hold the Up arrow key',
  brake: 'hold the Down arrow key',
  steer: 'To steer, use the Left and Right arrow keys. Short taps work best; holding a key keeps the truck sliding that way.',
  dashboard: 'press I',
  gps: 'press G',
  signalRight: 'press the right bracket key, just to the right of P',
  cancelSignal: 'press Backspace',
  horn: 'press H',
  pause: 'Escape opens the pause menu any time you need it.',
};

export class Tutorial {
  static targetSpeed = 8.3; // about 30 km/h or 20 mph
  static laneSeconds = 15;
  static reminderInterval = 25;
  static listenSeconds = 6;

  constructor({ units = 'imperial', controls = KEYBOARD } = {}) {
    this.units = units;
    this.controls = controls;
    this.stepIndex = 0;
    this.started = false;
    this.sinceSpoken = 0;
    this.resetProgress();
  }

  get step() {
    return STEPS[this.stepIndex];
  }

  get isComplete() {
    return this.step === 'done';
  }

  resetProgress() {
    this.laneTime = 0;
    this.inCurve = false;
    this.stoppedTime = 0;
    this.listening = null;
  }

  /** Steps the tutorial. `actions` are the actions the player made since the last call. Returns text to speak, or null. */
  update(dt, session, actions = []) {
    if (this.isComplete) return null;
    if (!this.started) {
      this.started = true;
      this.sinceSpoken = 0;
      return Tutorial.welcome + ' ' + this.instruction(this.step);
    }
    if (this.isDone(this.step, dt, session, actions)) {
      const finished = this.step;
      this.stepIndex += 1;
      this.sinceSpoken = 0;
      this.resetProgress();
      if (this.isComplete) return this.praise(finished) + ' ' + this.finished;
      return this.praise(finished) + ' ' + this.instruction(this.step);
    }
    this.sinceSpoken += dt;
    if (this.listening != null) return null; // done; waiting for the reading to finish
    if (this.sinceSpoken >= Tutorial.reminderInterval) {
      this.sinceSpoken = 0;
      return this.reminder(this.step, session);
    }
    return null;
  }

  /** For steps whose result is spoken: done a few seconds after the key press, so the reading isn't cut off. */
  heard(type, actions, dt) {
    if (this.listening != null) this.listening += dt;
    else if (actions.some((a) => a.type === type)) this.listening = 0;
    return (this.listening ?? 0) >= Tutorial.listenSeconds;
  }

  isDone(step, dt, session, actions) {
    const t = session.truck;
    switch (step) {
      case 'startEngine':
        return t.engine === 'running';
      case 'accelerate':
        return t.speed >= Tutorial.targetSpeed;
      case 'stayInLane':
        if (t.speed > 3 && Math.abs(session.laneGuidanceOffset) < 0.6) this.laneTime += dt;
        return this.laneTime >= Tutorial.laneSeconds;
      case 'dashboard':
        return this.heard('speakDashboard', actions, dt);
      case 'roadAhead':
        return this.heard('speakRoadAhead', actions, dt);
      case 'signalOn':
        return t.signal !== 'off';
      case 'signalOff':
        return t.signal === 'off';
      case 'curve': {
        // Done once the truck has driven into a curve and out the other side.
        const curving = Math.abs(session.road.curvature(t.position)) > 0.0005;
        if (curving) this.inCurve = true;
        return this.inCurve && !curving;
      }
      case 'horn':
        return actions.some((a) => a.type === 'horn');
      case 'brake':
        if (t.speed < 0.3) this.stoppedTime += dt;
        else this.stoppedTime = 0;
        return this.stoppedTime >= 1;
      default:
        return false;
    }
  }

  static welcome = "Welcome to the tutorial. I'll teach you to drive one step at a time, and wait for you at each step. There's no traffic here, and crashes don't cost anything.";

  get finished() {
    return `That's everything you need. Tutorial complete! ${this.controls.pause}`;
  }

  get targetSpeedWords() {
    return this.units === 'metric' ? '30 kilometers per hour' : '20 miles per hour';
  }

  instruction(step) {
    const k = this.controls;
    switch (step) {
      case 'startEngine':
        return `First, start the engine: ${k.engine}.`;
      case 'accelerate':
        return `Now let's move. To accelerate, ${k.accelerate}. The engine gets louder as you speed up and the gears change by themselves. Get up to ${this.targetSpeedWords}.`;
      case 'stayInLane':
        return `Now stay in your lane. ${k.steer} If you drift, you'll hear a beeping tone on that side; steer away from it, gently. Go too far and you'll hear the rumble strip. Keep the truck in the middle of the lane for 15 seconds.`;
      case 'dashboard':
        return `Good driving. Keep going. Now read your dashboard: ${k.dashboard}. You'll hear your speed, gear and fuel.`;
      case 'roadAhead':
        return `Next, ask the GPS what's ahead: ${k.gps}. It tells you about the next curve and how far you have to go.`;
      case 'signalOn':
        return `Turn signals choose your way at junctions on the map. Turn on the right signal: ${k.signalRight}.`;
      case 'signalOff':
        return `Hear the ticking? That's your signal. To cancel it, ${k.cancelSignal}.`;
      case 'curve':
        return 'Curves are announced before you reach them, with how sharp they are. Slow down before sharp ones, and steer with the curve. Keep driving and get through the next curve.';
      case 'horn':
        return `Nice curve. Now the horn: ${k.horn}.`;
      case 'brake':
        return `Last step: stop the truck. To brake, ${k.brake} until you've stopped completely. At a delivery you stop on the drop-off the same way.`;
      default:
        return this.finished;
    }
  }

  praise(step) {
    return {
      startEngine: 'Engine running.',
      accelerate: "Great, you're up to speed.",
      stayInLane: 'Well done, nice and steady.',
      dashboard: "That's it.",
      roadAhead: "That's it.",
      signalOn: 'Signal on.',
      signalOff: 'Signal off.',
      curve: 'You made it through.',
      horn: 'Loud and clear.',
      brake: 'Stopped. Well done!',
    }[step] ?? '';
  }

  reminder(step, session) {
    const t = session.truck;
    const k = this.controls;
    if (step === 'accelerate' && t.engine !== 'running') return `The engine is off. To start it, ${k.engine}.`;
    if (step === 'stayInLane' && t.speed < 3) return `Keep moving: ${k.accelerate}. Then keep the truck in the middle of the lane.`;
    if (step === 'curve' && t.speed < 3) return `Keep driving to reach the next curve: ${k.accelerate}.`;
    return 'Reminder: ' + this.instruction(step);
  }
}
