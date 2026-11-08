// The driving simulation for one trip. Pure logic: feed it input every tick, get events back.
// A direct port of DrivingSession.swift from the iPhone version, so both drive the same.
//
// Events are plain objects: { type: 'curveAhead', curve }, { type: 'crashed', reason }, ...
// Signal: 'off' | 'left' | 'right'.  Engine: 'off' | 'starting' | 'running'.

import { practiceLoop } from './road.js';
import { starter, torqueAt, peakTorque } from './truck.js';
import { freeDriveGoal, newStats, ARRIVAL_TOLERANCE } from './trip.js';
import { SeededRandom } from './random.js';

export const ASSISTS = {
  off: { simple: false, maxLateralSpeed: 0, curvePush: 0, alignRate: 0 },
  low: { simple: true, maxLateralSpeed: 2.2, curvePush: 0.55, alignRate: 0.35 },
  medium: { simple: true, maxLateralSpeed: 1.8, curvePush: 0.38, alignRate: 0.7 },
  high: { simple: true, maxLateralSpeed: 1.5, curvePush: 0.25, alignRate: 1.3 },
};

export const C = {
  arrivalTolerance: ARRIVAL_TOLERANCE,
  milestones: [10000, 5000, 2000, 1000],
  destinationWarning: 400,
  rumbleOffset: 0.9,
  offRoadOffset: 2.6,
  leftLaneCenter: -3.7,
  centerLine: -1.85,
  leftRumbleOffset: -4.6,
  leftOffRoadOffset: -6.3,
  fuelGameScale: 10,
  truckStopFuelPrice: 2.5,
  pumpRate: 40,
  truckStopExitSpeed: 50 / 3.6,
  towFee: 150,
  towSeconds: 120,
  policeChance: 0.5,
  policeRange: 120,
  speedingTolerance: 8 / 3.6,
  pullOverTime: 25,
  shoulderSafeSpeed: 25 / 3.6,
  typicalFuelPerMetre: 0.0035,
  truckLength: 16,
};

export function speedingFine(speed, limit) {
  const over = Math.max(0, (speed - limit) * 3.6);
  return 100 + Math.round((over * 25) / 10) * 10;
}

const clamp = (x, lo, hi) => Math.min(Math.max(x, lo), hi);

export function vehicleLength(kind) {
  return kind === 'truck' ? 14 : kind === 'pickup' ? 5.5 : 4.5;
}
export function vehicleHalfWidth(kind) {
  return kind === 'truck' ? 1.25 : 0.95;
}

export class DrivingSession {
  constructor({
    spec = starter,
    road = practiceLoop(),
    goal = freeDriveGoal,
    cargoMassKg = 0,
    timeLimit = null,
    startingFuel = null,
    navigator = null,
    assist = 'medium',
    seed,
  } = {}) {
    this.rng = new SeededRandom(seed);
    this.spec = spec;
    this.navigator = navigator;
    this.road = navigator ? navigator.road : road;
    this.goal = goal;
    this.cargoMassKg = cargoMassKg;
    this.timeLimit = timeLimit;
    this.assist = assist;
    this.time = 0;
    this.stats = newStats();
    this.summary = null;
    const fuel = Math.min(spec.fuelCapacityLiters, Math.max(0, startingFuel ?? spec.fuelCapacityLiters));
    this.truck = {
      position: 0,
      lateralOffset: 0,
      headingError: 0,
      speed: 0,
      steerAngle: 0,
      lateralVelocity: 0,
      rpm: 0,
      gearIndex: 0,
      shiftTimer: 0,
      engine: 'off',
      startRemaining: 0,
      engineLoad: 0,
      fuelLiters: fuel,
      engineTempC: 20,
      signal: 'off',
      odometer: 0,
    };

    this.announcedCurveIndex = null;
    this.lastTooFastWarning = -100;
    this.rumbleSide = null;
    this.lastEngineOffHint = -100;
    this.announcedMilestones = new Set();
    this.warnedDestination = false;
    this.announcedAtDestination = false;
    this.wasStopped = true;
    this.announcedTimeWarnings = new Set();
    this.currentZone = null;
    this.policeDecided = new Map();
    this.chase = null;
    this.trafficEnabled = false;
    this.traffic = [];
    this.nextVehicleID = 0;
    this.oncomingTimer = 12;
    this.slowTimer = 40;
    this.warnedAhead = new Set();
    this.honked = new Set();
    this.lastTooClose = -100;
    this.policePresenceChance = C.policeChance;
    this.navAnnounced = new Set();
    this.lastShoulderWarning = -100;
    this.targetLane = 0;
    this.inLeftLane = false;
    this.lastWrongSideWarning = -100;
    this.truckStopState = { kind: 'driving' };
    this.announcedStop = null;
    this.exitChecked = null;
    this.outOfFuelTimer = 0;
    this.announcedLate = false;
    // A tank already under the warning levels shouldn't be announced as if it just dropped.
    this.warnedQuarter = fuel / spec.fuelCapacityLiters < 0.25;
    this.fuelWarned = fuel / spec.fuelCapacityLiters < 0.1;
  }

