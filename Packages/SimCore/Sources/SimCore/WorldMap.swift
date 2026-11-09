import Foundation

// MARK: - Map data

/// A place on the map: a town (with a depot where jobs start and end) or a junction.
public struct MapNode: Equatable, Sendable {
    public var id: String
    public var name: String
    /// Kilometres east and north, used only to work out which way roads turn at junctions.
    public var x: Double
    public var y: Double
    public var isTown: Bool
    /// Cargo this town ships out (by cargo name).
    public var exports: [String]
}

public enum RoadStyle: String, Sendable {
    case interstate, country, mountain

    public var speedLimit: Double {
        switch self {
        case .interstate: return 100 / 3.6
        case .country: return 80 / 3.6
        case .mountain: return 60 / 3.6
        }
    }
}

/// A two-way highway between two nodes. Its road geometry is stored in the a-to-b direction.
public struct MapEdge: Sendable {
    public var name: String
    public var a: String
    public var b: String
    public var style: RoadStyle
    public var road: Road
}

/// Speed limit inside towns, m/s.
public let townSpeedLimit = 50 / 3.6
/// How far a town's slow zone reaches along each road, metres.
public let townZoneLength = 1_200.0

public struct WorldMap: Sendable {
    public var nodes: [MapNode]
    public var edges: [MapEdge]

    public func node(_ id: String) -> MapNode? { nodes.first { $0.id == id } }
    public var towns: [MapNode] { nodes.filter(\.isTown) }

    /// Every directed edge leaving a node.
    public func outgoing(from node: String) -> [DirectedEdge] {
        edges.indices.compactMap { i in
            if edges[i].a == node { return DirectedEdge(index: i, forward: true) }
            if edges[i].b == node { return DirectedEdge(index: i, forward: false) }
            return nil
        }
    }

    public func from(_ e: DirectedEdge) -> String { e.forward ? edges[e.index].a : edges[e.index].b }
    public func to(_ e: DirectedEdge) -> String { e.forward ? edges[e.index].b : edges[e.index].a }
    public func name(_ e: DirectedEdge) -> String { edges[e.index].name }
    public func length(_ e: DirectedEdge) -> Double { edges[e.index].road.totalLength }

    /// The road as driven in this direction, with town speed zones at its ends.
    public func road(_ e: DirectedEdge) -> Road {
        let base = edges[e.index].road
        var r = e.forward ? base : base.reversed()
        r.speedZones = []
        if node(from(e))?.isTown == true { r.speedZones.append(SpeedZone(start: 0, end: townZoneLength, limit: townSpeedLimit, name: node(from(e))!.name)) }
        if node(to(e))?.isTown == true {
            r.speedZones.append(SpeedZone(start: r.totalLength - townZoneLength, end: r.totalLength + 1_000,
                                          limit: townSpeedLimit, name: node(to(e))!.name))
        }
        // Police watch the town speed limits from inside each town.
        if node(from(e))?.isTown == true { r.policeSpots.append(townZoneLength * 0.5) }
        if node(to(e))?.isTown == true { r.policeSpots.append(r.totalLength - townZoneLength * 0.5) }
        r.policeSpots.sort()
        return r
    }

    /// Compass direction (radians, counter-clockwise from east) of a directed edge as it leaves its start.
    func bearing(_ e: DirectedEdge) -> Double {
        guard let f = node(from(e)), let t = node(to(e)) else { return 0 }
        return atan2(t.y - f.y, t.x - f.x)
    }

    /// Where you can go after driving `edge` into its end node. No U-turns, except at dead ends.
    public func choices(after edge: DirectedEdge) -> [JunctionChoice] {
        let node = to(edge)
        let reverse = DirectedEdge(index: edge.index, forward: !edge.forward)
        var options = outgoing(from: node).filter { $0 != reverse }
        if options.isEmpty { options = [reverse] }
        let incoming = bearing(edge)
        return options.map { out in
            var delta = (bearing(out) - incoming) * 180 / .pi
            while delta > 180 { delta -= 360 }
            while delta <= -180 { delta += 360 }
            let turn: Turn
            if out == reverse { turn = .uTurn } else if abs(delta) < 35 { turn = .straight } else { turn = delta > 0 ? .left : .right }
            return JunctionChoice(edge: out, turn: turn, angle: delta, roadName: name(out),
                                  toward: self.node(to(out))?.name ?? "")
        }
    }

