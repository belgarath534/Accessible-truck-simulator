"""Generates the truck sim's radio voice files with Piper (free, open-source voices).
Usage: make_voices.py <radio_lines.json> <voices dir> <out dir>"""
import json, subprocess, sys, os
lines, voices, out = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
# speaker -> (voice, speed (bigger = slower), pitch factor)
CAST = {
    "dispatcher": ("kristin", 1.0, 1.0),
    "dj": ("joe", 0.95, 1.0),
    "bigMike": ("joe", 1.05, 0.86),
    "smoothRider": ("kristin", 1.1, 0.9),
}
os.makedirs(out, exist_ok=True)
for line in lines:
    voice, speed, pitch = CAST[line["speaker"]]
    raw = os.path.join(out, "_raw.wav")
    subprocess.run([sys.executable, "-m", "piper", "-m", f"{voices}/en_US-{voice}-medium.onnx", "-f", raw,
                    "--length-scale", str(speed), "--sentence-silence", "0.25"],
                   input=line["text"].encode(), check=True, capture_output=True)
    # Pitch without changing speed, a little silence trimmed, even loudness, mono 44.1 kHz.
    f = []
    if pitch != 1.0:
        f += [f"asetrate=22050*{pitch}", "aresample=22050", f"atempo={1/pitch:.4f}"]
    f += ["loudnorm=I=-18:TP=-2", "aresample=44100"]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af", ",".join(f), "-ac", "1", "-c:a", "pcm_s16le",
                    os.path.join(out, f"voice_{line['id']}.wav")], check=True)
os.remove(os.path.join(out, "_raw.wav"))
print(len(lines), "voice files")
