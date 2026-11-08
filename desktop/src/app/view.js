// A simple top-down picture of the road for sighted players. Never needed to play.

export class DriveView {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
  }

  resize() {
    const dpr = window.devicePixelRatio || 1;
    const { clientWidth: w, clientHeight: h } = this.canvas;
    if (this.canvas.width !== Math.round(w * dpr) || this.canvas.height !== Math.round(h * dpr)) {
      this.canvas.width = Math.round(w * dpr);
      this.canvas.height = Math.round(h * dpr);
    }
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return [w, h];
  }

  draw(session, settings) {
    const [w, h] = this.resize();
    const ctx = this.ctx;
    const truck = session.truck;
    const road = session.road;
    const ppm = Math.min(w / 22, h / 26);
    const cx = w / 2;
    ctx.fillStyle = '#213821';
    ctx.fillRect(0, 0, w, h);
    const laneW = road.laneWidth * ppm;
    const roadLeft = cx - laneW * 1.5;
    const roadRight = cx + laneW * 0.5;
    ctx.fillStyle = '#404040';
    ctx.fillRect(roadLeft, 0, roadRight - roadLeft, h);
    ctx.fillStyle = '#666';
    ctx.fillRect(roadRight, 0, 0.4 * ppm, h);
    // Lane markings scroll with distance travelled.
    const dash = 4 * ppm;
    const gap = 8 * ppm;
    const offset = (truck.position % 12) * ppm;
    ctx.fillStyle = '#fff';
    for (let y = -dash - gap + offset; y < h; y += dash + gap) ctx.fillRect(cx - laneW / 2 - 2, y, 4, dash);
    ctx.fillRect(roadLeft, 0, 3, h);
    ctx.fillRect(roadRight - 3, 0, 3, h);
    const k = road.curvature(truck.position + 60);
    ctx.textBaseline = 'top';
    if (Math.abs(k) > 0.0005) {
      ctx.fillStyle = '#ff0';
      ctx.font = '600 22px system-ui, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(k > 0 ? 'Curve right ➡' : '⬅ Curve left', cx, 20);
    }
    for (const v of session.traffic) {
      const carY = h * 0.7 - (v.position - truck.position) * ppm;
      if (carY < -100 || carY > h + 100) continue;
      const len = (v.kind === 'truck' ? 14 : v.kind === 'pickup' ? 5.5 : 4.5) * ppm;
      const wid = (v.kind === 'truck' ? 2.5 : 1.9) * ppm;
      ctx.fillStyle = v.oncoming ? '#3b82f6' : '#f59e0b';
      ctx.fillRect(cx + v.lane * ppm - wid / 2, carY - len / 2, wid, len);
    }
    ctx.save();
    ctx.translate(cx + truck.lateralOffset * ppm, h * 0.7);
    ctx.rotate(truck.headingError);
    const tw = 2.5 * ppm;
    const tl = 7 * ppm;
    ctx.fillStyle = '#e33';
    ctx.fillRect(-tw / 2, -tl / 2, tw, tl * 0.3);
    ctx.fillStyle = '#d9d9d9';
    ctx.fillRect(-tw / 2, -tl / 2 + tl * 0.33, tw, tl * 0.67);
    ctx.restore();
    const metric = settings.units === 'metric';
    const speed = Math.round(truck.speed * (metric ? 3.6 : 2.23694));
    ctx.fillStyle = '#fff';
    ctx.textAlign = 'left';
    ctx.font = '600 34px system-ui, sans-serif';
    ctx.fillText(`${speed} ${metric ? 'km/h' : 'mph'}`, 20, 20);
    const status = [];
    if (truck.engine === 'off') status.push('Engine off');
    else if (truck.engine === 'starting') status.push('Starting…');
    else status.push(`Gear ${truck.gearIndex + 1}  ${Math.round(truck.rpm)} rpm`);
    if (truck.signal !== 'off') status.push(truck.signal === 'left' ? '◀ signal' : 'signal ▶');
    status.push(`Fuel ${Math.round((truck.fuelLiters / session.spec.fuelCapacityLiters) * 100)}%`);
    ctx.font = '600 17px system-ui, sans-serif';
    ctx.fillText(status.join('   '), 20, 64);
  }
}
