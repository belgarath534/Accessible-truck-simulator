// Player settings, saved on this computer.

const DEFAULTS = {
  units: 'imperial',
  assist: 'medium',
  speechMode: 'auto',
  voiceRate: 1.1,
  volume: 0.8,
  laneTone: true,
  announceSpeed: true,
  announceGears: false,
  tutorialDone: false,
};

const KEY = 'truckSim.settings';

export function loadSettings() {
  let saved = {};
  try {
    saved = JSON.parse(localStorage.getItem(KEY) ?? '{}');
  } catch {
    saved = {};
  }
  const settings = { ...DEFAULTS, ...saved };
  return new Proxy(settings, {
    set(target, prop, value) {
      target[prop] = value;
      try {
        localStorage.setItem(KEY, JSON.stringify(target));
      } catch {
        // Not saved; the game still works this session.
      }
      return true;
    },
  });
}
