import Foundation

/// Pilots speak knots, feet and nautical miles everywhere in the world, so the game does too.
public enum Units {
    public static func knots(_ metresPerSecond: Double) -> Int { Int((metresPerSecond * 1.943_84).rounded()) }
    public static func feet(_ metres: Double) -> Int { Int((metres * 3.280_84).rounded()) }
    public static func feetPerMinute(_ metresPerSecond: Double) -> Int { Int((metresPerSecond * 196.85).rounded()) }
    public static func metres(feet: Double) -> Double { feet / 3.280_84 }
    public static func metresPerSecond(knots: Double) -> Double { knots / 1.943_84 }

    /// "4.2 miles" (nautical), or "800 feet" when very close.
    public static func distance(_ metres: Double) -> String {
        let nm = metres / 1_852
        if nm < 0.3 { return "\(roundedFeet(metres)) feet" }
        if nm < 10 { return String(format: "%.1f miles", nm).replacingOccurrences(of: ".0 ", with: " ") }
        return "\(Int(nm.rounded())) miles"
    }

    /// Feet rounded to a sensible step for speaking.
    public static func roundedFeet(_ metres: Double) -> Int {
        let f = Double(feet(metres))
        let step: Double = f >= 1_000 ? 100 : f >= 200 ? 50 : 10
        return Int((f / step).rounded() * step)
    }

    /// Normalises an angle to 0..<360.
    public static func heading(_ degrees: Double) -> Double {
        let h = degrees.truncatingRemainder(dividingBy: 360)
        return h < 0 ? h + 360 : h
    }

    /// The shortest turn from one heading to another: positive = turn right.
    public static func turn(from: Double, to: Double) -> Double {
        var d = heading(to) - heading(from)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// "270" spoken as pilots say it: "two seven zero".
    public static func headingWords(_ degrees: Double) -> String {
        var h = Int(heading(degrees).rounded()) % 360
        if h == 0 { h = 360 }
        let digits = String(format: "%03d", h).map { String($0) }
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "niner"]
        return digits.map { words[Int($0)!] }.joined(separator: " ")
    }

    public static func compassPoint(_ degrees: Double) -> String {
        let names = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        return names[Int((heading(degrees) / 45).rounded()) % 8]
    }
}
