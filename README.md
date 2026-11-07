# Accessible Truck Simulator

An accessible iOS truck-driving game in Swift, playable by blind and sighted players.

- [Pitch](docs/PITCH.md)
- [Architecture & feasibility proposal](docs/ARCHITECTURE.md)

## Status: driving prototype (milestones M0–M2)

One truck on a 12 km practice loop with curves. Engine start, automatic gearbox, accelerate, brake,
steer (tilt or one-finger joystick, plus keyboard and game controller), synthesized engine/road/rumble-strip
audio, lane guidance beeps, spoken curve warnings and dashboard, and vibration. See **How to Drive** in the app.

## Layout

- `Packages/SimCore` – the simulation (physics, road, gestures, spoken phrases). Pure Swift, unit-tested,
  runs on Linux too: `cd Packages/SimCore && swift test`.
- `App/` – the iOS app: SwiftUI menus, driving screen, audio synthesis, speech, haptics, input.
- `project.yml` – XcodeGen spec. The Xcode project is generated, not committed.

## Building without a Mac

GitHub Actions (`.github/workflows/build.yml`) runs the tests on Linux and builds the app on a macOS runner.
Every push uploads an unsigned `TruckSim-unsigned.ipa` artifact (a quick compile check).

## TestFlight

Signed builds go through Codemagic (`codemagic.yaml`), set up the same way as Dungeon Descent: the
"Accessible Backrooms" App Store Connect key and distribution certificate. See [docs/CODEMAGIC.md](docs/CODEMAGIC.md).
