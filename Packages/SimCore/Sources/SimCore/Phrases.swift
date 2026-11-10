import Foundation

public enum UnitSystem: String, CaseIterable, Sendable {
    case metric, imperial

    public func speed(_ metresPerSecond: Double) -> Int {
        Int((metresPerSecond * (self == .metric ? 3.6 : 2.236_94)).rounded())
    }

    public var speedUnitSpoken: String { self == .metric ? "kilometers per hour" : "miles per hour" }

    /// Distances rounded the way a co-driver would say them.
    public func distance(_ metres: Double) -> String {
        switch self {
        case .metric:
            if metres >= 1_000 {
                let km = (metres / 100).rounded() / 10
                return km == km.rounded() ? "\(Int(km)) kilometers" : String(format: "%.1f kilometers", km)
            }
            let rounded = metres >= 200 ? (metres / 50).rounded() * 50 : (metres / 10).rounded() * 10
            return "\(Int(rounded)) meters"
        case .imperial:
            let feet = metres * 3.280_84
            if feet >= 1_000 {
                let miles = (metres / 1_609.34 * 10).rounded() / 10
                return miles == 1 ? "1 mile" : String(format: "%.1f miles", miles)
            }
            return "\(Int((feet / 50).rounded() * 50)) feet"
        }
    }
}

/// Builds the sentences the game speaks. Kept here (not in the app) so it is unit-testable.
public struct Phrases {
    public var units: UnitSystem
    /// Driving an electric truck: "battery" and "charge" instead of "fuel" and "fill up".
    public var electric: Bool

    public init(units: UnitSystem, electric: Bool = false) {
        self.units = units
        self.electric = electric
    }

    private var fuelWord: String { electric ? "battery" : "fuel" }

    public func curve(_ c: UpcomingCurve) -> String {
        let suggest = units.speed(c.advisorySpeed)
        var text = "\(c.severity.rawValue.capitalized) \(c.direction.rawValue) curve in \(units.distance(c.distance))"
        if c.severity != .gentle { text += ", slow to \(suggest)" }
        return text + "."
    }

    public func roadAhead(_ c: UpcomingCurve?, remaining: Double? = nil, timeLeft: Double? = nil,
                          truckStop: Double? = nil) -> String {
        var text = ""
        if let remaining {
            text = remaining > 0 ? "\(units.distance(remaining)) to the drop-off. " : "You're at the drop-off. "
        }
        if let timeLeft {
            text += timeLeft > 0 ? "\(duration(timeLeft, roundToMinutes: timeLeft >= 120)) left. " : "You're late. "
        }
        let stop = truckStop.map { " " + roadAheadTruckStop($0) } ?? ""
        guard let c else { return text + "Straight road ahead." + stop }
        return text + "Next: " + curve(c) + stop
    }

    public func duration(_ seconds: Double, roundToMinutes: Bool = false) -> String {
        if roundToMinutes {
            let m = Int((seconds / 60).rounded())
            return "\(m) minute\(m == 1 ? "" : "s")"
        }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        if h > 0 { return unit(h, "hour") + " " + unit(m, "minute") }
        if m > 0 { return unit(m, "minute") + " " + unit(s, "second") }
        return unit(s, "second")
    }

    public func tripProgress(remaining: Double) -> String {
        "\(units.distance(remaining)) to the drop-off."
    }

    public func destinationAhead(_ distance: Double) -> String {
        "Drop-off in \(units.distance(distance)). Slow down and stop at the drop-off."
    }

    public let atDestination = "You're at the drop-off. Stop now."

    // MARK: Fuel and truck stops

    public func fuelLow(fraction: Double, nextStop: Double?, urgent: Bool) -> String {
        var text: String
        if electric {
            text = urgent ? "Battery very low, \(Int((fraction * 100).rounded())) percent!" : "Battery low, a quarter charge."
        } else {
            text = urgent ? "Fuel very low, \(Int((fraction * 100).rounded())) percent!" : "Fuel low, a quarter tank."
        }
        if let nextStop { text += " Next truck stop in \(units.distance(nextStop)). Signal right before it and slow down to pull in." }
        return text
    }