  get assistInfo() {
    return ASSISTS[this.assist] ?? ASSISTS.medium;
  }
  get sirenOn() {
    return this.chase !== null;
  }
  get laneGuidanceOffset() {
    return this.truck.lateralOffset - this.targetLane;
  }
  get isRefueling() {
    return this.truckStopState.kind === 'refueling';
  }
  get isAtTruckStop() {
    return this.truckStopState.kind !== 'driving';
  }
  get totalMassKg() {
    return this.spec.massKg + this.cargoMassKg;
  }
  get fuelPerMetre() {
    if (this.stats.distance > 1000 && this.stats.fuelUsedLiters > 0) return this.stats.fuelUsedLiters / this.stats.distance;
    return C.typicalFuelPerMetre;
  }
  get range() {
    return this.truck.fuelLiters / this.fuelPerMetre;
  }
  get timeLeft() {
    return this.timeLimit == null ? null : this.timeLimit - this.stats.drivingTime;
  }
  /** Metres left to the drop-off (negative once past it), or null on a free drive. */
  get remaining() {
    if (this.navigator) return this.navigator.remaining(this.truck.position);
    return this.goal.distance == null ? null : this.goal.distance - this.truck.odometer;
  }
  get currentSpeedLimit() {
    return this.road.speedLimitAt(this.truck.position);
  }

  get dashboard() {
    const t = this.truck;
    return {
      speed: t.speed,
      gear: t.engine === 'running' ? t.gearIndex + 1 : 0,
      rpm: t.engine === 'running' ? t.rpm : 0,
      fuelFraction: t.fuelLiters / this.spec.fuelCapacityLiters,
      engineTempC: t.engineTempC,
      signal: t.signal,
      engine: t.engine,
      speedLimit: this.currentSpeedLimit,
      range: this.range,
    };
  }

  // MARK: Actions

  perform(action) {
    const t = this.truck;
    switch (action.type) {
      case 'toggleEngine':
        if (t.engine === 'off') {
          if (t.fuelLiters <= 0) return [{ type: 'outOfFuel' }];
          t.engine = 'starting';
          t.startRemaining = this.spec.engineStartSeconds;
          return [{ type: 'engineStarting' }];
        }
        t.engine = 'off';
        return [{ type: 'engineStopped' }];
      case 'signal':
        t.signal = t.signal === action.side ? 'off' : action.side;
        return [{ type: 'signalChanged', signal: t.signal }];
      case 'cancelSignal':
        t.signal = 'off';
        return [{ type: 'signalChanged', signal: 'off' }];
      case 'horn':
        return [{ type: 'horn' }];
      case 'speakDashboard':
        return [{ type: 'dashboard', reading: this.dashboard }];
      case 'speakRoadAhead': {
        const events = [{
          type: 'roadAhead',
          curve: this.road.nextCurve(t.position, 3000),
          remaining: this.remaining,
          timeLeft: this.timeLeft,
          truckStop: this.road.nextTruckStop(t.position)?.distance ?? null,
        }];
        const nav = this.navigator;
        if (nav) {
          if (nav.destination != null) {
            const next = nav.nextInstruction(t.position);
            if (next) events.push({ type: 'navInstruction', instruction: next });
          } else {
            events.push({ type: 'junctionAhead', choices: nav.junctionChoices, distance: this.road.totalLength - t.position });
          }
        }
        return events;
      }
      default:
        return [];
    }
  }

  /** Puts the truck back in the centre of its lane, stopped. Used after a crash. */
  recover() {
    const t = this.truck;
    t.lateralOffset = 0;
    t.headingError = 0;
    t.lateralVelocity = 0;
    t.speed = 0;
    t.steerAngle = 0;
    this.targetLane = 0;
    this.inLeftLane = false;
    t.gearIndex = 0;
    this.rumbleSide = null;
  }

  // MARK: Simulation step

