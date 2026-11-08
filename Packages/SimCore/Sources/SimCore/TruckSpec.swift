import Foundation

/// Static description of a truck model. Upgrades will later act as multipliers on these values,
/// so players see "Engine level 3" and never have to think about gear ratios.
public struct TruckSpec: Equatable, Sendable {
    public struct TorquePoint: Equatable, Sendable {
        public var rpm: Double
        public var torque: Double // Newton-metres
        public init(rpm: Double, torque: Double) { self.rpm = rpm; self.torque = torque }
    }

    public var name: String

    // Shop
    /// Stable identifier used in save files.
    public var id = "old_reliable"
    /// Price in the garage (0 = the starter truck).
    public var price = 0
    /// One or two sentences for the garage.
    public var summary = ""
    public var sound = EngineSound.recorded
    /// Electric trucks: one gear, a motor instead of an engine, a battery charged at truck stops.
    public var isElectric = false
    /// Fuel (or battery) used compared with a typical truck: below 1 goes further on a tank.
    public var fuelEfficiency = 1.0

    // Mass
    public var massKg: Double

    // Engine
    public var torqueCurve: [TorquePoint]
    public var idleRPM: Double
    public var maxRPM: Double
    public var cylinders: Int
    public var engineStartSeconds: Double

    // Transmission (automatic)
    public var gearRatios: [Double]
    public var finalDrive: Double
    public var drivetrainEfficiency: Double
    public var shiftUpRPM: Double
    public var shiftDownRPM: Double
    public var shiftSeconds: Double
    public var wheelRadius: Double

    // Brakes
    /// Maximum deceleration from the service brakes, m/s².
    public var maxBrakeDecel: Double
    /// Fraction of peak torque available as engine braking when off the throttle.
    public var engineBrakeFraction: Double

    // Resistance
    public var dragArea: Double          // Cd * frontal area, m²
    public var rollingResistance: Double // coefficient
    /// Fraction of weight on the driven axle times tyre grip: caps how hard it can accelerate.
    public var tractionLimitAccel: Double

    // Handling
    public var wheelbase: Double
    /// The lateral acceleration (m/s²) produced at full steering lock at speed.
    /// Higher = more responsive steering, and faster possible cornering.
    public var steeringLatAccel: Double
    /// Maximum road-wheel angle at walking pace, radians.
    public var maxSteerAngle: Double
    /// How fast the wheels turn toward the requested angle, radians per second.
    public var steerRate: Double

    // Fuel
    public var fuelCapacityLiters: Double

    /// Speed governor, m/s. Real trucks are usually limited to ~90 km/h.
    public var speedLimiter: Double

    public init(name: String, massKg: Double, torqueCurve: [TorquePoint], idleRPM: Double, maxRPM: Double,
                cylinders: Int, engineStartSeconds: Double, gearRatios: [Double], finalDrive: Double,
                drivetrainEfficiency: Double, shiftUpRPM: Double, shiftDownRPM: Double, shiftSeconds: Double,
                wheelRadius: Double, maxBrakeDecel: Double, engineBrakeFraction: Double, dragArea: Double,
                rollingResistance: Double, tractionLimitAccel: Double, wheelbase: Double,
                steeringLatAccel: Double, maxSteerAngle: Double, steerRate: Double,
                fuelCapacityLiters: Double, speedLimiter: Double) {
        self.name = name; self.massKg = massKg; self.torqueCurve = torqueCurve; self.idleRPM = idleRPM
        self.maxRPM = maxRPM; self.cylinders = cylinders; self.engineStartSeconds = engineStartSeconds
        self.gearRatios = gearRatios; self.finalDrive = finalDrive; self.drivetrainEfficiency = drivetrainEfficiency
        self.shiftUpRPM = shiftUpRPM; self.shiftDownRPM = shiftDownRPM; self.shiftSeconds = shiftSeconds
        self.wheelRadius = wheelRadius; self.maxBrakeDecel = maxBrakeDecel; self.engineBrakeFraction = engineBrakeFraction
        self.dragArea = dragArea; self.rollingResistance = rollingResistance; self.tractionLimitAccel = tractionLimitAccel
        self.wheelbase = wheelbase; self.steeringLatAccel = steeringLatAccel; self.maxSteerAngle = maxSteerAngle
        self.steerRate = steerRate; self.fuelCapacityLiters = fuelCapacityLiters; self.speedLimiter = speedLimiter
    }

