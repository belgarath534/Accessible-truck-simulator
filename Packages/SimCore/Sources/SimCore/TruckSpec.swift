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
        engineStartSeconds: 1.4,
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