  step(dt, raw) {
    if (this.summary) return [];
    const events = [];
    this.time += dt;
    const input = {
      throttle: clamp(raw.throttle ?? 0, 0, 1),
      brake: clamp(raw.brake ?? 0, 0, 1),
      steer: clamp(raw.steer ?? 0, -1, 1),
    };
    this.stepEngineState(dt, events);
    if (this.truck.engine === 'off' && input.throttle > 0.5 && this.time - this.lastEngineOffHint > 6) {
      this.lastEngineOffHint = this.time;
      events.push({ type: 'engineNotRunning' });
    }
    this.stepLongitudinal(dt, input, events);
    this.stepLateral(dt, input);
    this.stepTemperatureAndFuel(dt, events);
    this.checkLane(events);
    this.checkCurves(events);
    this.checkMap(events);
    this.stepTraffic(dt, events);
    this.checkPolice(dt, events);
    this.checkTruckStops(dt, input, events);
    this.checkTow(dt, events);
    this.updateStats(dt, events);
    this.checkTrip(events);
    return events;
  }

  updateStats(dt, events) {
    const s = this.stats;
    if (s.drivingTime > 0 || this.truck.speed > 0.1) s.drivingTime += dt;
    s.distance = this.truck.odometer;
    s.topSpeed = Math.max(s.topSpeed, this.truck.speed);
    for (const e of events) {
      if (e.type === 'crashed') s.crashes += 1;
      if (e.type === 'tooFastForCurve') s.tooFastWarnings += 1;
    }
  }

  checkTrip(events) {
    const timeLeft = this.timeLeft;
    if (timeLeft != null) {
      for (const warning of [300, 60]) {
        if (timeLeft <= warning && !this.announcedTimeWarnings.has(warning)) {
          this.announcedTimeWarnings.add(warning);
          if ((this.timeLimit ?? 0) - warning > 60) events.push({ type: 'timeLeft', seconds: warning });
        }
      }
      if (timeLeft < 0 && !this.announcedLate) {
        this.announcedLate = true;
        events.push({ type: 'lateForDelivery' });
      }
    }
    const total = this.goal.distance;
    const remaining = this.remaining;
    if (total == null || remaining == null) return;
    for (const m of C.milestones) {
      if (remaining <= m && !this.announcedMilestones.has(m)) {
        this.announcedMilestones.add(m);
        if (total - m > 500) events.push({ type: 'tripProgress', remaining: m });
      }
    }
    if (!this.warnedDestination && remaining <= C.destinationWarning) {
      this.warnedDestination = true;
      events.push({ type: 'destinationAhead', distance: Math.max(0, remaining) });
    }
    if (!this.announcedAtDestination && remaining <= 0 && this.truck.speed > 2) {
      this.announcedAtDestination = true;
      events.push({ type: 'atDestination' });
    }
    const stopped = this.truck.speed < 0.3;
    const wasStopped = this.wasStopped;
    this.wasStopped = stopped;
    if (!stopped) return;
    if (remaining <= C.arrivalTolerance && this.stats.drivingTime > 0) {
      this.summary = { goalName: this.goal.name, stats: { ...this.stats }, stopError: -remaining };
      events.push({ type: 'arrived', summary: this.summary });
    } else if (!wasStopped && remaining <= 1000 && this.stats.drivingTime > 0 && !events.some((e) => e.type === 'crashed')) {
      events.push({ type: 'stoppedShort', remaining });
    }
  }

  stepEngineState(dt, events) {
    const t = this.truck;
    if (t.engine !== 'starting') return;
    t.startRemaining -= dt;
    if (t.startRemaining <= 0) {
      t.engine = 'running';
      t.rpm = this.spec.idleRPM;
      events.push({ type: 'engineStarted' });
    } else {
      // Cranking: the starter motor spins the engine slowly.
      t.rpm = 150 + 100 * Math.sin(this.time * 40);
    }
  }

  overallRatio(gearIndex) {
    return this.spec.gearRatios[gearIndex] * this.spec.finalDrive;
  }

  wheelRPM(speed) {
    return (speed / (2 * Math.PI * this.spec.wheelRadius)) * 60;
  }

