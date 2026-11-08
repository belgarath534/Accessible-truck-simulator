// Speech: through the player's screen reader (NVDA, JAWS, Narrator) via live regions,
// or the built-in Windows voice. Priorities work like the iPhone version:
//   high   interrupts whatever is being said
//   normal is queued
//   low    is skipped if something is already being said (speed call-outs, gears)

export class Speech {
  constructor() {
    this.mode = 'auto'; // 'auto' | 'screenReader' | 'voice'
    this.rate = 1.1;
    this.onSpeakingChanged = null;
    this.lastSpoke = 0;
    this.flip = false;
    this.assertive = [document.getElementById('live-a1'), document.getElementById('live-a2')];
    this.polite = document.getElementById('live-p');
  }

  /** True when a screen reader is running (reported by Windows through Electron). */
  get screenReaderRunning() {
    return !!window.truckSim?.screenReaderActive?.();
  }

  get usesScreenReader() {
    return this.mode === 'screenReader' || (this.mode === 'auto' && this.screenReaderRunning);
  }

  speak(text, priority = 'normal') {
    if (!text) return;
    const now = performance.now();
    if (this.usesScreenReader) {
      if (priority === 'low' && now - this.lastSpoke < 1500) return;
      this.lastSpoke = now;
      if (priority === 'high') {
        // Alternate between two regions so the same sentence twice is still read.
        this.flip = !this.flip;
        const [on, off] = this.flip ? this.assertive : [this.assertive[1], this.assertive[0]];
        off.textContent = '';
        on.textContent = text;
      } else {
        this.polite.textContent = '';
        setTimeout(() => { this.polite.textContent = text; }, 30);
      }
      return;
    }
    const synth = window.speechSynthesis;
    if (!synth) return;
    if (priority === 'low' && synth.speaking) return;
    if (priority === 'high') synth.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.rate = this.rate;
    u.onstart = () => this.onSpeakingChanged?.(true);
    u.onend = () => this.onSpeakingChanged?.(synth.pending || synth.speaking);
    synth.speak(u);
    this.lastSpoke = now;
  }

  stop() {
    window.speechSynthesis?.cancel();
    for (const r of [...this.assertive, this.polite]) r.textContent = '';
  }
}
