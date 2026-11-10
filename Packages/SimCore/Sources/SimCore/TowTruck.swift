import Foundation

public extension TruckSpec {
    /// A tow truck: drive to stranded cars and bring them to the mechanic. Only it can take tow calls.
    static let towTruck: TruckSpec = {
        var t = TruckSpec.cityHauler
        t.name = "Tow Truck"
        t.id = "tow_truck"
        t.price = 12_000
        t.summary = "A heavy-duty tow truck with a winch and a flatbed. It takes tow calls instead of freight: drive to stranded drivers, hook up their car, and bring it to the mechanic. Quick and nimble, with a growly V8."
        t.massKg = 11_000
        t.speedLimiter = 105 / 3.6
        t.sound.loopFile = "engine_loop_city_hauler"
        return t
    }()

    var isTowTruck: Bool { id == TruckSpec.towTruck.id }
}

/// A tow call: a stranded car somewhere along the route, to be towed to the destination.
public struct TowCall: Codable, Equatable, Hashable, Sendable {
    /// Metres along the route from the start where the car is waiting.
    public var pickupAt: Double
    /// "a blue pickup", "a minivan"...
    public var car: String
    /// "a flat tire", "an empty tank"...
    public var trouble: String
    /// Where it goes: "the mechanic in Bayview".
    public var place: String
}

public extension Cargo {
    /// What a tow truck carries once the car is hooked up.
    static let towedCar = Cargo(name: "Towed car", massKg: 1_600, ratePerKm: 230, fragile: true)
}

public extension JobBoard {
    /// Tow calls from `origin`: a stranded car out on the road, to be brought to a town.
    static func makeTowJob<R: RandomNumberGenerator>(using rng: inout R, map: WorldMap = .standard,
                                                     from origin: String) -> DeliveryJob {
        let destination = map.towns.filter { $0.id != origin }.randomElement(using: &rng)!
        let distance = map.route(from: origin, to: destination.id).map(map.length(of:)) ?? 10_000
        let cars = ["a blue pickup", "a red minivan", "a little white hatchback", "an old station wagon",
                    "a sports car", "a farm truck", "a camper van"]
        let troubles = ["a flat tire", "an empty tank", "a dead battery", "a broken fan belt", "an overheated engine",
                        "a slide into the ditch"]
        var job = DeliveryJob(cargo: .towedCar, distance: distance,
                              pay: Int((distance / 1_000 * Cargo.towedCar.ratePerKm / 10).rounded()) * 10,
                              timeLimit: ((distance / fairSpeed * 1.5 + 180) / 60).rounded(.up) * 60,
                              origin: origin, destination: destination.id)
        let place = Bool.random(using: &rng) ? "the mechanic in \(destination.name)" : "the owner's home in \(destination.name)"
        job.tow = TowCall(pickupAt: (distance * Double.random(in: 0.3...0.6, using: &rng)).rounded(),
                          car: cars.randomElement(using: &rng)!, trouble: troubles.randomElement(using: &rng)!, place: place)
        return job
    }
}

public extension DrivingSession {
    /// Stop within this many metres of the stranded car to hook it up.
    static let towReach = 40.0
    /// Seconds to hook a car up.
    static let towHookSeconds = 4.0
}

extension DrivingSession {
    /// Hooking up the stranded car right now.
    public var towHooking: Bool { towHookTimer > 0 && !towHooked }

    /// Metres from the truck to the stranded car (negative: past it), before it's hooked up.
    public var towCarDistance: Double? {
        guard let pickup = towPickupAt, !towHooked, !towFailed, let remaining, let total = goal.distance else { return nil }
        return pickup - (total - remaining)
    }

    func checkTowCall(dt: Double, events: inout [SimEvent]) {
        guard let d = towCarDistance else { return }
        if d < 800 && d > 0 && !towAnnounced && truck.speed > 2 {
            towAnnounced = true
            events.append(.towCarAhead(distance: d))
        }
        if truck.speed < 0.3 && abs(d) <= DrivingSession.towReach {
            if towHookTimer == 0 { events.append(.towHookingUp) }
            towHookTimer += dt
            if towHookTimer >= DrivingSession.towHookSeconds {
                towHooked = true
                stats.towCompleted = true
                cargoMassKg += Cargo.towedCar.massKg
                events.append(.towHooked)
            }
        } else {
            towHookTimer = 0
        }
        if d < -DrivingSession.towReach * 2 && truck.speed > 3 {
            towFailed = true
            events.append(.towMissedCar)
        }
    }
}

public extension Payout {
    /// A tow call that never picked up its car pays nothing.
    static func towCanceled(_ stats: TripStats) -> Payout {
        Payout(lines: [Line(label: "Tow call canceled: you missed the car", amount: 0)] + expenses(stats))
    }
}