    /// Shortest route (directed edges, in order) from the end of `edge` to `destination`, obeying no-U-turn rules.
    /// Empty if `edge` already ends at the destination.
    public func route(after edge: DirectedEdge, to destination: String) -> [DirectedEdge]? {
        if to(edge) == destination { return [] }
        var best: [DirectedEdge: Double] = [edge: 0]
        var previous: [DirectedEdge: DirectedEdge] = [:]
        var open: Set<DirectedEdge> = [edge]
        while let current = open.min(by: { best[$0]! < best[$1]! }) {
            open.remove(current)
            if to(current) == destination && current != edge {
                var path = [current]
                var step = current
                while let p = previous[step], p != edge { path.insert(p, at: 0); step = p }
                return path
            }
            for choice in choices(after: current) {
                let cost = best[current]! + length(choice.edge)
                if cost < best[choice.edge] ?? .infinity {
                    best[choice.edge] = cost
                    previous[choice.edge] = current
                    open.insert(choice.edge)
                }
            }
        }
        return nil
    }

    /// Shortest route that starts by leaving `origin` (any road out) and ends at `destination`.
    public func route(from origin: String, to destination: String) -> [DirectedEdge]? {
        var bestRoute: [DirectedEdge]?
        var bestLength = Double.infinity
        for first in outgoing(from: origin) {
            guard let rest = route(after: first, to: destination) else { continue }
            let r = [first] + rest
            let len = r.reduce(0) { $0 + length($1) }
            if len < bestLength { bestLength = len; bestRoute = r }
        }
        return bestRoute
    }

    public func length(of route: [DirectedEdge]) -> Double { route.reduce(0) { $0 + length($1) } }
}

public struct DirectedEdge: Codable, Hashable, Sendable {
    public var index: Int
    public var forward: Bool
}

public enum Turn: String, Equatable, Sendable { case left, right, straight, uTurn }

public struct JunctionChoice: Equatable, Sendable {
    public var edge: DirectedEdge
    public var turn: Turn
    public var angle: Double
    public var roadName: String
    public var toward: String
}

/// A stretch with its own speed limit (a town).
public struct SpeedZone: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var limit: Double
    public var name: String
}

// MARK: - Road helpers

public extension Road {
    /// The same road driven the other way.
    func reversed() -> Road {
        let segs = segments.reversed().map { seg -> RoadSegment in
            if case let .curve(direction, radius) = seg.kind {
                return RoadSegment(.curve(direction: direction == .left ? .right : .left, radius: radius), length: seg.length)
            }
            return seg
        }
        var r = Road(segments: Array(segs), loops: loops, speedLimit: speedLimit,
                     truckStops: truckStops.map { totalLength - $0 })
        r.speedZones = speedZones.map { SpeedZone(start: totalLength - $0.end, end: totalLength - $0.start, limit: $0.limit, name: $0.name) }
        r.policeSpots = policeSpots.map { totalLength - $0 }.sorted()
        r.leftLaneSameDirection = leftLaneSameDirection
        return r
    }

    /// Speed limit at a position (towns are slower).
    func speedLimit(at position: Double) -> Double {
        speedZones.first { position >= $0.start && position <= $0.end }?.limit ?? speedLimit
    }

    func speedZone(at position: Double) -> SpeedZone? {
        speedZones.first { position >= $0.start && position <= $0.end }
    }