  stepLongitudinal(dt, input, events) {
    const spec = this.spec;
    const t = this.truck;
    const mass = this.totalMassKg;
    const g = 9.81;
    const running = t.engine === 'running';
    const wheelRPM = this.wheelRPM(t.speed);

    // Automatic gearbox.
    if (running && t.shiftTimer <= 0) {
      const rpmInGear = wheelRPM * this.overallRatio(t.gearIndex);
      if (rpmInGear > spec.shiftUpRPM && t.gearIndex < spec.gearRatios.length - 1) {
        t.gearIndex += 1;
        t.shiftTimer = spec.shiftSeconds;
        events.push({ type: 'gearChanged', gear: t.gearIndex + 1, up: true });
      } else if (rpmInGear < spec.shiftDownRPM && t.gearIndex > 0) {
        // Skip-shift down to a sensible gear when slowing hard.
        let target = t.gearIndex - 1;
        while (target > 0 && wheelRPM * this.overallRatio(target) < spec.shiftDownRPM) target -= 1;
        t.gearIndex = target;
        t.shiftTimer = spec.shiftSeconds;
        events.push({ type: 'gearChanged', gear: t.gearIndex + 1, up: false });
      }
    }
    const shifting = t.shiftTimer > 0;
    t.shiftTimer = Math.max(0, t.shiftTimer - dt);

    // Engine RPM: locked to the wheels once the clutch is engaged, otherwise slipping above idle.
    const ratio = this.overallRatio(t.gearIndex);
    const lockedRPM = wheelRPM * ratio;
    let targetRPM;
    if (running) {
      const slipRPM = spec.idleRPM + input.throttle * 700;
      targetRPM = shifting
        ? Math.max(spec.idleRPM, lockedRPM * 0.8)
        : Math.max(lockedRPM, t.gearIndex === 0 ? slipRPM : spec.idleRPM);
      targetRPM = Math.min(targetRPM, spec.maxRPM);
    } else if (t.engine === 'starting') {
      targetRPM = t.rpm;
    } else {
      targetRPM = 0;
    }
    t.rpm += (targetRPM - t.rpm) * Math.min(1, dt * 8);

    // Drive force.
    let driveForce = 0;
    if (running && !shifting) {
      const governed = t.speed >= spec.speedLimiter;
      const throttle = governed ? 0 : input.throttle;
      const torque = torqueAt(spec, Math.max(t.rpm, spec.idleRPM)) * throttle;
      driveForce = (torque * ratio * spec.drivetrainEfficiency) / spec.wheelRadius;
      driveForce = Math.min(driveForce, mass * spec.tractionLimitAccel);
      if (throttle < 0.05 && t.speed > 1) {
        const engineBrake = peakTorque(spec) * spec.engineBrakeFraction * (t.rpm / spec.maxRPM);
        driveForce -= (engineBrake * ratio) / spec.wheelRadius;
      }
      t.engineLoad = throttle;
    } else {
      t.engineLoad = 0;
    }

    // Resistances.
    const aero = 0.5 * 1.2 * spec.dragArea * t.speed * t.speed;
    const rolling = t.speed > 0.01 ? spec.rollingResistance * mass * g : 0;
    // Brake force is sized for the truck with a light load, so heavy cargo takes longer to stop.
    const brakeDecel = Math.min(spec.maxBrakeDecel, (spec.maxBrakeDecel * spec.massKg * 1.5) / mass);
    const brake = input.brake * brakeDecel * mass;

    let accel = (driveForce - aero - rolling) / mass;
    accel -= t.speed > 0 ? brake / mass : 0;

    t.speed = Math.max(0, t.speed + accel * dt);
    if (t.speed < 0.05 && input.throttle < 0.05) t.speed = 0;

    // Looping roads wrap; map roads run past their end into the next junction (see checkMap).
    const advanced = t.position + t.speed * dt;
    t.position = this.road.loops ? this.road.normalized(advanced) : advanced;
    t.odometer += t.speed * dt;
  }

  stepLateral(dt, input) {
    const spec = this.spec;
    const t = this.truck;
    const v = t.speed;
    // Speed-sensitive steering: full lock always gives about the same sideways force.
    const speedLimitedAngle = v > 1 ? (spec.steeringLatAccel * spec.wheelbase) / (v * v) : spec.maxSteerAngle;
    const maxAngle = Math.min(spec.maxSteerAngle, speedLimitedAngle);
    const target = input.steer * maxAngle;
    const maxDelta = spec.steerRate * dt;
    t.steerAngle += clamp(target - t.steerAngle, -maxDelta, maxDelta);
    if (Math.abs(t.steerAngle) > maxAngle) t.steerAngle = maxAngle * Math.sign(t.steerAngle);

    const kRoad = this.road.curvature(t.position);
    const assist = this.assistInfo;
    if (assist.simple) {
      this.stepSimpleLateral(dt, input, kRoad);
      return;
    }
    // Realistic: kinematic bicycle model in road-relative coordinates.
    let headingRate = (v * Math.tan(t.steerAngle)) / spec.wheelbase - v * kRoad;
    if (Math.abs(input.steer) < 0.1 && v > 0.5) headingRate -= assist.alignRate * t.headingError;
    t.headingError = clamp(t.headingError + headingRate * dt, -0.6, 0.6);
    t.lateralOffset += v * Math.sin(t.headingError) * dt;
  }

