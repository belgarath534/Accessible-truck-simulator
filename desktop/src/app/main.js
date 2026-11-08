// The game window: menus, settings and drives.

import { GameAudio } from './audio.js';
import { Speech } from './speech.js';
import { Input } from './input.js';
import { DriveView } from './view.js';
import { Drive } from './drive.js';
import { loadSettings } from './settings.js';

const $ = (id) => document.getElementById(id);
const settings = loadSettings();
const audio = new GameAudio();
const speech = new Speech();
const input = new Input();
const view = new DriveView($('drive-canvas'));
let drive = null;
let lastMode = 'practice';

function applySpeechSettings() {
  speech.mode = settings.speechMode;
  speech.rate = settings.voiceRate;
}
applySpeechSettings();

// MARK: Screens

function show(id) {
  for (const el of document.querySelectorAll('.screen')) el.hidden = el.id !== id;
  const target = id === 'drive' ? $('drive-surface') : document.querySelector(`#${id} h1`);
  requestAnimationFrame(() => target?.focus());
}

function showMenu() {
  const done = settings.tutorialDone;
  $('btn-tutorial-first').hidden = done;
  $('btn-tutorial').hidden = !done;
  $('pause').hidden = true;
  $('results').hidden = true;
  show('menu');
  requestAnimationFrame(() => (done ? $('btn-practice') : $('btn-tutorial-first')).focus());
}

// Up and Down arrows move between buttons in a list, like a game menu.
document.addEventListener('keydown', (e) => {
  if (!['ArrowUp', 'ArrowDown'].includes(e.key)) return;
  const list = document.activeElement?.closest('.buttons');
  if (!list) return;
  const buttons = [...list.querySelectorAll('button')].filter((b) => !b.hidden);
  const i = buttons.indexOf(document.activeElement);
  if (i < 0) return;
  e.preventDefault();
  buttons[(i + (e.key === 'ArrowDown' ? 1 : buttons.length - 1)) % buttons.length].focus();
});

// MARK: Drives

async function startDrive(mode) {
  lastMode = mode;
  await audio.init().catch((err) => console.error('Audio failed to start', err));
  show('drive');
  drive = new Drive({
    mode,
    settings,
    audio,
    speech,
    input,
    view,
    onPause: (status) => {
      $('pause-status').textContent = status;
      $('pause').hidden = false;
      requestAnimationFrame(() => $('btn-resume').focus());
    },
    onFinish: ({ title, text }) => {
      $('results-title').textContent = title;
      $('results-text').textContent = text;
      $('btn-again').hidden = mode === 'tutorial';
      $('results').hidden = false;
      requestAnimationFrame(() => ($('btn-again').hidden ? $('btn-results-menu') : $('btn-again')).focus());
    },
  });
  drive.start();
}

function endDrive() {
  drive?.stop();
  drive = null;
  showMenu();
}

function resume() {
  $('pause').hidden = true;
  drive?.resume();
  $('drive-surface').focus();
}

$('btn-tutorial-first').onclick = () => startDrive('tutorial');
$('btn-tutorial').onclick = () => startDrive('tutorial');
$('btn-practice').onclick = () => startDrive('practice');
$('btn-help').onclick = () => show('help');
$('btn-settings').onclick = () => {
  fillSettings();
  show('settings');
};
$('btn-quit').onclick = () => (window.truckSim?.quit ? window.truckSim.quit() : window.close());
for (const b of document.querySelectorAll('.back')) b.onclick = showMenu;

$('btn-resume').onclick = resume;
$('btn-restart').onclick = () => {
  $('pause').hidden = true;
  drive?.restart();
  $('drive-surface').focus();
};
$('btn-quit-drive').onclick = endDrive;
$('btn-again').onclick = () => {
  $('results').hidden = true;
  drive?.stop();
  startDrive(lastMode);
};
$('btn-results-menu').onclick = endDrive;
$('pause').addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    e.preventDefault();
    e.stopPropagation();
    resume();
  }
});
// Keep focus inside an open dialog.
for (const dialog of [$('pause'), $('results')]) {
  dialog.addEventListener('keydown', (e) => {
    if (e.key !== 'Tab') return;
    const buttons = [...dialog.querySelectorAll('button')].filter((b) => !b.hidden);
    const i = buttons.indexOf(document.activeElement);
    e.preventDefault();
    buttons[(i + (e.shiftKey ? buttons.length - 1 : 1)) % buttons.length].focus();
  });
}

// MARK: Settings

function fillSettings() {
  $('set-speech').value = settings.speechMode;
  $('set-rate').value = settings.voiceRate;
  $('set-units').value = settings.units;
  $('set-assist').value = settings.assist;
  $('set-volume').value = settings.volume;
  $('set-lane').checked = settings.laneTone;
  $('set-speed').checked = settings.announceSpeed;
  $('set-gears').checked = settings.announceGears;
  $('set-rate').setAttribute('aria-valuetext', `${Math.round(settings.voiceRate * 100)} percent`);
  $('set-volume').setAttribute('aria-valuetext', `${Math.round(settings.volume * 100)} percent`);
}

$('set-speech').onchange = (e) => {
  settings.speechMode = e.target.value;
  applySpeechSettings();
  speech.speak('Speech changed.', 'high');
};
$('set-rate').oninput = (e) => {
  settings.voiceRate = Number(e.target.value);
  e.target.setAttribute('aria-valuetext', `${Math.round(settings.voiceRate * 100)} percent`);
  applySpeechSettings();
};
$('set-rate').onchange = () => {
  if (!speech.usesScreenReader) speech.speak('This is how fast the voice speaks.', 'high');
};
$('set-units').onchange = (e) => (settings.units = e.target.value);
$('set-assist').onchange = (e) => (settings.assist = e.target.value);
$('set-volume').oninput = (e) => {
  settings.volume = Number(e.target.value);
  e.target.setAttribute('aria-valuetext', `${Math.round(settings.volume * 100)} percent`);
};
$('set-lane').onchange = (e) => (settings.laneTone = e.target.checked);
$('set-speed').onchange = (e) => (settings.announceSpeed = e.target.checked);
$('set-gears').onchange = (e) => (settings.announceGears = e.target.checked);

showMenu();
