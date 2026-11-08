// Deterministic random numbers (SplitMix64), so drives and tests can be repeated with a seed.
const MASK = (1n << 64n) - 1n;

export class SeededRandom {
  constructor(seed = Math.floor(Math.random() * 2 ** 52) + 1) {
    this.state = (BigInt(seed) + 0x9e3779b97f4a7c15n) & MASK;
  }

  nextBig() {
    this.state = (this.state + 0x9e3779b97f4a7c15n) & MASK;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & MASK;
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & MASK;
    return z ^ (z >> 31n);
  }

  /** A number in [0, 1). */
  next() {
    return Number(this.nextBig() >> 11n) / 2 ** 53;
  }

  /** A number in [lo, hi]. */
  range(lo, hi) {
    return lo + (hi - lo) * this.next();
  }

  pick(array) {
    return array[Math.floor(this.next() * array.length)];
  }
}
