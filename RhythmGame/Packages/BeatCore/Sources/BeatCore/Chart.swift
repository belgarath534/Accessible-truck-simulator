import Foundation

/// One thing to do: hear the cue in the "listen" bar, then do the move at the same spot in the next bar.
public struct Note: Equatable, Sendable {
    /// When to do the move, seconds from the start of the song.
    public let time: Double
    /// When its cue sound plays, one bar earlier.
    public let cueTime: Double
    public let move: Move
}

/// The notes of a song. The game is call and response: a bar of cue sounds (listen),
/// then a bar where you repeat them (your turn), over and over.
public struct Chart: Equatable, Sendable {
    public let song: Song
    public let difficulty: Difficulty
    public let notes: [Note]

    public init(song: Song, difficulty: Difficulty) {
        self.song = song
        self.difficulty = difficulty
        self.notes = Chart.build(song: song, difficulty: difficulty)
    }

    /// The start of each "listen" bar, seconds.
    public var callBarStarts: [Double] {
        stride(from: Song.introBars, to: song.bars - Song.outroBars - 1, by: 2).map { Double($0) * song.barLength }
    }

    static func build(song: Song, difficulty: Difficulty) -> [Note] {
        var rng = SeededRandom(seed: SeededRandom.stableHash(song.id + difficulty.rawValue))
        var notes: [Note] = []
        let eighth = song.beatLength / 2
        let pairs = Array(stride(from: Song.introBars, to: song.bars - Song.outroBars - 1, by: 2))
        for (n, callBar) in pairs.enumerated() {
            let warmUp = n < 2
            let moves = movesAllowed(difficulty: difficulty, pair: n)
            let positions = Chart.positions(difficulty: difficulty, warmUp: warmUp, using: &rng)
            let responseStart = Double(callBar + 1) * song.barLength
            for p in positions {
                let time = responseStart + Double(p) * eighth
                notes.append(Note(time: time, cueTime: time - song.barLength, move: moves.randomElement(using: &rng)!))
            }
        }
        return notes
    }

    /// Easy starts with taps only, then adds swipes; swipe up comes last.
    static func movesAllowed(difficulty: Difficulty, pair: Int) -> [Move] {
        switch difficulty {
        case .easy: return pair < 2 ? [.tap] : pair < 5 ? [.tap, .left, .right] : Move.allCases
        case .normal: return pair < 1 ? [.tap, .left, .right] : Move.allCases
        case .hard: return Move.allCases
        }
    }

    /// Spots in the bar, in eighth notes (0...7).
    static func positions(difficulty: Difficulty, warmUp: Bool, using rng: inout SeededRandom) -> [Int] {
        switch difficulty {
        case .easy:
            let count = warmUp ? 2 : Int.random(in: 2...3, using: &rng)
            return Array([0, 2, 4, 6].shuffled(using: &rng).prefix(count)).sorted()
        case .normal:
            let count = warmUp ? 2 : Int.random(in: 3...4, using: &rng)
            return Array([0, 2, 4, 6].shuffled(using: &rng).prefix(count)).sorted()
        case .hard:
            let count = warmUp ? 3 : Int.random(in: 4...6, using: &rng)
            // Any eighth, but never two in a row more than twice, so it stays playable.
            var spots = Set([0, 2, 4, 6].shuffled(using: &rng).prefix(min(count, 4)))
            while spots.count < count { spots.insert(Int.random(in: 0...7, using: &rng)) }
            return spots.sorted()
        }
    }
}
