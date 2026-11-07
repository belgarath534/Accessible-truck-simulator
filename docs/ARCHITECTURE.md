# Architecture & Feasibility Proposal (Draft)

Status: **proposal for discussion** — nothing here is final. See `PITCH.md` for the vision.

Guiding rule: *driving is the main attraction; a blind player must be able to drive with zero visual information.*

---

## 1. Verdict on feasibility

Feasible in native Swift, using only Apple frameworks — **if** we pick a world model that
is accessible by design (see §3). The risky parts are not physics or economy; they are:

1. Gestures while VoiceOver is running.
2. Making lane-keeping and turning understandable through audio alone.
3. Making the engine sound convincing (this is most of the "feel").

The prototype exists to retire those three risks.

---

## 2. Tech stack (all first-party, no game engine)

| Concern | Framework | Notes |
|---|---|---|
| Menus, garage, contracts | SwiftUI | VoiceOver-friendly by default |
| Driving screen | UIKit view hosted in SwiftUI | Needs low-level touch handling |
| Simulation loop | `CADisplayLink`, fixed 60 Hz step | Pure Swift, no UI dependencies |
| Engine/traffic/3D audio | `AVAudioEngine` + `AVAudioEnvironmentNode` (HRTF) | Apple's PHASE is an option later |
| Speech | `AVSpeechSynthesizer` (+ `prefersAssistiveTechnologySettings`) | Uses the player's VoiceOver voice/rate |
| Haptics | Core Haptics | Engine rumble, rumble strips, collisions |
| Motion steering | Core Motion (`CMMotionManager.deviceMotion`) | Optional, never required |
| Controllers / keyboards | GameController framework | Xbox/PS/MFi + Bluetooth keyboards — very popular with blind gamers |
| Visuals for sighted players | SpriteKit (top-down) to start | 3D (SceneKit/RealityKit) can come much later |
| Saves | `Codable` → JSON file (or SwiftData later) | |

Minimum target suggestion: **iOS 17**.

---

## 3. The key decision: a road-relative world

A free-roaming 2D/3D world is hard to build *and* hard to drive without sight. Instead:

- The map is a **graph**: intersections (nodes) connected by road segments (edges).
- Each segment has length, curvature profile, lanes, speed limit, and hazards.
- The truck's position is `(segment, distanceAlongSegment, lateralOffset)`.

This is still real driving — you control throttle, brake, and steering, and you can leave
your lane or crash — but every important quantity is one number we can **sonify**:

- **Lane position** → stereo-panned tyre/rumble-strip sound + haptic tick as you drift; warning
  tone when near the edge.
- **Upcoming curve** → spoken ("sharp left in 200 metres") plus a subtle directional cue.
- **Curve force** → curves push `lateralOffset` proportional to speed² × curvature; you must
  counter-steer. Too fast = you run wide. This is where truck handling stats matter.
- **Intersections** → GPS announces the turn; you signal and steer; when you reach the node,
  steering direction picks the exit branch.
- **Traffic** → other vehicles live on the same graph, follow simple car-following rules,
  and are rendered as 3D-positioned sounds relative to the player.

Sighted players get a top-down view drawn from the same data.

---

## 4. Truck physics (simple, arcade-leaning, tunable)

Longitudinal (per tick):

```
engineForce   = torqueCurve(rpm) * throttle * gearRatio * finalDrive / wheelRadius
resistance    = rolling(mass) + aero(speed²) + grade(mass, slope)
brakeForce    = brakeInput * brakeStrength + engineBraking(rpm)
acceleration  = (engineForce - resistance - brakeForce) / (truckMass + cargoMass)
```

- Automatic transmission first (manual is a later option/upgrade).
- Fuel burns proportional to engine load.
- Every truck is a `TruckSpec` data struct (power, torque curve, mass, brake strength,
  handling, fuel capacity, sound set). Upgrades are multipliers on these fields — players
  just see "Engine Level 3", never a gear ratio.

---

## 5. Input & VoiceOver strategy

VoiceOver normally swallows custom gestures. The standard fix used by iOS audio games:

