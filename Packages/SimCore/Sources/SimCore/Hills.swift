import Foundation

/// A stretch of road that climbs (positive grade) or descends (negative), in the direction of travel.
public struct Hill: Equatable, Sendable {
    public var start: Double
    public var end: Double
    /// Rise over run: 0.06 is a 6% climb, -0.06 a 6% descent.
    public var grade: Double
    /// A runaway truck ramp partway down a steep descent (metres along the road), or nil.
    public var runawayRamp: Double?

    public var length: Double { end - start }
}

public extension Road {
    /// How long the road takes to go from flat to the full grade, metres.
    static let gradeTransition = 120.0

    /// The grade at a position, easing in and out at each hill's ends.
    func grade(at position: Double) -> Double {
        guard let h = hills.first(where: { position >= $0.start && position <= $0.end }) else { return 0 }
        let edge = min(position - h.start, h.end - position)
        return h.grade * min(1, edge / Road.gradeTransition)
    }

    /// Hills for a generated road: away from the ends (towns and junctions), steeper in the mountains.
    static func makeHills(length: Double, style: RoadStyle, seed: UInt64) -> [Hill] {
        var rng = SeededRandom(seed: seed &+ 0x4111)
        let (gradeRange, lengthRange, gapRange): (ClosedRange<Double>, ClosedRange<Double>, ClosedRange<Double>)
        switch style {
        case .interstate: (gradeRange, lengthRange, gapRange) = (0.01...0.03, 900...2_000, 1_500...3_500)
        case .country: (gradeRange, lengthRange, gapRange) = (0.02...0.04, 600...1_400, 700...1_800)
        case .mountain: (gradeRange, lengthRange, gapRange) = (0.04...0.07, 800...1_800, 300...800)
        }
        var hills: [Hill] = []
        var s = 1_500 + Double.random(in: gapRange, using: &rng) * 0.5
        var up = Bool.random(using: &rng)
        while true {
            let len = Double.random(in: lengthRange, using: &rng).rounded()
            guard s + len < length - 1_500 else { break }
            let grade = Double.random(in: gradeRange, using: &rng) * (up ? 1 : -1)
            var hill = Hill(start: s, end: s + len, grade: (grade * 1_000).rounded() / 1_000)
            if style == .mountain && hill.grade <= -0.055 && len >= 1_000 { hill.runawayRamp = s + len * 0.65 }
            hills.append(hill)
            s += len + Double.random(in: gapRange, using: &rng).rounded()
            // Mostly up then down, like real hills; sometimes two climbs in a row.
            if Double.random(in: 0...1, using: &rng) < 0.8 { up.toggle() }
        }
        return hills
    }
}

public extension DrivingSession {
    /// Brake temperature where warnings start, and where braking starts to fade, °C.
    static let brakeHotTemp = 300.0
    static let brakeFadeTemp = 400.0
    /// The steepest descent the engine brake holds by itself.
    static let engineBrakeGrade = 0.035
    /// Hills at least this steep are announced.
    static let announcedGrade = 0.03
}

extension DrivingSession {
    /// Brakes lose grip as they overheat: 1 when cool, down to 0.35 when very hot.
    var brakeFade: Double {
        let over = max(0, truck.brakeTempC - DrivingSession.brakeHotTemp)
        return max(0.35, 1 - over / 400)
    }

    /// Heats the brakes with use (more at speed) and lets them cool in the air.
    func stepBrakes(dt: Double, input: DrivingInput, events: inout [SimEvent]) {
        // Heat follows the braking power actually used (deceleration times speed); air cools them faster at speed.
        let heat = lastBrakeDecel * truck.speed * 2.3
        let cooling = (truck.brakeTempC - 40) * (0.012 + truck.speed * 0.0008)
        truck.brakeTempC = min(700, max(40, truck.brakeTempC + (heat - cooling) * dt))
        if truck.brakeTempC >= DrivingSession.brakeFadeTemp && !warnedBrakeFade {
            warnedBrakeFade = true
            events.append(.brakesFading)
        } else if truck.brakeTempC >= DrivingSession.brakeHotTemp && !warnedBrakeHot {
            warnedBrakeHot = true
            events.append(.brakesHot)
        }
        // Cool enough again: warn afresh next time.
        if truck.brakeTempC < DrivingSession.brakeHotTemp - 80 { warnedBrakeHot = false; warnedBrakeFade = false }
    }

    /// Announces steep hills ahead, and runaway ramps when the brakes are hot; takes the ramp on a right signal.
    func checkHills(events: inout [SimEvent]) {
        let lookahead = max(400, truck.speed * 15)
        for (i, h) in road.hills.enumerated() where abs(h.grade) >= DrivingSession.announcedGrade && !announcedHills.contains(i) {
            let ahead = h.start - truck.position
            if ahead > 0 && ahead < lookahead && truck.speed > 3 {
                announcedHills.insert(i)
                events.append(.hillAhead(grade: h.grade, length: h.length))
            }
        }
        for (i, h) in road.hills.enumerated() {
            guard let ramp = h.runawayRamp else { continue }
            let ahead = ramp - truck.position
            if ahead > 0 && ahead < 600 && !announcedRamps.contains(i) && truck.brakeTempC >= DrivingSession.brakeHotTemp {
                announcedRamps.insert(i)
                events.append(.runawayRampAhead(distance: ahead))
            }
            if ahead <= 0 && ahead > -40 && truck.signal == .on(.right) && !usedRamps.contains(i) && truck.speed > 5 {
                usedRamps.insert(i)
                // Deep gravel: the truck stops safely, and the brakes get to cool.
                truck.speed = 0
                truck.signal = .off
                truck.brakeTempC = min(truck.brakeTempC, 150)
                stats.towCost += DrivingSession.runawayRampTow
                stats.tows += 1
                events.append(.tookRunawayRamp(cost: DrivingSession.runawayRampTow))
            }
        }
    }
}

public extension DrivingSession {
    /// Pulling the truck out of the runaway ramp's gravel.
    static let runawayRampTow = 150
}
