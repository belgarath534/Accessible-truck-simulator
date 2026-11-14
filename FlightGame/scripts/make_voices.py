"""Generates the flight sim's recorded voice lines with Piper (free, open-source voices).
Usage: make_voices.py <flight_lines.json> <voices dir> <out dir>
The JSON comes from the DumpVoice test (DUMP_PATH=... swift test). Voice models: huggingface.co/rhasspy/piper-voices."""
import json, subprocess, sys, os
lines, voices, out = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
CAST = {"instructor": ("joe", 1.0), "cockpit": ("joe", 0.95), "tower": ("joe", 0.92)}   # voice, speed (bigger = slower)
# The tower talks over the radio: a narrow, slightly crunchy sound.
RADIO = "highpass=f=450,lowpass=f=2800,acompressor=threshold=-22dB:ratio=6,"
SAY = {"1000": "one thousand", "500": "five hundred", "200": "two hundred", "100": "one hundred"}
os.makedirs(out, exist_ok=True)
raw = os.path.join(out, "_raw.wav")
for line in lines:
    target = os.path.join(out, f"say_{line['id']}.m4a")
    if os.path.exists(target) and "--all" not in sys.argv:
        continue   # only new lines, unless --all
    voice, speed = CAST[line["speaker"]]
    text = SAY.get(line["text"], line["text"])
    subprocess.run([sys.executable, "-m", "piper", "-m", f"{voices}/en_US-{voice}-medium.onnx", "-f", raw,
                    "--length-scale", str(speed), "--sentence-silence", "0.3"],
                   input=text.encode(), check=True, capture_output=True)
    # Trim silence at both ends, even loudness, mono 44.1 kHz AAC.
    trim = "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse"
    radio = RADIO if line["speaker"] == "tower" else ""
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-af", trim + "," + radio + "loudnorm=I=-16:TP=-1.5,aresample=44100",
                    "-ac", "1", "-c:a", "aac", "-b:a", "64k", target], check=True)
if os.path.exists(raw):
    os.remove(raw)
print(len(lines), "voice files")