  /** Simple handling: steering sets how fast the truck moves across the lane. */
  stepSimpleLateral(dt, input, k) {
    const spec = this.spec;
    const t = this.truck;
    const assist = this.assistInfo;
    const v = t.speed;
    // Sideways force the curve asks for; positive curvature (right bend) pushes left.
    const curveAccel = v * v * k;
    let push = -curveAccel * assist.curvePush;
    // Too fast for the curve: past the tyres' grip the truck slides out much harder.
    const grip = spec.steeringLatAccel;
    const overGrip = Math.abs(curveAccel) / grip - 0.9;
    if (overGrip > 0) push *= 1 + 4 * overGrip;
    const speedFactor = Math.min(1, v / 4);
    const target = (input.steer * assist.maxLateralSpeed + push) * speedFactor;
    t.lateralVelocity += (target - t.lateralVelocity) * Math.min(1, dt / 0.35);
    t.lateralOffset += t.lateralVelocity * dt;
    t.headingError = v > 0.5 ? Math.atan2(t.lateralVelocity, v) : 0;
    t.steerAngle = input.steer * Math.min(spec.maxSteerAngle, v > 1 ? (grip * spec.wheelbase) / (v * v) : spec.maxSteerAngle);
  }

  stepTemperatureAndFuel(dt, events) {
    const spec = this.spec;
    const t = this.truck;
    const running = t.engine === 'running';
    const targetTemp = running ? 82 + 10 * t.engineLoad : 20;
    const rate = running ? 0.01 : 0.003;
    t.engineTempC += (targetTemp - t.engineTempC) * Math.min(1, dt * rate);
    if (!running) return;
    const powerKW = (torqueAt(spec, t.rpm) * t.engineLoad * t.rpm * 2 * Math.PI) / 60 / 1000;
    const litersPerSecond = (0.0005 + (powerKW * 0.252) / 3600) * C.fuelGameScale;
    const burned = Math.min(t.fuelLiters, litersPerSecond * dt);
    t.fuelLiters -= burned;
    this.stats.fuelUsedLiters += burned;
    const fraction = t.fuelLiters / spec.fuelCapacityLiters;
    const nextStop = () => this.road.nextTruckStop(t.position)?.distance ?? null;
    if (t.fuelLiters <= 0) {
      t.engine = 'off';
      events.push({ type: 'outOfFuel' }, { type: 'engineStopped' });
    } else if (!this.fuelWarned && fraction < 0.1) {
      this.fuelWarned = true;
      this.warnedQuarter = true;
      events.push({ type: 'fuelLow', fraction, nextStop: nextStop(), urgent: true });
    } else if (!this.warnedQuarter && fraction < 0.25) {
      this.warnedQuarter = true;
      events.push({ type: 'fuelLow', fraction, nextStop: nextStop(), urgent: false });
    }
  }

  // MARK: Map

  checkMap(events) {
    const nav = this.navigator;
    if (!nav) return;
    const t = this.truck;
    const position = t.position;

    // Towns: speed limit changes.
    const zone = this.road.speedZone(position);
    if ((zone?.name ?? null) !== this.currentZone) {
      if (zone) events.push({ type: 'enteredTown', name: zone.name, speedLimit: zone.limit });
      else if (this.currentZone) events.push({ type: 'leftTown', name: this.currentZone, speedLimit: this.road.speedLimitAt(position) });
      this.currentZone = zone?.name ?? null;
    }

    // GPS: the next junction at 1 km and 300 m (free roaming: the choices at 800 m).
    const toEnd = this.road.totalLength - position;
    if (t.speed > 1) {
      if (nav.destination != null) {
        for (const mark of [1000, 300]) {
          if (toEnd <= mark && !this.navAnnounced.has(mark)) {
            this.navAnnounced.add(mark);
            const instruction = this.road.totalLength > mark + 200 ? nav.nextInstruction(position) : null;
            if (instruction) events.push({ type: 'navInstruction', instruction });
          }
        }
      } else if (toEnd <= 800 && !this.navAnnounced.has(800)) {
        this.navAnnounced.add(800);
        events.push({ type: 'junctionAhead', choices: nav.junctionChoices, distance: toEnd });
      }
    }

    // End of the road: take the junction (or, at the destination, allow a little room to stop).
    if (position < this.road.totalLength) return;
    if (nav.onFinalRoad) {
      if (position <= this.road.totalLength + 150) return;
      events.push({ type: 'missedDropOff' });
    }
    const oldLength = this.road.totalLength;
    const result = nav.takeJunction(t.signal);
    this.road = nav.road;
    t.position = position - oldLength;
    if (result.choice.turn !== 'straight') t.signal = 'off';
    this.announcedCurveIndex = null;
    this.announcedStop = null;
    this.exitChecked = null;
    this.truckStopState = { kind: 'driving' };
    this.navAnnounced = new Set();
    this.policeDecided = new Map();
    this.clearTraffic();
    this.currentZone = this.road.speedZone(t.position)?.name ?? null;
    events.push({
      type: 'tookRoad',
      roadName: result.choice.roadName,
      toward: result.choice.toward,
      length: this.road.totalLength,
      turn: result.choice.turn,
    });
    if (!result.onRoute && this.remaining != null) events.push({ type: 'rerouted', remaining: this.remaining });
  }