    /// Engine torque at a given RPM (linear interpolation over the curve, zero outside it).
    public func torque(atRPM rpm: Double) -> Double {
        guard let first = torqueCurve.first, let last = torqueCurve.last else { return 0 }
        if rpm <= first.rpm { return first.torque }
        if rpm >= last.rpm { return rpm > maxRPM ? 0 : last.torque }
        for i in 1..<torqueCurve.count where rpm <= torqueCurve[i].rpm {
            let a = torqueCurve[i - 1], b = torqueCurve[i]
            let t = (rpm - a.rpm) / (b.rpm - a.rpm)
            return a.torque + (b.torque - a.torque) * t
        }
        return last.torque
    }

    public var peakTorque: Double { torqueCurve.map(\.torque).max() ?? 0 }
}

public extension TruckSpec {
    /// The player's first truck: an old, modest six-cylinder tractor pulling an empty trailer.
    static let starter = TruckSpec(
        name: "Old Reliable",
        massKg: 16_000,
        torqueCurve: [
            .init(rpm: 600, torque: 1_000),
            .init(rpm: 1_000, torque: 1_700),
            .init(rpm: 1_400, torque: 1_800),
            .init(rpm: 1_800, torque: 1_500),
            .init(rpm: 2_100, torque: 1_100),
        ],
        idleRPM: 600,
        maxRPM: 2_100,
        cylinders: 6,
        engineStartSeconds: 1.8,
        gearRatios: [12.0, 9.0, 6.8, 5.1, 3.9, 2.9, 2.2, 1.7, 1.3, 1.0],
        finalDrive: 3.4,
        drivetrainEfficiency: 0.9,
        shiftUpRPM: 1_700,
        shiftDownRPM: 1_000,
        shiftSeconds: 0.5,
        wheelRadius: 0.5,
        maxBrakeDecel: 4.0,
        engineBrakeFraction: 0.12,
        dragArea: 6.0,
        rollingResistance: 0.006,
        tractionLimitAccel: 2.4,
        wheelbase: 4.0,
        steeringLatAccel: 3.0,
        maxSteerAngle: 0.6,
        steerRate: 0.6,
        fuelCapacityLiters: 400,
        speedLimiter: 90 / 3.6
    )
}

/// How a truck's engine sounds. Each truck has its own voice; the synthesizer shapes it from these settings.
public struct EngineSound: Equatable, Sendable {
    /// Use the recorded engine loops when they're in the app (falls back to the synthesizer).
    public var recorded: Bool
    /// Below 1 sounds bigger and deeper, above 1 smaller and buzzier.
    public var pitch: Double
    /// 0 smooth ... 1 rough, clattery old diesel (combustion noise and uneven firing).
    public var roughness: Double
    /// 0 no turbo ... 1 loud turbo whistle.
    public var turbo: Double
    /// 0 clean ... 1 barking exhaust (harder, more saturated tone).
    public var bark: Double
    /// 0 steady idle ... 1 lumpy, rocking idle.
    public var lope: Double
    /// An electric motor's whine instead of an engine.
    public var electric: Bool

    public init(recorded: Bool = false, pitch: Double = 1, roughness: Double = 0.3, turbo: Double = 0.3,
                bark: Double = 0.2, lope: Double = 0.1, electric: Bool = false) {
        self.recorded = recorded
        self.electric = electric
        self.pitch = pitch
        self.roughness = roughness
        self.turbo = turbo
        self.bark = bark
        self.lope = lope
    }

    public static let recorded = EngineSound(recorded: true)
}

