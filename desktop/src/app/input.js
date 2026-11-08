// Keyboard and game controller input.
//
// Keyboard: Up / W accelerate, Down / S brake, Left / A and Right / D steer,
// [ and ] turn signals, Backspace cancel signal, I dashboard, G GPS, N engine, H horn, Escape pause.
// Controller (Xbox layout): right trigger accelerate, left trigger brake, left stick steer,
// LB / RB turn signals, A dashboard, X GPS, Y engine, B horn, Menu pause.

const KEY_ACTIONS = {
  BracketLeft: { type: 'signal', side: 'left' },
  BracketRight: { type: 'signal', side: 'right' },
  Backspace: { type: 'cancelSignal' },
  KeyI: { type: 'speakDashboard' },
  KeyG: { type: 'speakRoadAhead' },
  KeyN: { type: 'toggleEngine' },
  KeyH: { type: 'horn' },
  Escape: { type: 'pause' },
  F1: { type: 'help' },
};

const PAD_ACTIONS = {
  0: { type: 'speakDashboard' }, // A
  1: { type: 'horn' }, // B
  2: { type: 'speakRoadAhead' }, // X
  3: { type: 'toggleEngine' }, // Y
  4: { type: 'signal', side: 'left' }, // LB
  5: { type: 'signal', side: 'right' }, // RB
  8: { type: 'cancelSignal' }, // View
  9: { type: 'pause' }, // Menu
};

const DRIVE_KEYS = new Set(['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'KeyW', 'KeyA', 'KeyS', 'KeyD']);

export class Input {
  constructor() {
    this.down = new Set();
    this.padPressed = new Map();
    this.onAction = null;
    this.enabled = false;
    this.keydown = (e) => {
      if (!this.enabled) return;
      if (DRIVE_KEYS.has(e.code)) {
        this.down.add(e.code);
        e.preventDefault();
        return;
      }
      const action = KEY_ACTIONS[e.code];
      if (action) {
        e.preventDefault();
        if (!e.repeat) this.onAction?.(action);
      }
    };
    this.keyup = (e) => this.down.delete(e.code);
    this.blur = () => this.down.clear();
    window.addEventListener('keydown', this.keydown, true);
    window.addEventListener('keyup', this.keyup, true);
    window.addEventListener('blur', this.blur);
  }

  reset() {
    this.down.clear();
  }

  /** Continuous controls, polled every frame; also fires controller button actions. */
  poll() {
    const k = (...codes) => codes.some((c) => this.down.has(c));
    let throttle = k('ArrowUp', 'KeyW') ? 1 : 0;
    let brake = k('ArrowDown', 'KeyS') ? 1 : 0;
    let steer = (k('ArrowRight', 'KeyD') ? 1 : 0) - (k('ArrowLeft', 'KeyA') ? 1 : 0);
    for (const pad of navigator.getGamepads?.() ?? []) {
      if (!pad) continue;
      throttle = Math.max(throttle, pad.buttons[7]?.value ?? 0);
      brake = Math.max(brake, pad.buttons[6]?.value ?? 0);
      const x = pad.axes[0] ?? 0;
      if (Math.abs(x) > 0.08) steer += x;
      for (const [index, action] of Object.entries(PAD_ACTIONS)) {
        const pressed = !!pad.buttons[index]?.pressed;
        const key = `${pad.index}:${index}`;
        if (pressed && !this.padPressed.get(key) && this.enabled) this.onAction?.(action);
        this.padPressed.set(key, pressed);
      }
    }
    return { throttle, brake, steer: Math.max(-1, Math.min(1, steer)) };
  }
}