    public func truckStopAhead(_ distance: Double) -> String {
        "Truck stop in \(units.distance(distance)). To \(electric ? "charge" : "fill up"), signal right and slow below \(units.speed(DrivingSession.truckStopExitSpeed)) before you reach it."
    }

    public var pulledIntoTruckStop: String {
        electric ? "Pulling into the truck stop. Stop at the charger to charge up."
                 : "Pulling into the truck stop. Stop at the pump to fill up."
    }

    public func missedTruckStop(tooFast: Bool) -> String {
        tooFast ? "Too fast to take the truck stop exit. You missed it." : "You passed the truck stop."
    }

    public var refuelStarted: String { electric ? "Charging." : "Filling up." }

    public func refueled(liters: Double, cost: Int) -> String {
        if electric { return "Charged: \(Int(liters.rounded())) kilowatt hours for \(Phrases.money(cost)). Back on the road when you're ready." }
        let amount = units == .metric ? "\(Int(liters.rounded())) liters" : String(format: "%.0f gallons", liters * 0.264_17)
        return "Filled up: \(amount) for \(Phrases.money(cost)). Back on the road when you're ready."
    }

    public let leftTruckStop = "Back on the road."

    public func towed(cost: Int, fuelCost: Int) -> String {
        "A tow truck took you to the next truck stop and \(electric ? "charged a quarter of the battery" : "put in a quarter tank"). Tow \(Phrases.money(cost)), \(fuelWord) \(Phrases.money(fuelCost)). That took 2 minutes. Start the engine to go on."
    }

    public func roadAheadTruckStop(_ distance: Double) -> String {
        "Next truck stop in \(units.distance(distance))."
    }

    // MARK: Map and GPS

    private func turnPhrase(_ turn: Turn) -> String {
        switch turn {
        case .left: return "turn left"
        case .right: return "turn right"
        case .straight: return "go straight"
        case .uTurn: return "turn around"
        }
    }

    public func navInstruction(_ n: NavInstruction) -> String {
        let signal: String
        switch n.turn {
        case .left: signal = " Signal left."
        case .right: signal = " Signal right."
        case .straight: signal = " No signal needed."
        case .uTurn: signal = ""
        }
        return "In \(units.distance(n.distance)), \(turnPhrase(n.turn)) onto \(n.roadName) toward \(n.toward).\(signal)"
    }

    public func junctionAhead(_ choices: [JunctionChoice], distance: Double) -> String {
        let order: [Turn] = [.left, .straight, .right, .uTurn]
        let parts = choices.sorted { order.firstIndex(of: $0.turn)! < order.firstIndex(of: $1.turn)! }.map { c -> String in
            switch c.turn {
            case .left: return "left on \(c.roadName) to \(c.toward)"
            case .right: return "right on \(c.roadName) to \(c.toward)"
            case .straight: return "straight on \(c.roadName) to \(c.toward)"
            case .uTurn: return "turn around to \(c.toward)"
            }
        }
        if parts.count == 1 { return "In \(units.distance(distance)), the road continues: \(parts[0])." }
        return "Junction in \(units.distance(distance)): " + parts.joined(separator: ", ") + ". Signal to choose."
    }

    public func tookRoad(roadName: String, toward: String, length: Double) -> String {
        "\(roadName) toward \(toward), \(units.distance(length))."
    }

    /// Warning just before a junction when the signal doesn't match the route.
    public func signalMismatch(_ n: NavInstruction, signal: SignalState) -> String {
        switch (n.turn, signal) {
        case (.straight, .on(let side)):
            return "Your \(side.rawValue) signal is on, but the route goes straight on \(n.roadName). Cancel the signal."
        case (.left, .off), (.right, .off):
            return "Signal \(n.turn.rawValue) now to turn onto \(n.roadName)."
        default:
            return "Wrong signal! The route turns \(n.turn.rawValue) onto \(n.roadName)."
        }
    }

