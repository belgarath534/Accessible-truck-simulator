// Roads: segments of straights and curves. Positions are metres along the road.
// Curvature sign convention: positive bends to the RIGHT.

export const straight = (length) => ({ kind: 'straight', length });
export const left = (radius, length) => ({ kind: 'curve', direction: 'left', radius, length });
export const right = (radius, length) => ({ kind: 'curve', direction: 'right', radius, length });

export function peakCurvature(seg) {
  if (seg.kind === 'straight') return 0;
  return (seg.direction === 'right' ? 1 : -1) / seg.radius;
}

export function curveSeverity(radius) {
  if (radius < 250) return 'sharp';
  if (radius < 700) return 'moderate';
  return 'gentle';
}

export class Road {
  /** Comfortable lateral acceleration used to compute advisory speeds, m/s². */
  static comfortLatAccel = 1.8;

  constructor(segments, { loops = true, speedLimit = 80 / 3.6, truckStops = [] } = {}) {
    this.segments = segments;
    this.loops = loops;
    this.speedLimit = speedLimit;
    this.laneWidth = 3.7;
    this.transitionLength = 40;
    this.truckStops = [...truckStops].sort((a, b) => a - b);
    this.speedZones = [];
    this.policeSpots = [];
    this.leftLaneSameDirection = false;
    this.starts = [];
    let s = 0;
    for (const seg of segments) {
      this.starts.push(s);
      s += seg.length;
    }
    this.totalLength = s;
  }

  normalized(s) {
    if (!this.loops || this.totalLength <= 0) return Math.min(Math.max(s, 0), this.totalLength);
    const r = s % this.totalLength;
    return r < 0 ? r + this.totalLength : r;
  }

  segmentIndex(position) {
    const s = this.normalized(position);
    let lo = 0;
    let hi = this.segments.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (this.starts[mid] <= s) lo = mid;
      else hi = mid - 1;
    }
    return lo;
  }

  /** Road curvature at a position (1/m, positive = bends right). Ramps in and out of curves. */
  curvature(position) {
    if (this.segments.length === 0) return 0;
    const s = this.normalized(position);
    const i = this.segmentIndex(s);
    const seg = this.segments[i];
    const k = peakCurvature(seg);
    if (k === 0) return 0;
    const into = s - this.starts[i];
    const remaining = seg.length - into;
    const ramp = Math.min(this.transitionLength, seg.length / 2);
    return k * Math.min(1, Math.min(into, remaining) / ramp);
  }

  /** Speed limit at a position (towns are slower). */
  speedLimitAt(position) {
    const zone = this.speedZone(position);
    return zone ? zone.limit : this.speedLimit;
  }

  speedZone(position) {
    return this.speedZones.find((z) => position >= z.start && position < z.end) ?? null;
  }

  /** The next truck stop ahead: { index, distance } or null. Wraps on looping roads. */
  nextTruckStop(position) {
    if (this.truckStops.length === 0) return null;
    const s = this.normalized(position);
    const i = this.truckStops.findIndex((t) => t >= s);
    if (i >= 0) return { index: i, distance: this.truckStops[i] - s };
    if (!this.loops) return null;
    return { index: 0, distance: this.truckStops[0] + this.totalLength - s };
  }

  /** Puts truck stops in the middle of the given segments. */
  withTruckStops(indices) {
    this.truckStops = indices.map((i) => this.starts[i] + this.segments[i].length / 2).sort((a, b) => a - b);
    return this;
  }

  /** The next curve starting within `lookahead` metres (not the one the truck is already in). */
  nextCurve(position, lookahead) {
    if (this.segments.length === 0) return null;
    const s = this.normalized(position);
    const current = this.segmentIndex(s);
    let distance = this.starts[current] + this.segments[current].length - s;
    let i = current;
    for (let n = 0; n < this.segments.length; n++) {
      i += 1;
      if (i >= this.segments.length) {
        if (!this.loops) return null;
        i = 0;
      }
      if (distance > lookahead) return null;
      const seg = this.segments[i];
      if (seg.kind === 'curve') {
        return {
          segmentIndex: i,
          direction: seg.direction,
          radius: seg.radius,
          severity: curveSeverity(seg.radius),
          distance,
          advisorySpeed: Math.min(this.speedLimit, Math.sqrt(Road.comfortLatAccel * seg.radius)),
        };
      }
      distance += seg.length;
    }
    return null;
  }
}

/** A ~12 km country loop: long straights to get up to speed, then curves of every kind in both directions. */
export function practiceLoop() {
  return new Road([
    straight(800), right(900, 400), straight(600), left(500, 350), straight(400), right(350, 300),
    straight(700), left(1200, 500), straight(300), left(220, 250), straight(250), right(220, 250),
    straight(900), right(600, 450), straight(500), left(400, 400), straight(600), right(160, 220),
    straight(1000), left(800, 600), straight(1200),
  ]).withTruckStops([6, 12, 20]);
}
