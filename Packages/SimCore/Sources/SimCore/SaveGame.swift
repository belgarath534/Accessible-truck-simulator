import Foundation

/// A drive saved part-way ("Save and Continue Later"), to pick up next time.
public struct DriveSnapshot: Codable, Equatable, Sendable {
    public var truckID: String
    public var position: Double
    public var lateralOffset: Double
    public var odometer: Double
    public var fuelLiters: Double
    public var engineTempC: Double
    public var time: Double
    public var signal: Side?
    public var stats: TripStats
    public var weather: Weather
    /// Where on the map (nil for the practice loop).
    public var edge: DirectedEdge?
    public var route: [DirectedEdge]
    public var lastTown: String?
    public var targetLane: Double
}

/// What kind of drive was saved, with the job for a delivery.
public struct SavedDrive: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case practice, freeDrive, job }

    public var kind: Kind
    public var job: DeliveryJob?
    /// The town the drive started from (for Free Drive).
    public var origin: String
    public var snapshot: DriveSnapshot
    public var savedAt: Date

    public init(kind: Kind, job: DeliveryJob?, origin: String, snapshot: DriveSnapshot, savedAt: Date = Date()) {
        self.kind = kind
        self.job = job
        self.origin = origin
        self.snapshot = snapshot
        self.savedAt = savedAt
    }
}
