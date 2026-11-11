import Foundation

/// What the player does for a note. Each has its own sound, so you can tell them apart by ear.
public enum Move: String, CaseIterable, Codable, Sendable {
    case tap, left, right, up

    public var name: String {
        switch self {
        case .tap: return "Tap"
        case .left: return "Swipe left"
        case .right: return "Swipe right"
        case .up: return "Swipe up"
        }
    }

    /// How it sounds, for the "Learn the sounds" screen.
    public var soundDescription: String {
        switch self {
        case .tap: return "a wooden knock in the middle"
        case .left: return "a low beep on the left"
        case .right: return "a high beep on the right"
        case .up: return "a rising whistle"
        }
    }
}

public enum Difficulty: String, CaseIterable, Codable, Sendable {
    case easy, normal, hard
    public var name: String { rawValue.capitalized }
}

/// A small, stable random number generator (the same song always gets the same chart).
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// FNV-1a: a hash that doesn't change between launches, unlike `hashValue`.
    public static func stableHash(_ text: String) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01B3 }
        return h
    }
}
