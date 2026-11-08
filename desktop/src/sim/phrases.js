// Everything the game says. A port of Phrases.swift, so Windows and iPhone speak the same way.

import { C } from './session.js';
import { averageSpeed, stopRating } from './trip.js';
import { horsepower } from './truck.js';

const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;

export class Units {
  constructor(system = 'imperial') {
    this.system = system;
  }

  get metric() {
    return this.system === 'metric';
  }

  speed(mps) {
    return Math.round(mps * (this.metric ? 3.6 : 2.23694));
  }

  get speedUnitSpoken() {
    return this.metric ? 'kilometers per hour' : 'miles per hour';
  }

  /** Distances rounded the way a co-driver would say them. */
  distance(metres) {
    if (this.metric) {
      if (metres >= 1000) {
        const km = Math.round(metres / 100) / 10;
        return km === Math.round(km) ? `${km} kilometers` : `${km.toFixed(1)} kilometers`;
      }
      const rounded = metres >= 200 ? Math.round(metres / 50) * 50 : Math.round(metres / 10) * 10;
      return `${rounded} meters`;
    }
    const feet = metres * 3.28084;
    if (feet >= 1000) {
      const miles = Math.round((metres / 1609.34) * 10) / 10;
      return miles === 1 ? '1 mile' : `${miles.toFixed(1)} miles`;
    }
    return `${Math.round(feet / 50) * 50} feet`;
  }
}

