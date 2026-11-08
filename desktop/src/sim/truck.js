// Truck models. Same numbers as the iPhone version.

const STARTER = {
  id: 'old_reliable',
  name: 'Old Reliable',
  price: 0,
  summary: 'Your first truck. Steady six-cylinder with a little turbo: nothing fancy, never lets you down.',
  sound: { recorded: true, pitch: 1, roughness: 0.3, turbo: 0.3, bark: 0.2, lope: 0.1 },
  massKg: 16000,
  torqueCurve: [[600, 1000], [1000, 1700], [1400, 1800], [1800, 1500], [2100, 1100]],
  idleRPM: 600,
  maxRPM: 2100,
  cylinders: 6,
  engineStartSeconds: 1.8,
  gearRatios: [12.0, 9.0, 6.8, 5.1, 3.9, 2.9, 2.2, 1.7, 1.3, 1.0],
  finalDrive: 3.4,
  drivetrainEfficiency: 0.9,
  shiftUpRPM: 1700,
  shiftDownRPM: 1000,
  shiftSeconds: 0.5,
  wheelRadius: 0.5,
  maxBrakeDecel: 4.0,
  engineBrakeFraction: 0.12,
  dragArea: 6.0,
  rollingResistance: 0.006,
  tractionLimitAccel: 2.4,
  wheelbase: 4.0,
  steeringLatAccel: 3.0,
  maxSteerAngle: 0.6,
  steerRate: 0.6,
  fuelCapacityLiters: 400,
  speedLimiter: 90 / 3.6,
};

export const starter = STARTER;

export const workhorse = {
  ...STARTER,
  id: 'workhorse',
  name: 'Workhorse',
  price: 6000,
  summary: 'An old, tough truck. A bit less power, but it grips the road better in curves. Rough, clattery diesel with a lumpy idle and no turbo.',
  torqueCurve: [[600, 1100], [1000, 1600], [1300, 1650], [1800, 1300], [2100, 900]],
  steeringLatAccel: 3.5,
  maxBrakeDecel: 4.2,
  fuelCapacityLiters: 350,
  speedLimiter: 85 / 3.6,
  sound: { recorded: false, pitch: 1.1, roughness: 0.9, turbo: 0, bark: 0.45, lope: 0.7 },
};

export const roadKing = {
  ...STARTER,
  id: 'road_king',
  name: 'Road King',
  price: 18000,
  summary: 'The big rig. Much more power, stronger brakes and a bigger fuel tank, even with heavy loads. Deep V8 rumble with a loud turbo whistle.',
  massKg: 17500,
  torqueCurve: [[600, 1500], [1000, 2500], [1400, 2700], [1800, 2300], [2100, 1700]],
  cylinders: 8,
  tractionLimitAccel: 2.8,
  maxBrakeDecel: 5.0,
  steeringLatAccel: 3.2,
  fuelCapacityLiters: 600,
  speedLimiter: 100 / 3.6,
  sound: { recorded: false, pitch: 0.82, roughness: 0.35, turbo: 1, bark: 0.6, lope: 0.35 },
};

export const catalog = [starter, workhorse, roadKing];

export function withID(id) {
  return catalog.find((t) => t.id === id) ?? starter;
}

/** Engine torque (N·m) at an RPM: linear interpolation over the curve, zero above the red line. */
export function torqueAt(spec, rpm) {
  const curve = spec.torqueCurve;
  if (curve.length === 0) return 0;
  const [firstRPM, firstT] = curve[0];
  const [lastRPM, lastT] = curve[curve.length - 1];
  if (rpm <= firstRPM) return firstT;
  if (rpm >= lastRPM) return rpm > spec.maxRPM ? 0 : lastT;
  for (let i = 1; i < curve.length; i++) {
    if (rpm <= curve[i][0]) {
      const [aR, aT] = curve[i - 1];
      const [bR, bT] = curve[i];
      return aT + ((bT - aT) * (rpm - aR)) / (bR - aR);
    }
  }
  return lastT;
}

export function peakTorque(spec) {
  return Math.max(...spec.torqueCurve.map(([, t]) => t));
}

export function horsepower(spec) {
  const watts = Math.max(...spec.torqueCurve.map(([r, t]) => (t * r * 2 * Math.PI) / 60));
  return Math.round(watts / 745.7 / 10) * 10;
}
