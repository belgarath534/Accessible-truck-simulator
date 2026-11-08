// Runs one drive: the game loop, input and feedback. A port of DrivingController.swift.

import { DrivingSession } from '../sim/session.js';
import { practiceLoop } from '../sim/road.js';
import { practiceGoal } from '../sim/trip.js';
import { starter } from '../sim/truck.js';
import { Phrases } from '../sim/phrases.js';
import { Tutorial } from '../sim/tutorial.js';
import { Feedback } from './feedback.js';

const FIXED_STEP = 1 / 60;

export class Drive {
  constructor({ mode, settings, audio, speech, input, view, onPause, onFinish }) {
    Object.assign(this, { mode, settings, audio, speech, input, view, onPause, onFinish });
    this.feedback = new Feedback(audio, speech, settings);
    this.paused = false;
    this.finished = false;
    this.raf = null;
    this.makeSession();
  }

  makeSession() {
    const road = practiceLoop();
    const goal = this.mode === 'tutorial' ? { name: 'Tutorial', distance: null } : practiceGoal(road);
    this.session = new DrivingSession({ spec: starter, road, goal, assist: this.settings.assist });
    this.tutorial = this.mode === 'tutorial' ? new Tutorial({ units: this.settings.units }) : null;
    // The tutorial says "Engine running" itself, with the next step.
    this.feedback.quietEngineStart = !!this.tutorial;
    this.recentActions = [];
    this.tutorialFinishedAt = null;
    this.lastTime = 0;
    this.accumulator = 0;
    this.finished = false;
  }

  get phrases() {
    return new Phrases(this.settings.units);
  }

  start() {
    this.audio.setVolume(this.settings.volume);
    this.audio.setLaneTone(this.settings.laneTone);
    this.audio.start(this.session.spec.sound);
    this.feedback.reset();
    this.input.onAction = (a) => this.perform(a);
    this.input.reset();
    this.input.enabled = true;
    if (!this.tutorial) this.speech.speak(this.feedback.intro(this.session), 'high');
    this.raf = requestAnimationFrame((t) => this.tick(t));
  }

  stop() {
    cancelAnimationFrame(this.raf);
    this.raf = null;
    this.input.enabled = false;
    this.input.onAction = null;
    this.audio.stop();
    this.speech.stop();
  }

  pause() {
    if (this.paused || this.finished) return;
    this.paused = true;
    this.input.enabled = false;
    this.input.reset();
    this.audio.setMuted(true);
    this.audio.flush();
    this.speech.stop();
    const s = this.session;
    this.onPause(this.phrases.tripStatus({ goal: s.goal, stats: s.stats, remaining: s.remaining, timeLeft: s.timeLeft }));
  }

  resume() {
    if (!this.paused) return;
    this.paused = false;
    this.lastTime = 0;
    this.accumulator = 0;
    this.audio.setMuted(false);
    this.input.reset();
    this.input.enabled = true;
  }

  restart() {
    this.makeSession();
    this.audio.start(this.session.spec.sound);
    this.feedback.reset();
    this.paused = false;
    this.input.reset();
    this.input.enabled = true;
    if (!this.tutorial) this.speech.speak(this.feedback.intro(this.session), 'high');
    if (!this.raf) this.raf = requestAnimationFrame((t) => this.tick(t));
  }

  perform(action) {
    if (action.type === 'pause') {
      if (!this.finished) this.pause();
      return;
    }
    if (action.type === 'help') {
      this.speech.speak('Up arrow accelerate, Down arrow brake, Left and Right arrows steer. N engine, I dashboard, G road ahead, left and right brackets turn signals, Backspace cancel signal, H horn, Escape pause.', 'high');
      return;
    }
    if (this.paused || this.finished) return;
    if (this.tutorial) this.recentActions.push(action);
    this.feedback.handle(this.session.perform(action));
  }

  tick(now) {
    this.raf = requestAnimationFrame((t) => this.tick(t));
    const input = this.input.poll();
    if (this.paused || this.finished) return;
    const nowS = now / 1000;
    const dt = this.lastTime === 0 ? FIXED_STEP : Math.min(nowS - this.lastTime, 0.1);
    this.lastTime = nowS;
    this.accumulator += dt;
    const events = [];
    while (this.accumulator >= FIXED_STEP) {
      events.push(...this.session.step(FIXED_STEP, input));
      this.accumulator -= FIXED_STEP;
    }
    this.feedback.handle(events);
    this.feedback.update(this.session);
    this.view.draw(this.session, this.settings);
    this.updateTutorial(dt, nowS);
    const summary = this.session.summary;
    if (summary && !this.finished) {
      this.finish('Delivered!', `${this.phrases.arrived(summary)} Practice drives don't pay. In the full game, jobs pay money.`);
    }
  }

  updateTutorial(dt, now) {
    const tutorial = this.tutorial;
    if (!tutorial) return;
    const line = tutorial.update(dt, this.session, this.recentActions);
    if (line) this.speech.speak(line, 'high');
    this.recentActions = [];
    if (!tutorial.isComplete) return;
    if (this.tutorialFinishedAt == null) {
      this.tutorialFinishedAt = now;
      this.settings.tutorialDone = true;
    }
    // Let the closing words play before the results screen.
    if (now - this.tutorialFinishedAt > 9) {
      this.finish('Tutorial Complete!', "You've learned the engine, pedals, steering, the dashboard, GPS, signals, curves, the horn and stopping. Try a Practice Drive next. The controls are always in How to Drive on the main menu.");
    }
  }

  finish(title, text) {
    this.finished = true;
    this.input.enabled = false;
    this.input.reset();
    this.audio.setMuted(true);
    this.audio.flush();
    this.onFinish({ title, text });
  }
}