/** "$12,450" (screen readers read this as dollars). */
export function money(amount) {
  const grouped = Math.abs(Math.round(amount)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return (amount < 0 ? 'minus $' : '$') + grouped;
}

export class Phrases {
  constructor(units) {
    this.units = units instanceof Units ? units : new Units(units);
  }

  curve(c) {
    const u = this.units;
    let text = `${cap(c.severity)} ${c.direction} curve in ${u.distance(c.distance)}`;
    if (c.severity !== 'gentle') text += `, slow to ${u.speed(c.advisorySpeed)}`;
    return text + '.';
  }

  duration(seconds, roundToMinutes = false) {
    if (roundToMinutes) return plural(Math.round(seconds / 60), 'minute');
    const total = Math.round(seconds);
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    if (h > 0) return `${plural(h, 'hour')} ${plural(m, 'minute')}`;
    if (m > 0) return `${plural(m, 'minute')} ${plural(s, 'second')}`;
    return plural(s, 'second');
  }

  roadAhead({ curve, remaining = null, timeLeft = null, truckStop = null }) {
    let text = '';
    if (remaining != null) text = remaining > 0 ? `${this.units.distance(remaining)} to the drop-off. ` : "You're at the drop-off. ";
    if (timeLeft != null) text += timeLeft > 0 ? `${this.duration(timeLeft, timeLeft >= 120)} left. ` : "You're late. ";
    const stop = truckStop != null ? ' ' + this.roadAheadTruckStop(truckStop) : '';
    if (!curve) return text + 'Straight road ahead.' + stop;
    return text + 'Next: ' + this.curve(curve) + stop;
  }

  tripProgress(remaining) {
    return `${this.units.distance(remaining)} to the drop-off.`;
  }

  destinationAhead(distance) {
    return `Drop-off in ${this.units.distance(distance)}. Slow down and stop at the drop-off.`;
  }

  atDestination = "You're at the drop-off. Stop now.";

  fuelLow(fraction, nextStop, urgent) {
    let text = urgent ? `Fuel very low, ${Math.round(fraction * 100)} percent!` : 'Fuel low, a quarter tank.';
    if (nextStop != null) text += ` Next truck stop in ${this.units.distance(nextStop)}. Signal right before it and slow down to pull in.`;
    return text;
  }

  truckStopAhead(distance) {
    const u = this.units;
    return `Truck stop in ${u.distance(distance)}. To fill up, signal right and slow below ${u.speed(C.truckStopExitSpeed)} before you reach it.`;
  }

  pulledIntoTruckStop = 'Pulling into the truck stop. Stop at the pump to fill up.';
  refuelStarted = 'Filling up.';
  leftTruckStop = 'Back on the road.';

  missedTruckStop(tooFast) {
    return tooFast ? 'Too fast to take the truck stop exit. You missed it.' : 'You passed the truck stop.';
  }

  refueled(liters, cost) {
    const amount = this.units.metric ? `${Math.round(liters)} liters` : `${Math.round(liters * 0.26417)} gallons`;
    return `Filled up: ${amount} for ${money(cost)}. Back on the road when you're ready.`;
  }

  towed(cost, fuelCost) {
    return `A tow truck took you to the next truck stop and put in a quarter tank. Tow ${money(cost)}, fuel ${money(fuelCost)}. That took 2 minutes. Start the engine to go on.`;
  }

  roadAheadTruckStop(distance) {
    return `Next truck stop in ${this.units.distance(distance)}.`;
  }

  // Map and GPS

  turnPhrase(turn) {
    return { left: 'turn left', right: 'turn right', straight: 'go straight', uTurn: 'turn around' }[turn];
  }

  navInstruction(n) {
    const signal = { left: ' Signal left.', right: ' Signal right.', straight: ' No signal needed.', uTurn: '' }[n.turn];
    return `In ${this.units.distance(n.distance)}, ${this.turnPhrase(n.turn)} onto ${n.roadName} toward ${n.toward}.${signal}`;
  }

  junctionAhead(choices, distance) {
    const order = ['left', 'straight', 'right', 'uTurn'];
    const parts = [...choices]
      .sort((a, b) => order.indexOf(a.turn) - order.indexOf(b.turn))
      .map((c) => ({
        left: `left on ${c.roadName} to ${c.toward}`,
        right: `right on ${c.roadName} to ${c.toward}`,
        straight: `straight on ${c.roadName} to ${c.toward}`,
        uTurn: `turn around to ${c.toward}`,
      })[c.turn]);
    const d = this.units.distance(distance);
    if (parts.length === 1) return `In ${d}, the road continues: ${parts[0]}.`;
    return `Junction in ${d}: ${parts.join(', ')}. Signal to choose.`;
  }

  tookRoad(roadName, toward, length) {
    return `${roadName} toward ${toward}, ${this.units.distance(length)}.`;
  }

  rerouted(remaining) {
    return `That's off the route. Recalculating. New route: ${this.units.distance(remaining)} to the drop-off.`;
  }

  missedDropOff = 'You drove past the drop-off. Recalculating a way back.';

  enteredTown(name, limit) {
    return `Entering ${name}. Speed limit ${this.units.speed(limit)}.`;
  }

  leftTown(name, limit) {
    return `Leaving ${name}. Speed limit ${this.units.speed(limit)}.`;
  }

  // Traffic

  changedLane(toLeft, oncoming) {
    if (!toLeft) return 'Back in your lane.';
    return oncoming ? 'Oncoming lane. Pass quickly and get back.' : 'Left lane.';
  }

  wrongSideOfRoad = 'Oncoming traffic! Get back in your lane!';
  tooClose = 'Too close! Brake!';

  vehicleAhead(distance, speed, kind) {
    return `Slow ${kind} ahead, ${this.units.distance(distance)}, doing ${this.units.speed(speed)}. Slow down or pass.`;
  }

  // Police

  policeChase(speed, limit) {
    const u = this.units;
    return `Police! You were doing ${u.speed(speed)} in a ${u.speed(limit)}. Pull over: slow down and stop.`;
  }

  speedingTicket(speed, limit, fine) {
    const u = this.units;
    return `Speeding ticket: ${u.speed(speed)} in a ${u.speed(limit)}. Fine ${money(fine)}. You can go.`;
  }

  fledPolice(fine) {
    return `You didn't stop for the police. Fine ${money(fine)}.`;
  }

  onShoulder(side) {
    return `On the ${side} shoulder. Steer ${side === 'left' ? 'right' : 'left'} to get back on the road.`;
  }

  stoppedShort(remaining) {
    return `The drop-off is ${this.units.distance(remaining)} ahead. Keep going.`;
  }

  timeLeft(seconds) {
    return seconds >= 120 ? `${this.duration(seconds, true)} left to deliver.` : 'One minute left to deliver!';
  }

  lateForDelivery = "You're late. The pay drops a little for every minute.";

  weight(kg) {
    return this.units.metric ? `${Math.round(kg / 1000)} tonnes` : `${Math.round((kg * 2.20462) / 2000)} tons`;
  }

  truck(t) {
    const u = this.units;
    const tank = u.metric ? `${t.fuelCapacityLiters} liter tank` : `${Math.round(t.fuelCapacityLiters * 0.26417)} gallon tank`;
    return `${t.name}. ${horsepower(t)} horsepower, top speed ${u.speed(t.speedLimiter)} ${u.speedUnitSpoken}, ${tank}. ${t.summary}`;
  }

  payout(p) {
    const lines = p.lines.map((l) => (l.amount < 0 ? `${l.label}: minus ${money(-l.amount)}.` : `${l.label}: ${money(l.amount)}.`));
    const total = p.total >= 0 ? `You earned ${money(p.total)}.` : `This drive cost you ${money(-p.total)}.`;
    return [...lines, total].join(' ');
  }

  /** The trip status shown in the pause menu. */
  tripStatus({ goal, stats, remaining, timeLeft = null, earnedSoFar = null }) {
    const u = this.units;
    const parts = [goal.name + '.'];
    if (goal.distance != null && remaining != null) {
      const left = Math.max(0, remaining);
      const percent = Math.round(Math.min(1, stats.distance / goal.distance) * 100);
      parts.push(`${u.distance(stats.distance)} driven, ${u.distance(left)} to the drop-off, ${percent} percent done.`);
    } else {
      parts.push(`No destination: drive as long as you like. ${u.distance(stats.distance)} driven.`);
    }
    parts.push(`Driving time ${this.duration(stats.drivingTime)}.`);
    if (stats.drivingTime > 0) {
      parts.push(`Average speed ${u.speed(averageSpeed(stats))}, top speed ${u.speed(stats.topSpeed)} ${u.speedUnitSpoken}.`);
    }
    parts.push(stats.crashes === 0 ? 'No crashes.' : `Crashes: ${stats.crashes}.`);
    if (timeLeft != null) parts.push(timeLeft > 0 ? `Time left: ${this.duration(timeLeft)}.` : `Late by ${this.duration(-timeLeft)}.`);
    if (earnedSoFar != null) parts.push(`Earned so far: ${money(earnedSoFar)}.`);
    return parts.join(' ');
  }

  arrived(s) {
    const u = this.units;
    let stop;
    const rating = stopRating(s.stopError);
    if (rating === 'perfect') stop = 'Perfect stop, right at the drop-off.';
    else if (rating === 'good') stop = `Good stop, ${u.distance(Math.abs(s.stopError))} ${s.stopError >= 0 ? 'past' : 'before'} the drop-off.`;
    else stop = `You stopped ${u.distance(s.stopError)} past the drop-off.`;
    return `Delivered! ${s.goalName} complete. ${stop} ` + this.tripResults(s.stats);
  }

  tripResults(st) {
    const u = this.units;
    const parts = [
      `Time ${this.duration(st.drivingTime)}.`,
      `Distance ${u.distance(st.distance)}.`,
      `Average speed ${u.speed(averageSpeed(st))}, top speed ${u.speed(st.topSpeed)} ${u.speedUnitSpoken}.`,
      st.crashes === 0 ? 'No crashes.' : `Crashes: ${st.crashes}.`,
    ];
    if (st.tooFastWarnings > 0) parts.push(`Too fast for a curve ${plural(st.tooFastWarnings, 'time')}.`);
    parts.push(u.metric ? `Fuel used ${Math.round(st.fuelUsedLiters)} liters.` : `Fuel used ${(st.fuelUsedLiters * 0.26417).toFixed(1)} gallons.`);
    return parts.join(' ');
  }

  dashboard(d) {
    const u = this.units;
    const parts = [`${u.speed(d.speed)} ${u.speedUnitSpoken}`];
    if (d.engine === 'off') parts.push('engine off');
    else if (d.engine === 'starting') parts.push('engine starting');
    else parts.push(`gear ${d.gear}`, `${Math.round(d.rpm / 50) * 50} RPM`);
    parts.push(`fuel ${Math.round(d.fuelFraction * 100)} percent, about ${u.distance(d.range)} left`);
    const temp = u.metric ? Math.round(d.engineTempC) : Math.round((d.engineTempC * 9) / 5 + 32);
    parts.push(`engine temperature ${temp} degrees`);
    if (d.signal !== 'off') parts.push(`${d.signal} signal on`);
    parts.push(`limit ${u.speed(d.speedLimit)}`);
    return parts.join(', ') + '.';
  }

  signal(s) {
    return s === 'off' ? 'Signal off.' : `${cap(s)} signal.`;
  }

  crash(reason) {
    if (reason.kind === 'leftRoad') return `Crash! You ran off the ${reason.side} side of the road. Truck recovered to the lane.`;
    return reason.headOn
      ? `Crash! Head-on with an oncoming ${reason.vehicle}. Stay in your lane when traffic is coming.`
      : `Crash! You hit the ${reason.vehicle} in front of you. Slow down sooner behind traffic.`;
  }
}
