# Accessible Flight Simulator

Fly a small plane by sound. Built for VoiceOver.

- `Packages/FlightCore`: the flight model, airports, navigation and landing guidance, lessons, logbook and gestures
  (tested on Linux, including a robot pilot that flies every lesson).
- `App`: the SwiftUI app (tilt yoke, live sound engine, speech, menus).
- Builds: `.github/workflows/flight.yml`. TestFlight: Actions, Flight Sim, Run workflow. Reuses the truck sim's
  secrets and fastlane match certificates.
