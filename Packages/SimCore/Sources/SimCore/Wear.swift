import Foundation

// MARK: - Truck wear and service

public extension CareerState {
    /// Condition lost per kilometre driven, percent.
    static let wearPerKm = 0.05
    /// Condition lost per crash, percent.
    static let wearPerCrash = 3.0
    /// Service cost per percent restored.
    static let servicePerPercent = 15

    /// A truck's condition, 0...100 (100 is like new).
    func condition(of truck: TruckSpec) -> Double { truckCondition[truck.id] ?? 100 }

    /// Wears a truck after a drive.
    mutating func wear(_ truck: TruckSpec, kilometers: Double, crashes: Int) {
        let lost = kilometers * CareerState.wearPerKm + Double(crashes) * CareerState.wearPerCrash
        truckCondition[truck.id] = max(0, condition(of: truck) - lost)
    }

    /// What a full service costs.
    func serviceCost(_ truck: TruckSpec) -> Int {
        Int(((100 - condition(of: truck)) * Double(CareerState.servicePerPercent)).rounded())
    }

    /// Services a truck back to 100%. False if there's nothing to do or not enough money.
    @discardableResult
    mutating func service(_ truck: TruckSpec) -> Bool {
        let cost = serviceCost(truck)
        guard cost > 0, money >= cost else { return false }
        money -= cost
        truckCondition[truck.id] = 100
        return true
    }
}

public extension TruckSpec {
    /// A worn truck loses power: none above 50% condition, up to 15% at 0%.
    func worn(_ condition: Double) -> TruckSpec {
        guard condition < 50 else { return self }
        var t = self
        let loss = 1 - 0.15 * (50 - max(0, condition)) / 50
        t.torqueCurve = t.torqueCurve.map { TorquePoint(rpm: $0.rpm, torque: $0.torque * loss) }
        return t
    }
}

// MARK: - Tire blowouts

public extension DrivingSession {
    /// Roadside tire change after a blowout.
    static let tireChangeCost = 250
    /// Blowout chance per kilometre: rare on a good truck, much likelier on a worn one.
    static func blowoutChancePerKm(condition: Double) -> Double { 0.002 + (1 - condition / 100) * 0.02 }
}

extension DrivingSession {
    func checkBlowout(dt: Double, events: inout [SimEvent]) {
        if let side = blowout {
            // The blown tire drags the truck toward its side; hard braking makes it worse.
            let v = truck.speed
            truck.lateralOffset += (side == .right ? 1 : -1) * min(v, 20) * 0.035 * dt
            if v < 0.5 {
                blowout = nil
                stats.repairCost += DrivingSession.tireChangeCost
                events.append(.tireChanged(cost: DrivingSession.tireChangeCost))
            }
            return
        }
        guard blowoutsEnabled, truck.speed > 12, docking == nil else { return }
        let km = truck.speed * dt / 1_000
        if Double.random(in: 0...1, using: &rng) < DrivingSession.blowoutChancePerKm(condition: condition) * km {
            let side: Side = Bool.random(using: &rng) ? .left : .right
            blowout = side
            events.append(.blowout(side))
        }
    }
}
