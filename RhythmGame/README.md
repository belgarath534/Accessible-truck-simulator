# Beat by Ear

A rhythm game for blind and low-vision players, played by sound and touch.

Call and response: a soft bell, then a bar of cue sounds (listen), then you repeat the moves on the same beats
(your turn). Tap is a wooden knock, swipe left a low beep on the left, swipe right a high beep on the right,
swipe up a rising whistle. Haptics tell you perfect, good or miss. VoiceOver steps aside during songs (direct touch).

- `Packages/BeatCore`: songs, charts, judging and sound synthesis (tested on Linux).
- `App`: the SwiftUI app (audio engine, touch pad, menus, calibration).
- Builds: `.github/workflows/rhythm.yml`. TestFlight: Actions, Beat by Ear, Run workflow. It reuses the truck sim's
  secrets and fastlane match certificates.

Coming next: your own songs from the Files app (beat detection), more built-in songs, Game Center leaderboards.
