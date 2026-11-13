# Engine and truck recordings

Drop recordings here (m4a, wav, caf or mp3) and the game uses them instead of its synthesized engine:

- `engine_idle`, `engine_low`, `engine_mid`, `engine_high`: seamless loops at steady RPM
  (about 600, 1000, 1400 and 1850 RPM; see `SampledEngine.loops` to adjust)
- `engine_start`, `engine_stop`, `air_brake`, `horn`: one-shot sounds (each optional)

`engine_idle` is required; without it the synthesized engine is used.

## Truck engines

`engine_loop_<truck id>.wav`: one seamless loop per truck, recorded at idle and sped up with the revs
(see `SampledEngine.init(engine:loop:idleRPM:maxRPM:)`). Made with ElevenLabs sound effects.
Old Reliable uses the four `engine_idle`...`engine_high` loops; the Volt (electric) is synthesized.

## Weather

`weather_rain_light`, `weather_rain_storm`, `weather_wipers`, `weather_wet_tires` (seamless loops) and
`weather_thunder` (one shot), made with ElevenLabs sound effects. Without them, the rain is synthesized.

## Radio voices

`voice_<id>.m4a`: one file per line in `RadioLines.swift`, made with Piper (open-source text to speech) by
`scripts/make_voices.py`. Voices: Kristin (dispatcher, and lower and slower as Smooth Rider) and Joe (the DJ, and
deeper as Big Mike). Kristin's voice data is public domain (LibriVox) and Joe's is CC0. To regenerate after changing
a line: export the lines to JSON, download the two voice models from huggingface.co/rhasspy/piper-voices, and run
the script. Without a file, the game's own voice reads the line.
