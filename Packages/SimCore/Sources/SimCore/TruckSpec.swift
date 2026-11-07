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

    public init(recorded: Bool = false, pitch: Double = 1, roughness: Double = 0.3, turbo: Double = 0.3,
                bark: Double = 0.2, lope: Double = 0.1) {
        self.recorded = recorded
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

    /// Every truck in the garage, cheapest first.
    static let catalog: [TruckSpec] = [{
        var t = TruckSpec.starter
        t.summary = "Your first truck. Steady six-cylinder with a little turbo: nothing fancy, never lets you down."
        return t
    }(), .workhorse, .roadKing]

    /// Peak engine power, horsepower.
    var horsepower: Int {
        let watts = torqueCurve.map { $0.torque * $0.rpm * 2 * .pi / 60 }.max() ?? 0
        return Int((watts / 745.7 / 10).rounded()) * 10
    }

    static func withID(_ id: String) -> TruckSpec {
        catalog.first { $0.id == id } ?? .starter
    }
}