  // MARK: Police

  checkPolice(dt, events) {
    const t = this.truck;
    if (this.chase) {
      const c = this.chase;
      c.timer += dt;
      if (t.speed < 0.3) {
        const fine = speedingFine(c.speed, c.limit);
        this.stats.tickets += 1;
        this.stats.ticketCost += fine;
        this.chase = null;
        events.push({ type: 'speedingTicket', speed: c.speed, limit: c.limit, fine });
      } else if (c.timer > C.pullOverTime) {
        const fine = speedingFine(c.speed, c.limit) * 3 + 500;
        this.stats.tickets += 1;
        this.stats.ticketCost += fine;
        this.chase = null;
        events.push({ type: 'fledPolice', fine });
      }
      return;
    }
    for (const spot of this.road.policeSpots) {
      if (Math.abs(t.position - spot) >= C.policeRange) continue;
      let present = this.policeDecided.get(spot);
      if (present === undefined) {
        present = this.rng.next() < this.policePresenceChance;
        this.policeDecided.set(spot, present);
        if (present && t.speed > 1) events.push({ type: 'passedPolice' });
      }
      if (!present) continue;
      const limit = this.currentSpeedLimit;
      if (t.speed > limit + C.speedingTolerance) {
        this.chase = { speed: t.speed, limit, timer: 0 };
        this.policeDecided.set(spot, false); // one stop per police car
        events.push({ type: 'policeChase', speed: t.speed, limit });
        return;
      }
    }
  }

  // MARK: Truck stops

  checkTruckStops(dt, input, events) {
    const spec = this.spec;
    const t = this.truck;
    const fraction = t.fuelLiters / spec.fuelCapacityLiters;
    const st = this.truckStopState;
    if (st.kind === 'driving') {
      const next = this.road.nextTruckStop(t.position);
      if (!next) return;
      if (next.distance < 1500 && this.announcedStop !== next.index && fraction < 0.5 && t.speed > 2) {
        this.announcedStop = next.index;
        events.push({ type: 'truckStopAhead', distance: next.distance });
      }
      // Taking the exit: right signal on while passing the truck stop, slowly enough.
      if (next.distance < 40 && this.exitChecked !== next.index && t.signal === 'right') {
        this.exitChecked = next.index;
        if (t.speed <= C.truckStopExitSpeed) {
          this.truckStopState = { kind: 'pulledIn', index: next.index };
          t.signal = 'off';
          events.push({ type: 'pulledIntoTruckStop' });
        } else {
          events.push({ type: 'missedTruckStop', tooFast: true });
        }
      }
      if (next.distance > 200 && this.exitChecked === next.index) this.exitChecked = null;
      if (next.distance > 2000 && this.announcedStop === next.index) this.announcedStop = null;
    } else if (st.kind === 'pulledIn') {
      // Signed distance past the pump (negative = still before it), wrapped for looping roads.
      let past = t.position - this.road.truckStops[st.index];
      if (this.road.loops) {
        if (past > this.road.totalLength / 2) past -= this.road.totalLength;
        if (past < -this.road.totalLength / 2) past += this.road.totalLength;
      }
      if (t.speed < 0.3 && past > -150 && past < 300) {
        this.truckStopState = { kind: 'refueling', index: st.index, liters: 0 };
        events.push({ type: 'refuelStarted' });
      } else if (past >= 300) {
        this.truckStopState = { kind: 'driving' };
        events.push({ type: 'leftTruckStop' });
      }
    } else {
      const room = spec.fuelCapacityLiters - t.fuelLiters;
      const add = Math.min(room, C.pumpRate * dt);
      t.fuelLiters += add;
      const total = st.liters + add;
      // Done when full, or when the driver drives off early.
      if (t.fuelLiters >= spec.fuelCapacityLiters - 0.01 || input.throttle > 0.3) {
        const cost = Math.round(total * C.truckStopFuelPrice);
        this.stats.fuelBoughtLiters += total;
        this.stats.fuelCost += cost;
        this.fuelWarned = t.fuelLiters / spec.fuelCapacityLiters < 0.1;
        this.warnedQuarter = t.fuelLiters / spec.fuelCapacityLiters < 0.25;
        events.push({ type: 'refueled', liters: total, cost });
        // Parked at the pump: count as moving on so the next stop isn't another refuel.
        this.truckStopState = { kind: 'driving' };
        this.exitChecked = st.index;
      } else {
        st.liters = total;
      }
    }
  }

