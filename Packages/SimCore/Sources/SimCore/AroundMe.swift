import Foundation

/// "What's around me": a snapshot of what's near the truck, for the three-finger swipe down.
public struct Surroundings: Equatable, Sendable {
    public struct Nearby: Equatable, Sendable {
        public let kind: VehicleKind
        /// Metres, bumper to bumper.
        public let distance: Double
        public let speed: Double
    }
    public var ahead: Nearby?
    public var behind: Nearby?
    public var oncoming: Nearby?
    public var deer: Double?
    public var weighStation: Double?
    /// Percent; positive is uphill.
    public var gradePercent: Double = 0
    public var weather: Weather = .clear
    public var speed: Double = 0
}

public extension DrivingSession {
    /// How far "around me" looks, metres.
    static let aroundRange = 500.0

    var surroundings: Surroundings {
        let me = truck.position, range = Self.aroundRange
        var s = Surroundings(weather: weather, speed: truck.speed)
        func nearby(_ v: TrafficVehicle) -> Surroundings.Nearby {
            .init(kind: v.kind, distance: max(0, abs(v.position - me) - v.length / 2 - 8), speed: v.speed)
        }
        let same = traffic.filter { !$0.oncoming }
        s.ahead = same.filter { $0.position > me && $0.position - me < range }.min { $0.position < $1.position }.map(nearby)
        s.behind = same.filter { $0.position <= me && me - $0.position < range }.max { $0.position < $1.position }.map(nearby)
        s.oncoming = traffic.filter { $0.oncoming && $0.position > me && $0.position - me < range * 2 }
            .min { $0.position < $1.position }.map(nearby)
        if let d = deer, d.position > me, d.position - me < range * 2, !d.scared { s.deer = d.position - me }
        s.weighStation = road.weighStations.filter { $0 > me }.min().map { $0 - me }.flatMap { $0 < 5_000 ? $0 : nil }
        s.gradePercent = (road.grade(at: me) * 100).rounded()
        return s
    }
}

public extension Phrases {
    private func vehicleWord(_ k: VehicleKind) -> String { k == .truck ? "truck" : k == .pickup ? "pickup" : "car" }

    func surroundings(_ s: Surroundings) -> String {
        var parts: [String] = []
        if let a = s.ahead {
            let pace = a.speed + 1 < s.speed ? ", slower than you" : ""
            parts.append("A \(vehicleWord(a.kind)) ahead in your lane, \(units.distance(a.distance))\(pace).")
        } else {
            parts.append("Your lane is clear ahead.")
        }
        if let b = s.behind { parts.append("A \(vehicleWord(b.kind)) behind you, \(units.distance(b.distance)).") }
        if let o = s.oncoming { parts.append("Oncoming \(vehicleWord(o.kind)) in the other lane, \(units.distance(o.distance)).") }
        if let d = s.deer { parts.append("A deer near the road, \(units.distance(d)) ahead. Honk to scare it off.") }
        if s.gradePercent >= 1 { parts.append("Going uphill, \(Int(s.gradePercent)) percent.") }
        else if s.gradePercent <= -1 { parts.append("Going downhill, \(Int(-s.gradePercent)) percent. Use the engine brake.") }
        if let w = s.weighStation { parts.append("Weigh station in \(units.distance(w)).") }
        switch s.weather {
        case .clear: break
        case .rain: parts.append("It's raining.")
        case .storm: parts.append("There's a storm.")
        case .snow: parts.append("It's snowing.")
        }
        return parts.joined(separator: " ")
    }
}