    public func rerouted(_ remaining: Double) -> String {
        "That's off the route. Recalculating. New route: \(units.distance(remaining)) to the drop-off."
    }

    public let missedDropOff = "You drove past the drop-off. Recalculating a way back."

    public func enteredTown(_ name: String, speedLimit: Double) -> String {
        "Entering \(name). Speed limit \(units.speed(speedLimit))."
    }

    public func leftTown(_ name: String, speedLimit: Double) -> String {
        "Leaving \(name). Speed limit \(units.speed(speedLimit))."
    }

    // MARK: Living world

    public func deerAhead(_ distance: Double) -> String {
        "Deer on the road, \(units.distance(distance)) ahead! Honk or slow down."
    }

    public func deerGone(scared: Bool) -> String {
        scared ? "The deer ran off. Road's clear." : "The deer jumped out of the way. Road's clear."
    }

    public func enteredConstruction(speedLimit: Double) -> String {
        "Construction zone. One lane. Speed limit \(units.speed(speedLimit)). Fines doubled."
    }

    public func leftConstruction(speedLimit: Double) -> String {
        "End of construction. Speed limit \(units.speed(speedLimit))."
    }

    public func tollBoothAhead(_ distance: Double) -> String {
        "Toll booth in \(units.distance(distance)). Slow below \(units.speed(DrivingSession.tollSpeed)) to pay \(Phrases.money(DrivingSession.tollCost))."
    }

    public func tollPaid(_ cost: Int) -> String { "Toll paid: \(Phrases.money(cost)). Have a good drive." }

    public func ranToll(_ fine: Int) -> String {
        "You blew through the toll booth! Fine: \(Phrases.money(fine)). Slow down for tolls next time."
    }

    public func weighStationAhead(_ distance: Double) -> String {
        "Weigh station ahead. Trucks must pull in. It's in \(units.distance(distance)): signal right and slow below \(units.speed(DrivingSession.truckStopExitSpeed)) to pull in."
    }

    /// The load's weight the way the scale reads it out.
    public func cargoWeight(_ kg: Double) -> String {
        if units == .metric {
            let t = Int((kg / 1_000).rounded())
            return "\(t) tonne\(t == 1 ? "" : "s")"
        }
        let t = Int((kg / 907.185).rounded())
        return "\(t) ton\(t == 1 ? "" : "s")"
    }

    public func weighedIn(cargoKg: Double, fine: Int) -> String {
        let load = cargoKg > 0 ? "On the scale. Your load weighs \(cargoWeight(cargoKg))." : "On the scale. No load."
        if fine == 0 { return "\(load) You're good to go, driver." }
        return "\(load) That's a heavy load on a truck that crashed this trip. Unsafe load fine: \(Phrases.money(fine))."
    }

    public func skippedWeighStation(fine: Int, tooFast: Bool) -> String {
        tooFast
            ? "Too fast to pull into the weigh station! That counts as skipping it. Fine: \(Phrases.money(fine)). Slow down sooner next time."
            : "You skipped the weigh station! Fine: \(Phrases.money(fine)). Signal right to pull in next time."
    }

    // MARK: Blowouts and wear

    public func blowout(_ side: Side) -> String {
        "Blowout! Your \(side.rawValue) front tire burst. The truck is pulling \(side.rawValue): steer \(side == .left ? "right" : "left") to hold your lane, ease off the gas and slow down gently. Stop to change the tire."
    }

    public func tireChanged(cost: Int) -> String {
        "Tire changed on the roadside: \(Phrases.money(cost)). You're good to go."
    }

    // MARK: Hills

    public func hillAhead(grade: Double, length: Double) -> String {
        let percent = Int((abs(grade) * 100).rounded())
        if grade < 0 {
            return "Steep grade ahead: \(percent) percent downhill for \(units.distance(length)). Slow down before it, and let the engine hold you back. Use the brakes in short pushes so they don't overheat."
        }
        return "Climb ahead: \(percent) percent uphill for \(units.distance(length)). Keep your foot down."
    }

