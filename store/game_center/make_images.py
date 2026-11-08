"""Draws the 512x512 Game Center achievement pictures from achievements.json."""
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
COLORS = {  # ring, inner
    "start": ((76, 175, 80), (27, 66, 31)),
    "skill": ((33, 150, 243), (13, 50, 90)),
    "career": ((255, 176, 32), (90, 58, 0)),
    "business": ((171, 71, 188), (60, 22, 70)),
}


def draw_truck(d, cx, cy, s, color):
    # Trailer, cab and wheels: a simple side view.
    d.rounded_rectangle([cx - 1.6 * s, cy - 0.7 * s, cx + 0.5 * s, cy + 0.45 * s], radius=s * 0.08, fill=color)
    d.rounded_rectangle([cx + 0.6 * s, cy - 0.45 * s, cx + 1.55 * s, cy + 0.45 * s], radius=s * 0.15, fill=color)
    d.rectangle([cx + 1.05 * s, cy - 0.32 * s, cx + 1.4 * s, cy - 0.02 * s], fill=(30, 30, 30))
    for wx in (-1.3, -0.9, 0.2, 1.2):
        d.ellipse([cx + (wx - 0.18) * s, cy + 0.35 * s, cx + (wx + 0.18) * s, cy + 0.71 * s], fill=(25, 25, 25),
                  outline=color, width=max(2, int(s * 0.05)))


def wrap(text, font, width, d):
    words, lines, line = text.split(), [], ""
    for w in words:
        test = (line + " " + w).strip()
        if d.textlength(test, font=font) <= width:
            line = test
        else:
            lines.append(line)
            line = w
    lines.append(line)
    return lines


def make(a):
    size = 512
    img = Image.new("RGB", (size, size), (18, 22, 28))
    d = ImageDraw.Draw(img)
    ring, inner = COLORS[a["group"]]
    c = size / 2
    # Medal with a star-burst edge.
    points = []
    for i in range(48):
        r = 236 if i % 2 == 0 else 220
        ang = math.pi * 2 * i / 48
        points.append((c + r * math.cos(ang), c + r * math.sin(ang)))
    d.polygon(points, fill=ring)
    d.ellipse([c - 200, c - 200, c + 200, c + 200], fill=inner)
    d.ellipse([c - 200, c - 200, c + 200, c + 200], outline=ring, width=6)
    draw_truck(d, c, c - 70, 70, ring)
    font = ImageFont.truetype(FONT, 40)
    lines = wrap(a["title"], font, 330, d)
    if len(lines) > 2:
        font = ImageFont.truetype(FONT, 32)
        lines = wrap(a["title"], font, 340, d)
    y = c + 40 - (len(lines) - 1) * 22
    for line in lines:
        d.text((c, y), line, font=font, fill=(255, 255, 255), anchor="mm")
        y += 46
    pts = ImageFont.truetype(FONT, 26)
    d.text((c, c + 150), f"{a['points']} points", font=pts, fill=ring, anchor="mm")
    img.save(HERE / "images" / f"{a['id']}.png")


for a in json.loads((HERE / "achievements.json").read_text()):
    make(a)
print("done")
