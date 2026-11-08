// Turns simulation events and state into sound and speech. A port of FeedbackCoordinator.swift.

import { Phrases } from '../sim/phrases.js';

export class Feedback {
  constructor(audio, speech, settings) {
    this.audio = audio;
    this.speech = speech;
    this.settings = settings;
    this.reset();
  }

  get phrases() {
    return new Phrases(this.settings.units);
  }

  reset() {
    this.lastSpokenSpeedStep = null;
    this.wasMoving = false;
    this.audio.setRumble(null);
  }

  say(text, priority = 'normal') {
    this.speech.speak(text, priority);
  }

  handle(events) {
    for (const e of events) this.handleOne(e);
  }

  handleOne(e) {
    const p = this.phrases;
    switch (e.type) {
      case 'engineStarting': this.audio.engineStarting(); this.say('Starting engine.'); break;
      case 'engineStarted': if (!this.quietEngineStart) this.say('Engine running.'); break;
      case 'engineStopped': this.audio.engineStopped(); this.say('Engine off.', 'high'); break;
      case 'engineNotRunning': this.say('The engine is off. Press N to start it.', 'high'); break;
      case 'gearChanged':
        this.audio.gearShift();
        if (this.settings.announceGears) this.say(`Gear ${e.gear}`, 'low');
        break;
      case 'signalChanged': this.say(p.signal(e.signal), 'high'); break;
      case 'horn': this.audio.honk(); break;
      case 'rumbleStrip': this.audio.setRumble(e.side); break;
      case 'curveAhead': this.say(p.curve(e.curve)); break;
      case 'navInstruction': this.say(p.navInstruction(e.instruction)); break;
      case 'junctionAhead': this.say(p.junctionAhead(e.choices, e.distance)); break;
      case 'tookRoad': this.say(p.tookRoad(e.roadName, e.toward, e.length)); break;
      case 'rerouted': this.say(p.rerouted(e.remaining), 'high'); break;
      case 'missedDropOff': this.say(p.missedDropOff, 'high'); break;
      case 'enteredTown': this.say(p.enteredTown(e.name, e.speedLimit)); break;
      case 'leftTown': this.say(p.leftTown(e.name, e.speedLimit)); break;
      case 'changedLane': this.say(p.changedLane(e.toLeft, e.oncoming)); break;
      case 'wrongSideOfRoad': this.say(p.wrongSideOfRoad, 'high'); break;
      case 'vehicleAhead': this.say(p.vehicleAhead(e.distance, e.speed, e.kind), 'high'); break;
      case 'tooClose': this.say(p.tooClose, 'high'); break;
      case 'oncomingHorn': this.audio.oncomingCarHorn(); break;
      case 'passedPolice': this.audio.policeRadio(); break;
      case 'policeChase': this.say(p.policeChase(e.speed, e.limit), 'high'); break;
      case 'speedingTicket': this.say(p.speedingTicket(e.speed, e.limit, e.fine), 'high'); break;
      case 'fledPolice': this.say(p.fledPolice(e.fine), 'high'); break;
      case 'onShoulder': this.say(p.onShoulder(e.side), 'high'); break;
      case 'tooFastForCurve': this.say('Too fast for this curve!', 'high'); break;
      case 'crashed':
        this.audio.crash();
        this.say(p.crash(e.reason), 'high');
        this.lastSpokenSpeedStep = 0;
        break;
      case 'outOfFuel': this.say('Out of fuel.', 'high'); break;
      case 'fuelLow': this.say(p.fuelLow(e.fraction, e.nextStop, e.urgent), e.urgent ? 'high' : 'normal'); break;
      case 'truckStopAhead': this.say(p.truckStopAhead(e.distance)); break;
      case 'pulledIntoTruckStop': this.say(p.pulledIntoTruckStop, 'high'); break;
      case 'missedTruckStop': this.say(p.missedTruckStop(e.tooFast), 'high'); break;
      case 'refuelStarted': this.say(p.refuelStarted, 'high'); break;
      case 'refueled': this.say(p.refueled(e.liters, e.cost), 'high'); break;
      case 'leftTruckStop': this.say(p.leftTruckStop); break;
      case 'towed': this.say(p.towed(e.cost, e.fuelCost), 'high'); break;
      case 'dashboard': this.say(p.dashboard(e.reading), 'high'); break;
      case 'roadAhead': this.say(p.roadAhead(e), 'high'); break;
      case 'timeLeft': this.say(p.timeLeft(e.seconds)); break;
      case 'lateForDelivery': this.say(p.lateForDelivery, 'high'); break;
      case 'tripProgress': this.say(p.tripProgress(e.remaining)); break;
      case 'destinationAhead': this.say(p.destinationAhead(e.distance), 'high'); break;
      case 'atDestination': this.say(p.atDestination, 'high'); break;
      case 'stoppedShort': this.say(p.stoppedShort(e.remaining)); break;
      case 'arrived': this.audio.setMuted(true); break; // the results screen speaks for itself
      default: break;
    }
  }

  /** Every frame, with the latest state. */
  update(session) {
    const t = session.truck;
    this.audio.update(t, session.spec);
    this.audio.setLaneGuidance(session.laneGuidanceOffset);
    this.audio.updateTraffic(session.trafficSounds);
    const r = session.remaining;
    this.audio.set({
      pumping: session.isRefueling,
      siren: session.sirenOn,
      // Drop-off beacon: beeps speed up over the last 150 m, a steady tone right at the drop-off.
      beaconDistance: !session.summary && r != null && r < 150 && r > -60 ? r : -1000,
    });
    this.announceSpeedIfNeeded(t.speed);
    // Air brakes hiss when the truck comes to a stop.
    if (t.speed > 3) this.wasMoving = true;
    if (this.wasMoving && t.speed < 0.2) {
      this.wasMoving = false;
      this.audio.airBrake();
    }
    this.audio.flush();
  }

  /** Calls out the speed every 10 km/h (or mph), with a little hysteresis so it doesn't chatter. */
  announceSpeedIfNeeded(speed) {
    if (!this.settings.announceSpeed) return;
    const display = this.phrases.units.speed(speed);
    const step = Math.floor(display / 10);
    if (this.lastSpokenSpeedStep == null) {
      this.lastSpokenSpeedStep = step;
      return;
    }
    const last = this.lastSpokenSpeedStep;
    const crossedUp = step > last;
    const crossedDown = step < last && display < last * 10 - 3;
    if ((crossedUp || crossedDown) && step > 0) {
      this.lastSpokenSpeedStep = step;
      this.say(`${step * 10}`, 'low');
    } else if (step === 0 && last !== 0 && display < 2) {
      this.lastSpokenSpeedStep = 0;
    }
  }

  intro(session) {
    const p = this.phrases;
    const controls = 'Engine off. Press N to start the engine. Hold Up to accelerate, Down to brake, Left and Right to steer. I reads the dashboard, G tells you what\'s ahead, Escape pauses.';
    if (session.goal.distance != null) {
      return `${session.goal.name}: ${p.units.distance(session.goal.distance)} to the drop-off. Stop there to finish. ${controls}`;
    }
    return `${session.goal.name}. ${controls}`;
  }
}