    public let brakesHot = "Your brakes are getting hot. Ease off and brake in short pushes."
    public let brakesFading = "Brakes are fading! They're too hot to stop you well. Slow down any way you can."

    public func runawayRampAhead(_ distance: Double) -> String {
        "Runaway truck ramp in \(units.distance(distance)), on the right. If you can't slow down, signal right to take it."
    }

    public func tookRunawayRamp(cost: Int) -> String {
        "You took the runaway truck ramp. The gravel stopped you safely, and your brakes are cooling. Tow out of the gravel: \(Phrases.money(cost))."
    }

    // MARK: Docking

    /// Short distances said exactly (docking): "5 meters", "16 feet".
    func dockDistance(_ metres: Double) -> String {
        if units == .metric {
            let m = Int(metres.rounded())
            return "\(m) meter\(m == 1 ? "" : "s")"
        }
        let ft = Int((metres * 3.280_84).rounded())
        return "\(ft) \(ft == 1 ? "foot" : "feet")"
    }

    public func dockingStarted(_ distance: Double) -> String {
        "Now back into the loading dock. It's \(dockDistance(distance)) behind you. Accelerate to back up slowly, brake to stop. The beeps speed up as you get close. If the lane beep sounds, steer away from it to straighten the trailer. To skip docking, pause and choose Skip Docking."
    }

    public func dockingProgress(_ distance: Double, lateral: Double) -> String {
        let side = abs(lateral) <= 0.3 ? "Straight." : (lateral > 0 ? "A little left." : "A little right.")
        return "\(dockDistance(distance)). \(side)"
    }

    public func docked(_ rating: DockRating) -> String {
        switch rating {
        case .perfect: return "Perfect docking! Right in the middle of the dock."
        case .good: return "Docked. A little off center, but good."
        case .crooked: return "Docked, but crooked. Straighten up sooner next time."
        case .bumped: return "Bang! You bumped the dock. Back up slower at the end."
        case .skipped: return "Docking skipped."
        }
    }

    // MARK: Special cargo

    /// How to drive with this load, said when the job starts.
    public func cargoRules(_ kind: CargoKind) -> String? {
        switch kind {
        case .standard: return nil
        case .livestock: return "Livestock: brake gently and take curves slowly. Every scare costs you pay."
        case .refrigerated: return "Refrigerated: you'll hear the cooling unit. Arrive late and the load spoils, which costs a quarter of the pay."
        case .oversize: return "Oversize load: stay under \(units.speed(DrivingSession.oversizeSpeedLimit)) \(units.speedUnitSpoken). Every warning costs you pay."
        case .hazmat: return "Hazmat: the best pay, but one crash spills the load. No pay, and a \(Phrases.money(DrivingSession.hazmatCleanupCost)) cleanup bill."
        }
    }

    public let livestockScared = "Whoa! The animals are scared. Easy on the brakes and the curves."

    public func oversizeTooFast(limit: Double) -> String {
        "Wide load! Slow down below \(units.speed(limit)) \(units.speedUnitSpoken)."
    }

    public let cargoSpoiling = "You're past the deadline. The load is starting to spoil!"

    public func hazmatSpill(cost: Int) -> String {
        "Hazmat spill! The load is lost. Cleanup bill: \(Phrases.money(cost)). Drive to the drop-off to close out the job."
    }

    // MARK: Turbo Mode

    public func turboSpeed(_ speed: Double) -> String {
        let n = units.speed(speed)
        let rounded = units == .metric ? (n + 5) / 10 * 10 : (n + 2) / 5 * 5
        return "\(rounded) \(units.speedUnitSpoken)!"
    }

    public let turboIntro = "Turbo Mode is on: no speed limit and no police. Hold on tight, and slow down for curves."

    // MARK: Company