    /// Builds a road of the given style and exact length, with straight ends for junctions and towns.
    static func generate(length: Double, style: RoadStyle, seed: UInt64) -> Road {
        var rng = SeededRandom(seed: seed)
        let endStraight = 700.0
        var segs: [RoadSegment] = [.straight(endStraight)]
        var used = endStraight
        let budget = length - endStraight
        var direction: Side = Bool.random(using: &rng) ? .left : .right
        func r(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng).rounded() }
        while true {
            let (straight, radius, curveLength): (Double, Double, Double)
            switch style {
            case .interstate: (straight, radius, curveLength) = (r(900...2_000), r(900...1_600), r(300...600))
            case .country: (straight, radius, curveLength) = (r(300...900), r(280...800), r(200...450))
            case .mountain: (straight, radius, curveLength) = (r(150...400), r(140...380), r(150...320))
            }
            if used + straight + curveLength + 200 > budget { break }
            segs.append(.straight(straight))
            segs.append(RoadSegment(.curve(direction: direction, radius: radius), length: curveLength))
            used += straight + curveLength
            // Mostly alternate, sometimes two the same way.
            if Double.random(in: 0...1, using: &rng) < 0.75 { direction = direction == .left ? .right : .left }
        }
        segs.append(.straight(length - used))
        var road = Road(segments: segs, loops: false, speedLimit: style.speedLimit)
        road.leftLaneSameDirection = style == .interstate
        // A truck stop on longer non-mountain roads, in the middle of a straight near the halfway point.
        if style != .mountain && length >= 5_000 {
            var best: Double?
            var start = 0.0
            for seg in segs {
                if case .straight = seg.kind, seg.length >= 400 {
                    let mid = start + seg.length / 2
                    if mid > 1_500 && mid < length - 1_500,
                       best == nil || abs(mid - length / 2) < abs(best! - length / 2) { best = mid }
                }
                start += seg.length
            }
            if let best { road.truckStops = [best] }
        }
        // A police spot on interstates and country roads, somewhere along the open road.
        if style != .mountain {
            road.policeSpots = [(length * Double.random(in: 0.3...0.7, using: &rng)).rounded()]
        }
        return road
    }
}

// MARK: - The map

public extension WorldMap {
    static let standard: WorldMap = {
        let nodes = [
            MapNode(id: "millbrook", name: "Millbrook", x: 0, y: 0, isTown: true,
                    exports: ["Furniture", "Canned goods"]),
            MapNode(id: "millbrook_junction", name: "Millbrook Junction", x: 4, y: 0, isTown: false, exports: []),
            MapNode(id: "cedar_falls", name: "Cedar Falls", x: 4, y: 8, isTown: true, exports: ["Lumber", "Furniture"]),
            MapNode(id: "central_junction", name: "Central Junction", x: 13, y: 0, isTown: false, exports: []),
            MapNode(id: "ridgeport", name: "Ridgeport", x: 13, y: 7, isTown: true,
                    exports: ["Electronics", "Glassware", "Canned goods"]),
            MapNode(id: "ironton", name: "Ironton", x: 13, y: -6, isTown: true, exports: ["Steel beams", "Gravel"]),
            MapNode(id: "bayview", name: "Bayview", x: 19, y: 1, isTown: true,
                    exports: ["Fresh produce", "Frozen food", "Medical supplies"]),
        ]
        func edge(_ name: String, _ a: String, _ b: String, _ style: RoadStyle, _ km: Double, _ seed: UInt64) -> MapEdge {
            MapEdge(name: name, a: a, b: b, style: style, road: Road.generate(length: km * 1_000, style: style, seed: seed))
        }
        let edges = [
            edge("Route 1", "millbrook", "millbrook_junction", .country, 4, 11),
            edge("Highway 9", "millbrook_junction", "cedar_falls", .mountain, 8, 12),
            edge("Interstate 40", "millbrook_junction", "central_junction", .interstate, 9, 13),
            edge("Highway 12", "central_junction", "ridgeport", .country, 7, 14),
            edge("Ironton Road", "central_junction", "ironton", .mountain, 6, 15),
            edge("Interstate 40", "central_junction", "bayview", .interstate, 6.5, 16),
            edge("Lakeshore Road", "cedar_falls", "ridgeport", .country, 9, 17),
            edge("Coast Highway", "ridgeport", "bayview", .country, 8, 18),
        ]
        return WorldMap(nodes: nodes, edges: edges)
    }()
}