public extension TruckSpec {
    /// An older truck: less power and top speed, but planted in curves. Rough, clattery, no turbo.
    static let workhorse: TruckSpec = {
        var t = TruckSpec.starter
        t.name = "Workhorse"
        t.id = "workhorse"
        t.price = 6_000
        t.summary = "An old, tough truck. A bit less power, but it grips the road better in curves. Rough, clattery diesel with a lumpy idle and no turbo."
        t.torqueCurve = [
            .init(rpm: 600, torque: 1_100), .init(rpm: 1_000, torque: 1_600), .init(rpm: 1_300, torque: 1_650),
            .init(rpm: 1_800, torque: 1_300), .init(rpm: 2_100, torque: 900),
        ]
        t.steeringLatAccel = 3.5
        t.maxBrakeDecel = 4.2
        t.fuelCapacityLiters = 350
        t.speedLimiter = 85 / 3.6
        t.cylinders = 6
        t.sound = EngineSound(pitch: 1.1, roughness: 0.9, turbo: 0, bark: 0.45, lope: 0.7)
        return t
    }()

    /// The big rig: lots of power, strong brakes, a big tank. Deep V8 rumble with a loud turbo.
    static let roadKing: TruckSpec = {
        var t = TruckSpec.starter
        t.name = "Road King"
        t.id = "road_king"
        t.price = 18_000
        t.summary = "The big rig. Much more power, stronger brakes and a bigger fuel tank, even with heavy loads. Deep V8 rumble with a loud turbo whistle."
        t.massKg = 17_500
        t.torqueCurve = [
            .init(rpm: 600, torque: 1_500), .init(rpm: 1_000, torque: 2_500), .init(rpm: 1_400, torque: 2_700),
            .init(rpm: 1_800, torque: 2_300), .init(rpm: 2_100, torque: 1_700),
        ]
        t.cylinders = 8
        t.tractionLimitAccel = 2.8
        t.maxBrakeDecel = 5.0
        t.steeringLatAccel = 3.2
        t.fuelCapacityLiters = 600
        t.speedLimiter = 100 / 3.6
        t.sound = EngineSound(pitch: 0.82, roughness: 0.35, turbo: 1, bark: 0.6, lope: 0.35)
        return t
    }()

    /// A light farm truck: easy to handle and cheap to run, but slow.
    static let farmRunner: TruckSpec = {
        var t = TruckSpec.starter
        t.name = "Farm Runner"
        t.id = "farm_runner"
        t.price = 3_500
        t.summary = "A light farm truck. Easy to handle and cheap to run, but slow to get going. Rattly little four-cylinder."
        t.massKg = 14_500
        t.torqueCurve = [
            .init(rpm: 600, torque: 900), .init(rpm: 1_000, torque: 1_450), .init(rpm: 1_400, torque: 1_550),
            .init(rpm: 1_800, torque: 1_300), .init(rpm: 2_100, torque: 950),
        ]
        t.cylinders = 4
        t.steeringLatAccel = 3.4
        t.maxBrakeDecel = 4.2
        t.fuelCapacityLiters = 300
        t.fuelEfficiency = 0.85
        t.speedLimiter = 85 / 3.6
        t.sound = EngineSound(pitch: 1.35, roughness: 0.6, turbo: 0.1, bark: 0.3, lope: 0.3)
        return t
    }()

    /// Small and nimble: the sharpest steering, but a small tank.
    static let cityHauler: TruckSpec = {
        var t = TruckSpec.starter
        t.name = "City Hauler"
        t.id = "city_hauler"
        t.price = 10_000
        t.summary = "Small and nimble, with the sharpest steering of any truck: great in towns and tight curves. The small tank means more truck stops. High-revving four with a turbo."
        t.massKg = 15_000
        t.torqueCurve = [
            .init(rpm: 600, torque: 1_100), .init(rpm: 1_000, torque: 1_800), .init(rpm: 1_500, torque: 1_950),
            .init(rpm: 1_900, torque: 1_700), .init(rpm: 2_300, torque: 1_250),
        ]
        t.maxRPM = 2_300
        t.shiftUpRPM = 1_900
        t.cylinders = 4
        t.wheelbase = 3.6
        t.steeringLatAccel = 3.9
        t.maxSteerAngle = 0.7
        t.steerRate = 0.8
        t.maxBrakeDecel = 4.6
        t.fuelCapacityLiters = 280
        t.speedLimiter = 90 / 3.6
        t.sound = EngineSound(pitch: 1.25, roughness: 0.25, turbo: 0.6, bark: 0.2, lope: 0.05)
        return t
    }()