  /** Out of fuel and stopped: a tow truck takes you to the next truck stop and puts in a quarter tank. */
  checkTow(dt, events) {
    const t = this.truck;
    if (!(t.fuelLiters <= 0 && t.speed < 0.3)) {
      this.outOfFuelTimer = 0;
      return;
    }
    this.outOfFuelTimer += dt;
    if (this.outOfFuelTimer <= 3) return;
    this.outOfFuelTimer = 0;
    const next = this.road.nextTruckStop(t.position);
    if (next) {
      t.position = this.road.normalized(t.position + next.distance);
      t.odometer += next.distance;
    }
    this.recover();
    const liters = this.spec.fuelCapacityLiters * 0.25;
    t.fuelLiters = liters;
    const fuelCost = Math.round(liters * C.truckStopFuelPrice);
    this.stats.tows += 1;
    this.stats.towCost += C.towFee;
    this.stats.fuelBoughtLiters += liters;
    this.stats.fuelCost += fuelCost;
    this.stats.drivingTime += C.towSeconds;
    this.fuelWarned = false;
    this.warnedQuarter = true;
    events.push({ type: 'towed', cost: C.towFee, fuelCost });
  }

  checkLane(events) {
    const t = this.truck;
    const y = t.lateralOffset;
    // Lane changes: signalling left while crossing the center line means you meant to (passing).
    const leftNow = y < C.centerLine;
    if (leftNow !== this.inLeftLane) {
      this.inLeftLane = leftNow;
      if (leftNow) {
        if (t.signal === 'left') this.targetLane = C.leftLaneCenter;
      } else {
        this.targetLane = 0;
      }
      events.push({ type: 'changedLane', toLeft: leftNow, oncoming: !this.road.leftLaneSameDirection });
    }
    const offRoad = y > C.offRoadOffset || y < C.leftOffRoadOffset;
    if (offRoad) {
      const side = y > 0 ? 'right' : 'left';
      if (t.speed > C.shoulderSafeSpeed || !this.assistInfo.simple) {
        events.push({ type: 'crashed', reason: { kind: 'leftRoad', side } });
        this.recover();
        events.push({ type: 'rumbleStrip', side: null });
        return;
      }
      // Slow enough: the truck rolls onto the gravel shoulder instead of crashing.
      t.lateralOffset = y > 0 ? C.offRoadOffset : C.leftOffRoadOffset;
      if (t.lateralVelocity * y > 0) t.lateralVelocity = 0;
      t.speed *= 0.995;
      t.headingError = 0;
      if (this.time - this.lastShoulderWarning > 4) {
        this.lastShoulderWarning = this.time;
        events.push({ type: 'onShoulder', side });
      }
    }
    const side = y > C.rumbleOffset ? 'right' : y < C.leftRumbleOffset ? 'left' : null;
    if (side !== this.rumbleSide) {
      this.rumbleSide = side;
      events.push({ type: 'rumbleStrip', side });
    }
  }

  checkCurves(events) {
    const t = this.truck;
    const lookahead = Math.max(200, t.speed * 10);
    const curve = this.road.nextCurve(t.position, lookahead);
    if (curve && curve.segmentIndex !== this.announcedCurveIndex && t.speed > 2) {
      this.announcedCurveIndex = curve.segmentIndex;
      events.push({ type: 'curveAhead', curve });
    }
    const k = Math.abs(this.road.curvature(t.position));
    const lateralNeeded = t.speed * t.speed * k;
    if (k > 0 && lateralNeeded > this.spec.steeringLatAccel * 0.85 && this.time - this.lastTooFastWarning > 4) {
      this.lastTooFastWarning = this.time;
      events.push({ type: 'tooFastForCurve' });
    }
  }

