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

    public init(units: UnitSystem) { self.units = units }

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
        var text = urgent ? "Fuel very low, \(Int((fraction * 100).rounded())) percent!" : "Fuel low, a quarter tank."
        if let nextStop { text += " Next truck stop in \(units.distance(nextStop)). Signal right before it and slow down to pull in." }
        return text
    }

    public func truckStopAhead(_ distance: Double) -> String {
        "Truck stop in \(units.distance(distance)). To fill up, signal right and slow below \(units.speed(DrivingSession.truckStopExitSpeed)) before you reach it."
    }

    public let pulledIntoTruckStop = "Pulling into the truck stop. Stop at the pump to fill up."

    public func missedTruckStop(tooFast: Bool) -> String {
        tooFast ? "Too fast to take the truck stop exit. You missed it." : "You passed the truck stop."
    }

    public let refuelStarted = "Filling up."

    public func refueled(liters: Double, cost: Int) -> String {
        let amount = units == .metric ? "\(Int(liters.rounded())) liters" : String(format: "%.0f gallons", liters * 0.264_17)
        return "Filled up: \(amount) for \(Phrases.money(cost)). Back on the road when you're ready."
    }

    public let leftTruckStop = "Back on the road."

    public func towed(cost: Int, fuelCost: Int) -> String {
        "A tow truck took you to the next truck stop and put in a quarter tank. Tow \(Phrases.money(cost)), fuel \(Phrases.money(fuelCost)). That took 5 minutes. Start the engine to go on."
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

    public func job(_ job: DeliveryJob) -> String {
        let route = job.destinationName.map { " to \($0)" } ?? ""
        var parts = ["\(job.cargo.name)\(route), \(units.distance(job.distance))",
                     "pays \(Phrases.money(job.pay))",
                     "time limit \(duration(job.timeLimit, roundToMinutes: true))",
                     weight(job.cargo.massKg)]
        if job.cargo.urgent { parts.append("urgent") }
        if job.cargo.fragile { parts.append("fragile") }
        return parts.joined(separator: ", ") + "."
    }

    public func jobIntro(_ job: DeliveryJob) -> String {
        let towns = job.originName.flatMap { o in job.destinationName.map { "from \(o) to \($0), " } } ?? ""
        var text = "Job: deliver \(job.cargo.name.lowercased()), \(weight(job.cargo.massKg)), \(towns)"
            + "\(units.distance(job.distance)) to the drop-off. "
            + "Time limit \(duration(job.timeLimit, roundToMinutes: true)). Pays \(Phrases.money(job.pay))."
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
        let tank = units == .metric ? "\(Int(t.fuelCapacityLiters)) liter tank" : "\(Int((t.fuelCapacityLiters * 0.264_17).rounded())) gallon tank"
        return "\(t.name). \(t.horsepower) horsepower, top speed \(units.speed(t.speedLimiter)) \(units.speedUnitSpoken), \(tank). \(t.summary)"
    }

    public func payout(_ p: Payout) -> String {
        let lines = p.lines.map { line in
            line.amount < 0 ? "\(line.label): minus \(Phrases.money(-line.amount))."
                            : "\(line.label): \(Phrases.money(line.amount))."
        }
        let total = p.total >= 0 ? "You earned \(Phrases.money(p.total))." : "This drive cost you \(Phrases.money(-p.total))."
        return (lines + [total]).joined(separator: " ")
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
        parts.append(units == .metric ? String(format: "Fuel used %.0f liters.", st.fuelUsedLiters)
                                      : String(format: "Fuel used %.1f gallons.", st.fuelUsedLiters * 0.264_17))
        return parts.joined(separator: " ")
    }

    public func dashboard(_ d: DashboardReading) -> String {
        var parts: [String] = []
        parts.append("\(units.speed(d.speed)) \(units.speedUnitSpoken)")
        switch d.engine {
        case .off: parts.append("engine off")
        case .starting: parts.append("engine starting")
        case .running:
            parts.append("gear \(d.gear)")
            parts.append("\(Int((d.rpm / 50).rounded() * 50)) RPM")
        }
        parts.append("fuel \(Int((d.fuelFraction * 100).rounded())) percent, about \(units.distance(d.range)) left")
        let temp = units == .metric ? "\(Int(d.engineTempC.rounded())) degrees" : "\(Int((d.engineTempC * 9 / 5 + 32).rounded())) degrees"
        parts.append("engine temperature \(temp)")
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
        }
    }
}