    public func driver(_ d: Driver) -> String {
        "\(d.name), \(d.stars). About \(Phrases.money(d.hourlyEarnings)) an hour, one delivery every \(Int(d.minutesPerJob)) minutes."
    }

    /// "While you were away: Sam Hayes delivered 4 jobs and earned $1,200. ..."
    public static func driverReports(_ reports: [DriverReport]) -> String? {
        guard !reports.isEmpty else { return nil }
        let parts = reports.map { r -> String in
            var text = r.jobs > 0 ? "\(r.name) delivered \(r.jobs) job\(r.jobs == 1 ? "" : "s") and earned \(Phrases.money(r.earned))" : ""
            if let town = r.brokeDownIn {
                text += (text.isEmpty ? "" : ". ") + "\(r.name) called on the radio: their truck broke down near \(town). Send a tow for \(Phrases.money(Driver.towCost)), or let them wait two hours for a repair: answer in the Company screen"
            }
            if let raise = r.askedForRaise {
                text += ". \(r.name) has the experience to move up a star and asks for a raise of \(Phrases.money(raise)): answer in the Company screen"
            }
            if r.quit { text += ". \(r.name) quit: nobody answered their raise request. Their truck is free now" }
            return text
        }
        let total = reports.reduce(0) { $0 + $1.earned }
        if reports.count == 1 && reports[0].jobs == 0 { return "Your drivers: " + parts[0] + "." }
        return "Your drivers: " + parts.joined(separator: ". ") + (reports.count > 1 ? ". Total \(Phrases.money(total))." : ".")
    }

    // MARK: Traffic

    public func changedLane(toLeft: Bool, oncoming: Bool) -> String {
        if !toLeft { return "Back in your lane." }
        return oncoming ? "Oncoming lane. Pass quickly and get back." : "Left lane."
    }

    public let wrongSideOfRoad = "Oncoming traffic! Get back in your lane!"

    public func vehicleAhead(distance: Double, speed: Double, kind: VehicleKind) -> String {
        "Slow \(kind.rawValue) ahead, \(units.distance(distance)), doing \(units.speed(speed)). Slow down or pass."
    }

    public let tooClose = "Too close! Brake!"

    // MARK: Police

    public func policeChase(speed: Double, limit: Double) -> String {
        "Police! You were doing \(units.speed(speed)) in a \(units.speed(limit)). Pull over: slow down and stop."
    }

    public func speedingTicket(speed: Double, limit: Double, fine: Int) -> String {
        "Speeding ticket: \(units.speed(speed)) in a \(units.speed(limit)). Fine \(Phrases.money(fine)). You can go."
    }

    public func fledPolice(_ fine: Int) -> String {
        "You didn't stop for the police. Fine \(Phrases.money(fine))."
    }

    public func onShoulder(_ side: Side) -> String {
        "On the \(side.rawValue) shoulder. Steer \(side == .left ? "right" : "left") to get back on the road."
    }

    public func stoppedShort(_ remaining: Double) -> String {
        "The drop-off is \(units.distance(remaining)) ahead. Keep going."
    }

    // MARK: Money and jobs