  // MARK: Traffic

  /** Vehicles within earshot, nearest first (at most four), for the 3D traffic sound. */
  get trafficSounds() {
    const t = this.truck;
    return this.traffic
      .map((v) => {
        const rel = v.position - t.position;
        const approach = v.oncoming ? t.speed + v.speed : t.speed - v.speed;
        return { id: v.id, kind: v.kind, distance: rel, lateral: v.lane - t.lateralOffset, closingSpeed: rel >= 0 ? approach : -approach };
      })
      .filter((s) => Math.abs(s.distance) < 500)
      .sort((a, b) => Math.abs(a.distance) - Math.abs(b.distance))
      .slice(0, 4);
  }

  stepTraffic(dt, events) {
    if (!this.trafficEnabled) return;
    const t = this.truck;
    const road = this.road;
    const pos = t.position;
    const roadAhead = road.loops ? Infinity : road.totalLength - pos;
    const limit = road.speedLimit;

    this.oncomingTimer -= dt;
    if (this.oncomingTimer <= 0) {
      this.oncomingTimer = this.rng.range(25, 70);
      if (!road.leftLaneSameDirection && roadAhead > 800) {
        this.nextVehicleID += 1;
        this.traffic.push({ id: this.nextVehicleID, kind: this.randomKind(), oncoming: true, lane: C.leftLaneCenter, position: pos + 700, speed: limit * this.rng.range(0.85, 1) });
      }
    }
    this.slowTimer -= dt;
    if (this.slowTimer <= 0) {
      const hasSlowAhead = this.traffic.some((v) => !v.oncoming && v.position > pos);
      if (!hasSlowAhead && roadAhead > 900 && t.speed > 5) {
        this.nextVehicleID += 1;
        this.traffic.push({ id: this.nextVehicleID, kind: this.randomKind(), oncoming: false, lane: 0, position: pos + 500, speed: limit * this.rng.range(0.55, 0.75) });
        this.slowTimer = this.rng.range(70, 160);
      } else {
        this.slowTimer = 10;
      }
    }

    const remove = new Set();
    const y = t.lateralOffset;
    for (const v of this.traffic) {
      v.position += (v.oncoming ? -v.speed : v.speed) * dt;
      const rel = v.position - pos;
      if (rel < -300 || rel > 1200 || (!road.loops && !v.oncoming && v.position > road.totalLength - 80)) {
        remove.add(v.id);
        continue;
      }
      const lateralOverlap = Math.abs(y - v.lane) < 1.25 + vehicleHalfWidth(v.kind);
      const front = v.position - vehicleLength(v.kind) / 2;
      const back = v.position + vehicleLength(v.kind) / 2;
      if (lateralOverlap && front < pos && back > pos - C.truckLength) {
        events.push({ type: 'crashed', reason: { kind: 'collision', headOn: v.oncoming, vehicle: v.kind } });
        remove.add(v.id);
        this.recover();
        events.push({ type: 'rumbleStrip', side: null });
        continue;
      }
      if (v.oncoming) {
        if (rel > 0 && rel < 250 && y < -1.2 && !this.honked.has(v.id)) {
          this.honked.add(v.id);
          events.push({ type: 'oncomingHorn' });
          if (this.time - this.lastWrongSideWarning > 4) {
            this.lastWrongSideWarning = this.time;
            events.push({ type: 'wrongSideOfRoad' });
          }
        }
      } else if (Math.abs(y - v.lane) < 2 && rel > 0) {
        const closing = t.speed - v.speed;
        if (rel < 160 && closing > 1.5 && !this.warnedAhead.has(v.id)) {
          this.warnedAhead.add(v.id);
          events.push({ type: 'vehicleAhead', distance: rel, speed: v.speed, kind: v.kind });
        }
        const gap = rel - vehicleLength(v.kind) / 2;
        if (closing > 0.5 && gap < Math.max(15, closing * 2.5) && this.time - this.lastTooClose > 3) {
          this.lastTooClose = this.time;
          events.push({ type: 'tooClose' });
        }
      }
    }
    if (remove.size) this.traffic = this.traffic.filter((v) => !remove.has(v.id));
  }

  randomKind() {
    const r = this.rng.next();
    return r < 0.55 ? 'car' : r < 0.8 ? 'pickup' : 'truck';
  }

  clearTraffic() {
    this.traffic = [];
    this.warnedAhead = new Set();
    this.honked = new Set();
  }
}