    /// Made for the mountains: the strongest brakes and engine brake, planted in curves, slow on the highway.
    static let mountainGoat: TruckSpec = {
        var t = TruckSpec.starter
        t.name = "Mountain Goat"
        t.id = "mountain_goat"
        t.price = 14_000
        t.summary = "Made for the mountains. The strongest brakes and engine brake, and it hugs the road in curves, but its top speed is low. Growly six with a barking exhaust brake."
        t.massKg = 16_500
        t.torqueCurve = [
            .init(rpm: 600, torque: 1_400), .init(rpm: 1_000, torque: 2_100), .init(rpm: 1_400, torque: 2_100),
            .init(rpm: 1_800, torque: 1_600), .init(rpm: 2_100, torque: 1_200),
        ]
        t.engineBrakeFraction = 0.3
        t.maxBrakeDecel = 5.8
        t.steeringLatAccel = 3.6
        t.fuelCapacityLiters = 450
        t.speedLimiter = 85 / 3.6
        t.sound = EngineSound(pitch: 0.95, roughness: 0.55, turbo: 0.4, bark: 0.8, lope: 0.4)
        return t
    }()

    /// The quickest truck at highway speeds.
    static let highwayStar: TruckSpec = {
        var t = TruckSpec.starter
        t.name = "Highway Star"
        t.id = "highway_star"
        t.price = 24_000
        t.summary = "Built for the interstate: the quickest truck at highway speeds, smooth and a little thrifty. Smooth six with a loud turbo whistle."
        t.massKg = 16_800
        t.torqueCurve = [
            .init(rpm: 600, torque: 1_300), .init(rpm: 1_000, torque: 2_200), .init(rpm: 1_400, torque: 2_600),
            .init(rpm: 1_800, torque: 2_550), .init(rpm: 2_100, torque: 2_100),
        ]
        t.tractionLimitAccel = 2.7
        t.maxBrakeDecel = 4.8
        t.steeringLatAccel = 3.1
        t.fuelCapacityLiters = 550
        t.fuelEfficiency = 0.95
        t.speedLimiter = 100 / 3.6
        t.sound = EngineSound(pitch: 0.9, roughness: 0.15, turbo: 0.9, bark: 0.3, lope: 0.05)
        return t
    }()

    /// The road-trip truck: a huge tank and great fuel economy, but heavy in the curves.
    static let longHauler: TruckSpec = {
        var t = TruckSpec.starter
        t.name = "Long Hauler"
        t.id = "long_hauler"
        t.price = 28_000
        t.summary = "The road-trip truck. A huge 900 liter tank and the best fuel economy of any diesel: it can cross the map without stopping. Heavy in the curves. Deep, calm, low rumble."
        t.massKg = 18_000
        t.torqueCurve = [
            .init(rpm: 600, torque: 1_400), .init(rpm: 1_000, torque: 2_300), .init(rpm: 1_400, torque: 2_400),
            .init(rpm: 1_800, torque: 2_000), .init(rpm: 2_100, torque: 1_500),
        ]
        t.maxBrakeDecel = 4.6
        t.steeringLatAccel = 2.9
        t.fuelCapacityLiters = 900
        t.fuelEfficiency = 0.75
        t.speedLimiter = 95 / 3.6
        t.sound = EngineSound(pitch: 0.78, roughness: 0.2, turbo: 0.35, bark: 0.25, lope: 0.15)
        return t
    }()