    /// "$12,450" (VoiceOver and the speech synthesizer both read this as dollars).
    public static func money(_ amount: Int) -> String {
        let digits = String(abs(amount))
        var grouped = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(",") }
            grouped.append(ch)
        }
        return (amount < 0 ? "minus $" : "$") + String(grouped.reversed())
    }

    public func weight(_ kg: Double) -> String {
        units == .metric ? "\(Int((kg / 1_000).rounded())) tonnes" : "\(Int((kg * 2.204_62 / 2_000).rounded())) tons"
    }

    /// Whether the fuel in the tank covers a trip.
    public func fuelCheck(fuelLiters: Double, capacity: Double, distance: Double, cargoKg: Double = 0,
                          efficiency: Double = 1) -> String {
        let needed = CareerState.fuelNeeded(forDistance: distance, cargoKg: cargoKg) * efficiency
        let percent = Int((fuelLiters / capacity * 100).rounded())
        if electric {
            if fuelLiters >= needed { return "Battery OK: \(percent) percent." }
            return "Not enough charge: \(percent) percent. Charge up first, or stop at a truck stop on the way."
        }
        if fuelLiters >= needed { return "Fuel OK: \(percent) percent." }
        return "Not enough fuel: \(percent) percent. Fill up first, or stop at a truck stop on the way."
    }

    public func job(_ job: DeliveryJob) -> String {
        let route = job.destinationName.map { " to \($0)" } ?? ""
        var parts = ["\(job.cargo.name)\(route), \(units.distance(job.distance))",
                     "pays \(Phrases.money(job.pay))",
                     "time limit \(duration(job.timeLimit, roundToMinutes: true))",
                     weight(job.cargo.massKg)]
        if job.contractID != nil { parts.insert("Contract job", at: 0) }
        if let kind = job.cargo.kind.label { parts.append(kind) }
        if job.cargo.urgent { parts.append("urgent") }
        if job.cargo.fragile { parts.append("fragile") }
        return parts.joined(separator: ", ") + "."
    }

    public func jobIntro(_ job: DeliveryJob) -> String {
        let towns = job.originName.flatMap { o in job.destinationName.map { "from \(o) to \($0), " } } ?? ""
        var text = "Job: deliver \(job.cargo.name.lowercased()), \(weight(job.cargo.massKg)), \(towns)"
            + "\(units.distance(job.distance)) to the drop-off. "
            + "Time limit \(duration(job.timeLimit, roundToMinutes: true)). Pays \(Phrases.money(job.pay))."
        if let rules = cargoRules(job.cargo.kind) { text += " " + rules }
        if job.cargo.fragile { text += " Fragile: crashes damage this load badly." }
        if job.cargo.massKg >= 18_000 { text += " Heavy load: give yourself extra room to brake." }
        return text
    }

    public func timeLeft(_ seconds: Double) -> String {
        seconds >= 120 ? "\(duration(seconds, roundToMinutes: true)) left to deliver." : "One minute left to deliver!"
    }

    public let lateForDelivery = "You're late. The pay drops a little for every minute."

    /// A truck's details for the garage.
    public func truck(_ t: TruckSpec) -> String {
        let tank = t.isElectric ? "\(Int(t.fuelCapacityLiters)) kilowatt hour battery"
            : units == .metric ? "\(Int(t.fuelCapacityLiters)) liter tank" : "\(Int((t.fuelCapacityLiters * 0.264_17).rounded())) gallon tank"
        return "\(t.name). \(t.horsepower) horsepower, top speed \(units.speed(t.speedLimiter)) \(units.speedUnitSpoken), \(tank). \(t.summary)"
    }

    public func payout(_ p: Payout) -> String {
        let lines = p.lines.map { line in
            line.amount < 0 ? "\(line.label): minus \(Phrases.money(-line.amount))."
                            : "\(line.label): \(Phrases.money(line.amount))."
        }
        let total = p.total >= 0 ? "You earned \(Phrases.money(p.total))." : "This drive cost you \(Phrases.money(-p.total))."
        return (lines + [total] + p.news).joined(separator: " ")
    }

    /// The trip status shown in the pause menu.
    public func tripStatus(goal: TripGoal, stats: TripStats, remaining: Double?, timeLeft: Double? = nil,
                          earnedSoFar: Int? = nil) -> String {
        var parts: [String] = [goal.name + "."]
        if let total = goal.distance, let remaining {
            let left = max(0, remaining)
            let percent = Int((min(1, stats.distance / total) * 100).rounded())
            parts.append("\(units.distance(stats.distance)) driven, \(units.distance(left)) to the drop-off, \(percent) percent done.")
        } else {
            parts.append("No destination: drive as long as you like. \(units.distance(stats.distance)) driven.")
        }
        parts.append("Driving time \(duration(stats.drivingTime)).")
        if stats.drivingTime > 0 {
            parts.append("Average speed \(units.speed(stats.averageSpeed)), top speed \(units.speed(stats.topSpeed)) \(units.speedUnitSpoken).")
        }
        parts.append(stats.crashes == 0 ? "No crashes." : "Crashes: \(stats.crashes).")
        if let timeLeft {
            parts.append(timeLeft > 0 ? "Time left: \(duration(timeLeft))." : "Late by \(duration(-timeLeft)).")
        }
        if let earnedSoFar { parts.append("Earned so far: \(Phrases.money(earnedSoFar)).") }
        return parts.joined(separator: " ")
    }

    public func arrived(_ s: TripSummary) -> String {
        let stop: String
        switch s.stopRating {
        case .perfect: stop = "Perfect stop, right at the drop-off."
        case .good:
            let d = units.distance(abs(s.stopError))
            stop = "Good stop, \(d) \(s.stopError >= 0 ? "past" : "before") the drop-off."
        case .overshot: stop = "You stopped \(units.distance(s.stopError)) past the drop-off."
        }
        return "Delivered! \(s.goalName) complete. \(stop) " + tripResults(s.stats)
    }

    public func tripResults(_ st: TripStats) -> String {
        var parts = ["Time \(duration(st.drivingTime)).",
                     "Distance \(units.distance(st.distance)).",
                     "Average speed \(units.speed(st.averageSpeed)), top speed \(units.speed(st.topSpeed)) \(units.speedUnitSpoken)."]
        parts.append(st.crashes == 0 ? "No crashes." : "Crashes: \(st.crashes).")
        if st.tooFastWarnings > 0 { parts.append("Too fast for a curve \(st.tooFastWarnings) time\(st.tooFastWarnings == 1 ? "" : "s").") }
        if electric {
            parts.append(String(format: "Energy used %.0f kilowatt hours.", st.fuelUsedLiters))
        } else {
            parts.append(units == .metric ? String(format: "Fuel used %.0f liters.", st.fuelUsedLiters)
                                          : String(format: "Fuel used %.1f gallons.", st.fuelUsedLiters * 0.264_17))
        }
        return parts.joined(separator: " ")
    }

    public func dashboard(_ d: DashboardReading) -> String {
        var parts: [String] = []
        parts.append("\(units.speed(d.speed)) \(units.speedUnitSpoken)")
        switch d.engine {
        case .off: parts.append(electric ? "motor off" : "engine off")
        case .starting: parts.append(electric ? "powering up" : "engine starting")
        case .running:
            if !electric {
                parts.append("gear \(d.gear)")
                parts.append("\(Int((d.rpm / 50).rounded() * 50)) RPM")
            }
        }
        parts.append("\(fuelWord) \(Int((d.fuelFraction * 100).rounded())) percent, about \(units.distance(d.range)) left")
        let temp = units == .metric ? "\(Int(d.engineTempC.rounded())) degrees" : "\(Int((d.engineTempC * 9 / 5 + 32).rounded())) degrees"
        parts.append("\(electric ? "motor" : "engine") temperature \(temp)")
        if case let .on(side) = d.signal { parts.append("\(side.rawValue) signal on") }
        parts.append("limit \(units.speed(d.speedLimit))")
        return parts.joined(separator: ", ") + "."
    }

    public func signal(_ s: SignalState) -> String {
        switch s {
        case .off: return "Signal off."
        case let .on(side): return "\(side.rawValue.capitalized) signal."
        }
    }

    public func crash(_ reason: CrashReason) -> String {
        switch reason {
        case let .leftRoad(side):
            return "Crash! You ran off the \(side.rawValue) side of the road. Truck recovered to the lane."
        case let .collision(headOn, vehicle):
            return headOn ? "Crash! Head-on with an oncoming \(vehicle.rawValue). Stay in your lane when traffic is coming."
                          : "Crash! You hit the \(vehicle.rawValue) in front of you. Slow down sooner behind traffic."
        case .animal:
            return "Crash! You hit a deer. Next time, honk to scare it off, or slow right down."
        }
    }
}
