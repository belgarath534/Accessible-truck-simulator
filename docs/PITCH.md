# Project Pitch: Accessible Truck Simulator

An accessible truck-driving game for iOS, written in Swift, that blind and sighted players
can both enjoy. Players **actually drive** their trucks — this is not a menu game.

## Pillars

1. **Driving is the main attraction.** Everything else makes driving more rewarding.
2. **Accessibility from day one.** A player never needs visual information to drive.
3. **Approachable.** Owning trucks, not being a mechanic; light business, not a spreadsheet.

## Scope summary

- **Driving:** start the truck, accelerate, brake, steer, follow roads and GPS, traffic,
  distinct truck sounds and handling. Audio, spatial sound, and haptics carry immersion.
- **Controls (ideas):** hold to accelerate, two-finger tap for turn signals, three-finger
  tap for GPS, a control for air conditioning, optional motion steering with button
  alternatives. Must be validated against VoiceOver.
- **Accessibility:** distinctive engine sounds, spatial traffic audio, spoken GPS, hazard
  warnings, haptics, accessible menus, spoken dashboard (speed, fuel, temperature, signals).
- **Trucks & progression:** start with a basic truck; trucks differ in power, handling, fuel
  capacity, braking, feel. Simple leveled upgrades (engine, tires, brakes, fuel tank,
  transmission, GPS). Cosmetics later (paint, exterior, interior, horns).
- **Contracts:** standard, long-distance, time-sensitive, high-value. Earn money and XP.
  Deadlines affect satisfaction/reputation, fairly.
- **Company (optional):** more trucks, hired drivers, garage expansion, better contracts.
  Personal driving pays better than employee deliveries.
- **Progression:** company level, driver XP, and reputation are separate systems; no resets.
- **Offline progress:** hired drivers keep working via saved timestamps; no server required
  initially.

## First step

A small playable prototype: one truck, basic driving, acceleration, braking, steering, and
audio feedback. Prove the driving is enjoyable and accessible before building anything else.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the technical proposal.
