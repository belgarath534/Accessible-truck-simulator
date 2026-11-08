// What a drive is for, and how it went.

export const freeDriveGoal = { name: 'Free Drive', distance: null };

export function practiceGoal(road) {
  return { name: 'Practice Drive', distance: road.totalLength };
}

export function destinationGoal(name, distance) {
  return { name, distance };
}

export function newStats() {
  return {
    drivingTime: 0,
    distance: 0,
    crashes: 0,
    topSpeed: 0,
    tooFastWarnings: 0,
    fuelUsedLiters: 0,
    fuelBoughtLiters: 0,
    fuelCost: 0,
    tows: 0,
    towCost: 0,
    tickets: 0,
    ticketCost: 0,
  };
}

export function averageSpeed(stats) {
  return stats.drivingTime > 0 ? stats.distance / stats.drivingTime : 0;
}

export const ARRIVAL_TOLERANCE = 60;

/** 'perfect', 'good' or 'overshot', from metres past the drop-off (negative = before it). */
export function stopRating(stopError) {
  if (Math.abs(stopError) <= 15) return 'perfect';
  if (stopError <= ARRIVAL_TOLERANCE) return 'good';
  return 'overshot';
}