    /// A torque monster for the heaviest loads, but thirsty.
    static let ironBull: TruckSpec = {
        var t = TruckSpec.starter
        t.name = "Iron Bull"
        t.id = "iron_bull"
        t.price = 34_000
        t.summary = "A torque monster that pulls the heaviest loads like they're empty, but it drinks fuel. Lumpy, barking V8."
        t.massKg = 19_000
        t.torqueCurve = [
            .init(rpm: 600, torque: 2_000), .init(rpm: 1_000, torque: 3_200), .init(rpm: 1_400, torque: 3_300),
            .init(rpm: 1_800, torque: 2_700), .init(rpm: 2_100, torque: 2_000),
        ]
        t.cylinders = 8
        t.tractionLimitAccel = 3.0
        t.maxBrakeDecel = 5.2
        t.steeringLatAccel = 3.0
        t.fuelCapacityLiters = 700
        t.fuelEfficiency = 1.1
        t.speedLimiter = 95 / 3.6
        t.sound = EngineSound(pitch: 0.72, roughness: 0.5, turbo: 0.7, bark: 0.9, lope: 0.5)
        return t
    }()

    /// Electric: instant power, no gears, charged at truck stops, cheap to run.
    static let volt: TruckSpec = {
        var t = TruckSpec.starter
        t.name = "Volt"
        t.id = "volt"
        t.price = 40_000
        t.summary = "An electric truck. Instant power and no gear changes: you hear a motor whine that rises with your speed. Charge it at truck stops; it costs about half as much to run."
        t.isElectric = true
        t.massKg = 18_500
        t.torqueCurve = [
            .init(rpm: 0, torque: 2_200), .init(rpm: 2_500, torque: 2_200), .init(rpm: 4_000, torque: 1_500),
            .init(rpm: 6_000, torque: 900),
        ]
        t.idleRPM = 0
        t.maxRPM = 6_000
        t.cylinders = 0
        t.engineStartSeconds = 0.4
        t.gearRatios = [10.0]
        t.finalDrive = 1.0
        t.drivetrainEfficiency = 0.95
        t.shiftUpRPM = 6_000
        t.shiftDownRPM = 0
        t.engineBrakeFraction = 0.25 // regenerative braking
        t.tractionLimitAccel = 2.8
        t.maxBrakeDecel = 5.0
        t.steeringLatAccel = 3.3
        t.fuelCapacityLiters = 500
        t.fuelEfficiency = 0.55
        t.speedLimiter = 100 / 3.6
        t.sound = EngineSound(pitch: 1, roughness: 0, turbo: 0, bark: 0, lope: 0, electric: true)
        return t
    }()

    /// The flagship: the best at everything.
    static let titan: TruckSpec = {
        var t = TruckSpec.starter
        t.name = "Titan"
        t.id = "titan"
        t.price = 60_000
        t.summary = "The flagship. The most power, the best brakes and grip, and a big tank: the best at everything. A screaming V12 with straight pipes."
        t.massKg = 18_000
        t.torqueCurve = [
            .init(rpm: 600, torque: 2_200), .init(rpm: 1_000, torque: 3_300), .init(rpm: 1_400, torque: 3_600),
            .init(rpm: 1_800, torque: 3_300), .init(rpm: 2_100, torque: 2_600),
        ]
        t.cylinders = 12
        t.tractionLimitAccel = 3.2
        t.maxBrakeDecel = 5.5
        t.steeringLatAccel = 3.4
        t.fuelCapacityLiters = 800
        t.speedLimiter = 100 / 3.6
        t.sound = EngineSound(pitch: 0.68, roughness: 0.2, turbo: 0.8, bark: 1, lope: 0.2)
        return t
    }()

    /// Every truck in the garage, cheapest first.
    static let catalog: [TruckSpec] = [{
        var t = TruckSpec.starter
        t.summary = "Your first truck. Steady six-cylinder with a little turbo: nothing fancy, never lets you down."
        return t
    }(), .farmRunner, .workhorse, .cityHauler, .mountainGoat, .roadKing, .highwayStar, .longHauler, .ironBull, .volt, .titan]

    /// Peak engine power, horsepower.
    var horsepower: Int {
        let watts = torqueCurve.map { $0.torque * $0.rpm * 2 * .pi / 60 }.max() ?? 0
        return Int((watts / 745.7 / 10).rounded()) * 10
    }

    static func withID(_ id: String) -> TruckSpec {
        catalog.first { $0.id == id } ?? .starter
    }
}
