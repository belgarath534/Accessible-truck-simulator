import Foundation
import SimCore

/// What kind of drive the player picked.
enum DriveMode: Equatable, Identifiable {
    /// One lap, no pay: for learning.
    case practice
    /// Endless loop, small pay per kilometre.
    case freeDrive
    /// A delivery from the job board.
    case job(DeliveryJob)

    var id: String {
        switch self {
        case .practice: return "practice"
        case .freeDrive: return "free"
        case let .job(job): return job.id.uuidString
        }
    }

    var goal: TripGoal {
        switch self {
        case .practice: return .practice(on: .practiceLoop)
        case .freeDrive: return .freeDrive
        case let .job(job): return job.goal
        }
    }

    var job: DeliveryJob? {
        if case let .job(job) = self { return job }
        return nil
    }
}

/// The player's saved career: money, finished jobs and the job board.
/// Saved as JSON in Application Support, so it survives closing the game and app updates.
final class CareerStore: ObservableObject {
    @Published private(set) var state: CareerState

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("career.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(CareerState.self, from: data) {
            state = saved
        } else {
            state = CareerState()
        }
    }

    var money: Int { state.money }
    var jobs: [DeliveryJob] { state.jobBoard }

    /// Pays the player for a drive and, for a delivery, swaps in a new job.
    func record(_ payout: Payout, distance: Double, completing job: DeliveryJob?) {
        state.record(payout, distance: distance)
        if let job { state.completeJob(job) }
        save()
    }

    var truck: TruckSpec { state.truck }

    func buy(_ truck: TruckSpec) -> CareerState.PurchaseResult {
        let result = state.buy(truck)
        save()
        return result
    }

    func select(_ truck: TruckSpec) {
        state.select(truck)
        save()
    }

    func refreshBoard() {
        state.refreshBoard()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