// MARK: - Navigation

/// A GPS instruction for the next junction.
public struct NavInstruction: Equatable, Sendable {
    public var distance: Double
    public var turn: Turn
    public var roadName: String
    public var toward: String
}

/// Follows the truck around the map: which road it's on, the planned route, and what happens at junctions.
public final class Navigator {
    public let map: WorldMap
    /// Destination town id, or nil for free roaming.
    public let destination: String?
    public private(set) var edge: DirectedEdge
    /// Roads still to drive after the current one.
    public private(set) var route: [DirectedEdge]
    public private(set) var road: Road
    /// The last town the truck was in or left from.
    public private(set) var lastTown: String

    public init?(map: WorldMap, origin: String, destination: String?) {
        self.map = map
        self.destination = destination
        let start: DirectedEdge
        if let destination {
            guard let r = map.route(from: origin, to: destination), let first = r.first else { return nil }
            start = first
            route = Array(r.dropFirst())
        } else {
            guard let first = map.outgoing(from: origin).first else { return nil }
            start = first
            route = []
        }
        edge = start
        road = map.road(start)
        lastTown = origin
    }

    /// Puts the navigator back where a saved drive left off.
    func restore(edge: DirectedEdge, route: [DirectedEdge], lastTown: String) {
        self.edge = edge
        self.route = route
        self.road = map.road(edge)
        self.lastTown = lastTown
    }

    /// True on the last road before the destination.
    public var onFinalRoad: Bool { destination != nil && route.isEmpty && map.to(edge) == destination }

    /// Metres left along the planned route.
    public func remaining(at position: Double) -> Double? {
        guard destination != nil else { return nil }
        return (road.totalLength - position) + map.length(of: route)
    }

    /// The next junction instruction (nil on the final road).
    public func nextInstruction(at position: Double) -> NavInstruction? {
        guard !onFinalRoad else { return nil }
        let options = map.choices(after: edge)
        let planned = route.first ?? options.first(where: { $0.turn == .straight })?.edge ?? options.first?.edge
        guard let choice = options.first(where: { $0.edge == planned }) else { return nil }
        return NavInstruction(distance: road.totalLength - position, turn: choice.turn,
                              roadName: choice.roadName, toward: choice.toward)
    }

    public var junctionChoices: [JunctionChoice] { map.choices(after: edge) }

    /// Takes the junction at the end of the current road, using the turn signal. Returns the choice taken and
    /// whether it was the planned route.
    @discardableResult
    public func takeJunction(signal: SignalState) -> (choice: JunctionChoice, onRoute: Bool) {
        let options = map.choices(after: edge)
        let planned = route.first
        let pick: JunctionChoice
        switch signal {
        case .on(.left):
            pick = options.filter { $0.turn == .left }.max { $0.angle < $1.angle }
                ?? options.first { $0.turn == .straight } ?? options.first { $0.edge == planned } ?? options[0]
        case .on(.right):
            pick = options.filter { $0.turn == .right }.min { $0.angle < $1.angle }
                ?? options.first { $0.turn == .straight } ?? options.first { $0.edge == planned } ?? options[0]
        case .off:
            pick = options.first { $0.turn == .straight } ?? options.first { $0.edge == planned }
                ?? (options.count == 1 ? options[0] : options[0])
        }
        if map.node(map.to(edge))?.isTown == true { lastTown = map.to(edge) }
        let onRoute = destination == nil || pick.edge == planned
        edge = pick.edge
        road = map.road(edge)
        if let destination {
            if onRoute { route.removeFirst() } else { route = map.route(after: edge, to: destination) ?? [] }
        }
        return (pick, onRoute)
    }
}