- The driving view sets `accessibilityTraits = .allowsDirectInteraction`, so touches go
  straight to the game while VoiceOver stays on.
- The game speaks for itself during driving (`AVSpeechSynthesizer`, optionally routed via
  VoiceOver announcements — this should be a setting).
- Use VoiceOver's own hooks where they fit:
  - **Magic Tap** (two-finger double-tap) → e.g. speak dashboard / pause.
  - **Escape** (two-finger Z scrub) → pause menu.
- Menus stay normal SwiftUI with full VoiceOver support.

All inputs go through one abstraction so control schemes are swappable:

```swift
struct DrivingInput { var throttle: Double; var brake: Double; var steer: Double
                      var actions: Set<DrivingAction> } // signalLeft, horn, gps, dashboard…
protocol InputSource { func poll() -> DrivingInput }
// TouchInputSource, TiltInputSource, ControllerInputSource, KeyboardInputSource
```

**Must be tested on a real device with VoiceOver on** before locking the control scheme:
multi-finger taps inside a direct-interaction area, and conflicts with system gestures
(e.g. three-finger triple-tap = Screen Curtain). Proposed touch layout for testing:
left/right screen halves = steer, hold with second finger = throttle, swipe down = brake.

---

## 6. Module layout

```
TruckSim (Xcode app)
├── App/            SwiftUI app, navigation, settings
├── DrivingScreen/  UIKit view, touch → InputSource, SpriteKit overlay
└── Packages/
    ├── SimCore     (pure Swift, no Apple UI imports — unit-testable anywhere)
    │   ├── Physics/      TruckSpec, TruckState, step(dt:)
    │   ├── World/        RoadGraph, Segment, Route, GPS planner
    │   ├── Traffic/      AI vehicles
    │   └── Events/       stream of SimEvent (curveAhead, laneDrift, crash, arrived…)
    ├── Feedback    AudioEngine, Announcer (speech queue w/ priorities), Haptics
    ├── Input       InputSource implementations
    └── Career      Money, XP, contracts, garage, company, offline progress, saves
```

The simulation emits **events**; audio, speech, haptics, and visuals all *subscribe*. This
keeps accessibility output a first-class consumer instead of an afterthought, and lets us
unit-test "does a hazard produce a warning?" without a device.

Speech needs a **priority queue** (crash warning interrupts "speed 60"; GPS doesn't get
talked over by the dashboard).

---

## 7. Offline / AFK progression

No server needed. On save store `lastActiveDate`; on launch compute
`elapsed = min(now - lastActiveDate, cap)` and resolve each employee's assigned job with a
deterministic formula (job duration from distance and driver skill). Show a spoken/VoiceOver
summary: "While you were away, Sam completed 2 deliveries and earned $1,840." Clock
tampering only hurts a single-player game, so it's acceptable early on.

---

## 8. Prototype plan (driving only)

| Milestone | Goal | "Done" means |
|---|---|---|
| M0 | Project skeleton | Xcode app + `SimCore` package + unit tests run |
| M1 | Straight road, one truck | Accelerate/brake, RPM-driven engine sound, spoken speed |
| M2 | Steering & lanes | Curvy road, lane-position audio + haptics, run-off/crash |
| M3 | Input schemes | Touch, tilt, controller; tested with VoiceOver on a device |
| M4 | Route & GPS | Small road graph, turn-by-turn speech, arrive at a destination |
| M5 | Traffic | A few AI vehicles with spatial audio, overtaking, collisions |
| M6 | First "delivery" | Pick up → drive → drop off → paid. Playtest with blind players |

Career, upgrades, and company management start only after M6 feels good.

---

## 9. Open questions

1. Do you have a Mac with Xcode and an iPhone for device testing? (VoiceOver and haptics
   can't be meaningfully tested in the Simulator.)
2. Minimum iOS version — OK with iOS 17?
3. Sighted visuals: simple top-down 2D first, or is 3D important early?
4. Do you have blind / VoiceOver-using playtesters? (Strongly recommended from M2.)
5. Engine sounds: record/license real truck audio, or synthesize? (Biggest impact on "feel".)
6. Units: metric, imperial, or a setting?
