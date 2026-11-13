"""Generates the flight sim's recorded voice lines with Piper (free, open-source voices).
Usage: make_voices.py <flight_lines.json> <voices dir> <out dir>
The JSON comes from the DumpVoice test (DUMP_PATH=... swift test). Voice models: huggingface.co/rhasspy/piper-voices."""
import json, subprocess, sys, os
lines, voices, out = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
CAST = {"instructor": ("joe", 1.0), "cockpit": ("kristin", 0.95)}   # voice, speed (bigger = slower)
SAY = {"1000": "one thousand", "500": "five hundred", "200": "two hundred", "100": "one hundred"}
os.makedirs(out, exist_ok=True)
raw = os.path.join(out, "_raw.wav")
for line in lines:
    voice, speed = CAST[line["speaker"]]
    text = SAY.get(line["text"], line["text"])
    subprocess.run([sys.executable, "-m", "piper", "-m", f"{voices}/en_US-{voice}-medium.onnx", "-f", raw,
                    "--length-scale", str(speed), "--sentence-silence", "0.3"],
                   input=text.encode(), check=True, capture_output=True)
    # Trim silence at both ends, even loudness, mono 44.1 kHz AAC.
    trim = "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af", trim + ",loudnorm=I=-16:TP=-1.5,aresample=44100",
                    "-ac", "1", "-c:a", "aac", "-b:a", "64k", os.path.join(out, f"say_{line['id']}.m4a")], check=True)
os.remove(raw)
print(len(lines), "voice files")
