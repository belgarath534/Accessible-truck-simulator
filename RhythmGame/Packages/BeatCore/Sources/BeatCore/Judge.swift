import Foundation

public enum Judgement: String, Equatable, Sendable {
    case perfect, good, wrongMove, miss

    public var spoken: String {
        switch self {
        case .perfect: return "Perfect"
        case .good: return "Good"
        case .wrongMove: return "Wrong move"
        case .miss: return "Miss"
        }
    }
    public var isHit: Bool { self == .perfect || self == .good }
}

/// Scores a song as it's played. Feed it moves with their song time, and call `update` every frame for misses.
public struct Judge: Sendable {
    /// How close to the beat counts, seconds either side.
    public static let perfectWindow = 0.06
    public static let goodWindow = 0.12
    public static let hitWindow = 0.17

    public let notes: [Note]
    public private(set) var results: [Judgement?]
    public private(set) var score = 0
    public private(set) var combo = 0
    public private(set) var bestCombo = 0
    private var nextUnjudged = 0

    public init(chart: Chart) {
        notes = chart.notes
        results = Array(repeating: nil, count: chart.notes.count)
    }

    /// Points multiplier: x1, then x2 at 10 in a row, x3 at 20, x4 at 30.
    public var multiplier: Int { 1 + min(combo / 10, 3) }

    /// A move at a song time. Returns the judgement, or nil if no note was near (no penalty).
    public mutating func input(_ move: Move, at time: Double) -> (index: Int, judgement: Judgement)? {
        var best: Int?
        for i in nextUnjudged..<notes.count where results[i] == nil {
            let dt = abs(notes[i].time - time)
            if notes[i].time - time > Judge.hitWindow { break }
            if dt <= Judge.hitWindow, best.map({ dt < abs(notes[$0].time - time) }) ?? true { best = i }
        }
        guard let i = best else { return nil }
        let dt = abs(notes[i].time - time)
        let judgement: Judgement = notes[i].move != move ? .wrongMove
            : dt <= Judge.perfectWindow ? .perfect : dt <= Judge.goodWindow ? .good : .wrongMove
        // Right move but a bit too far off counts as a miss, not a wrong move.
        let final = (notes[i].move == move && judgement == .wrongMove) ? Judgement.miss : judgement
        record(i, final)
        return (i, final)
    }

    /// Marks notes that went by without a move. Returns their indices.
    public mutating func update(time: Double) -> [Int] {
        var missed: [Int] = []
        while nextUnjudged < notes.count {
            if results[nextUnjudged] != nil { nextUnjudged += 1; continue }
            guard time - notes[nextUnjudged].time > Judge.hitWindow else { break }
            record(nextUnjudged, .miss)
            missed.append(nextUnjudged)
            nextUnjudged += 1
        }
        return missed
    }

    private mutating func record(_ i: Int, _ j: Judgement) {
        results[i] = j
        switch j {
        case .perfect: combo += 1; score += 300 * multiplier
        case .good: combo += 1; score += 100 * multiplier
        case .wrongMove, .miss: combo = 0
        }
        bestCombo = max(bestCombo, combo)
    }

    public var isFinished: Bool { !results.contains(nil) }

    public func count(_ j: Judgement) -> Int { results.filter { $0 == j }.count }

    /// 0...100: perfect counts fully, good half.
    public var accuracy: Int {
        guard !notes.isEmpty else { return 0 }
        let points = Double(count(.perfect)) + Double(count(.good)) * 0.5
        return Int((points / Double(notes.count) * 100).rounded())
    }

    public var grade: String {
        switch accuracy {
        case 95...: return "S"
        case 85..<95: return "A"
        case 70..<85: return "B"
        case 50..<70: return "C"
        default: return "D"
        }
    }

    public var spokenResults: String {
        "Score \(score). Accuracy \(accuracy) percent, grade \(grade). \(count(.perfect)) perfect, \(count(.good)) good, \(count(.miss) + count(.wrongMove)) missed. Best combo \(bestCombo)."
    }
}
