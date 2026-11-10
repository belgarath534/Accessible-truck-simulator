import Foundation
import SimCore

/// What kind of drive the player picked.
enum DriveMode: Equatable, Identifiable {
    /// The guided first drive: one skill at a time on the practice loop.
    case tutorial
    /// One lap, no pay: for learning.
    case practice
    /// Endless loop, small pay per kilometre.
    case freeDrive
    /// A delivery from the job board.
    case job(DeliveryJob)

    var id: String {
        switch self {
        case .tutorial: return "tutorial"
        case .practice: return "practice"
        case .freeDrive: return "free"
        case let .job(job): return job.id.uuidString
        }
    }

    var goal: TripGoal {
        switch self {
        case .tutorial: return .freeDrive // ends when the tutorial does, not at a drop-off
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
    /// Achievements earned but not yet announced. The driving screen speaks them; the menu shows an alert.
    @Published var justUnlocked: [Achievement] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("career.json")
    }()

    /// Screenshot mode: example progress that is never saved.
    private let isDemo: Bool

    init(demo: CareerState? = nil) {
        isDemo = demo != nil
        if let demo {
            state = demo
        } else if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(CareerState.self, from: data) {
            state = saved
        } else {
            state = CareerState()
        }
    }

    var money: Int { state.money }
    var jobs: [DeliveryJob] { state.jobBoard }

    /// Pays the player for a drive and, for a delivery, updates reputation and contracts and swaps in a new job.
    /// Returns news for the player (reputation, contracts).
    @discardableResult
    func record(_ payout: Payout, distance: Double, completing job: DeliveryJob?, trip: TripResult? = nil) -> [String] {
        state.record(payout, distance: distance)
        var news: [String] = []
        if let job {
            if let summary = trip?.summary {
                news = state.completeDelivery(job, summary: summary)
            } else {
                state.completeJob(job)
            }
        }
        save(trip: trip)
        if !isDemo { GameCenter.shared.submitScores(state) }
        return news
    }

    func sendTow(_ driver: Driver) -> Bool {
        let ok = state.sendTow(driver)
        save()
        return ok
    }

    func letWait(_ driver: Driver) {
        state.letWait(driver)
        save()
    }

    func buyChains() -> CareerState.PurchaseResult {
        let result = state.buyChains()
        save()
        return result
    }

    func acceptContract() {
        state.acceptContract()
        save()
    }

    func abandonContract() {
        state.abandonContract()
        save()
    }

    /// Earns an achievement that isn't about the career itself (like finishing the tutorial).
    func unlock(_ achievement: Achievement) {
        guard !isDemo, state.unlock(achievement) else { return }
        justUnlocked.append(achievement)
        GameCenter.shared.report([achievement])
        save()
    }

    /// Hands over the achievements waiting to be announced.
    func takeUnlocked() -> [Achievement] {
        defer { justUnlocked = [] }
        return justUnlocked
    }

    /// After signing in to Game Center: send everything earned so far.
    func syncGameCenter() {
        guard !isDemo else { return }
        GameCenter.shared.sync(state)
    }

    var truck: TruckSpec { state.truck }
    /// The selected truck without upgrades (used as the key for per-truck saves).
    var baseTruck: TruckSpec { TruckSpec.withID(state.selectedTruck) }
    var fuelLiters: Double { state.fuelLiters(for: baseTruck) }

    func saveFuel(_ liters: Double) {
        state.setFuel(liters, for: baseTruck)
        save()
    }

    func fillAtYard(_ truck: TruckSpec) -> Bool {
        let full = state.fillAtYard(truck)
        save()
        return full
    }

    /// Charges a drive's costs without pay (abandoned job, restarted drive, practice).
    func charge(_ payout: Payout, trip: TripResult? = nil) {
        state.record(payout, distance: 0)
        save(trip: trip)
    }

    func buy(_ truck: TruckSpec) -> CareerState.PurchaseResult {
        let result = state.buy(truck)
        save()
        return result
    }

    /// A truck from the catalog with this player's upgrades applied.
    func upgraded(_ truck: TruckSpec) -> TruckSpec { truck.upgraded(state.upgradeLevels(for: truck)) }

    func buyUpgrade(_ kind: UpgradeKind, for truck: TruckSpec) -> CareerState.UpgradeResult {
        let result = state.buyUpgrade(kind, for: truck)
        save()
        return result
    }

    func buyHorn(_ horn: Horn) -> CareerState.PurchaseResult {
        let result = state.buyHorn(horn)
        save()
        return result
    }

    func selectHorn(_ horn: Horn) {
        state.selectHorn(horn)
        save()
    }

    func setNickname(_ name: String, for truck: TruckSpec) {
        state.setNickname(name, for: truck)
        save()
    }

    func setCompanyName(_ name: String) {
        state.setCompanyName(name)
        save()
    }

    func select(_ truck: TruckSpec) {
        state.select(truck)
        save()
    }

    // MARK: Company

    /// Counts the drivers' work up to now and returns what to tell the player (nil if nothing new).
    func collectDriverEarnings() -> String? {
        let reports = state.updateDrivers()
        save()
        return Phrases.driverReports(reports)
    }

    func hire(_ candidate: Driver) -> CareerState.HireResult {
        let result = state.hire(candidate)
        save()
        return result
    }

    func assign(_ driver: Driver, to truck: TruckSpec?) {
        state.assign(driver.id, to: truck)
        save()
    }

    func fire(_ driver: Driver) {
        state.fire(driver.id)
        save()
    }

    func giveRaise(_ driver: Driver) -> CareerState.RaiseResult {
        let result = state.giveRaise(driver.id)
        save()
        return result
    }

    func declineRaise(_ driver: Driver) {
        state.declineRaise(driver.id)
        save()
    }

    /// Counts the drivers' work up to now (so raise requests show up), without a spoken report.
    func refreshDrivers() {
        guard !isDemo else { return }
        _ = state.updateDrivers()
        save()
    }

    func driver(using truck: TruckSpec) -> Driver? { state.drivers.first { $0.truckID == truck.id } }

    func move(to town: String) {
        state.move(to: town)
        save()
    }

    // MARK: Ratings

    /// Set after a great delivery: the main menu asks for a rating (Apple decides whether it really shows).
    @Published var askForRating = false

    // MARK: Save and continue later

    var savedDrive: SavedDrive? { state.savedDrive }
    /// Set when the player chooses Continue; the next drive picks it up.
    private(set) var pendingResume: SavedDrive?

    func saveDrive(_ drive: SavedDrive) {
        state.savedDrive = drive
        save()
    }

    func clearSavedDrive() {
        state.savedDrive = nil
        save()
    }

    /// Continue the saved drive: drive the same truck, and hand the save to the next drive screen.
    func prepareResume() -> DriveMode? {
        guard let saved = state.savedDrive else { return nil }
        let truck = TruckSpec.withID(saved.snapshot.truckID)
        if state.owns(truck) && state.selectedTruck != truck.id { state.select(truck) }
        pendingResume = saved
        switch saved.kind {
        case .practice: return .practice
        case .freeDrive: return .freeDrive
        case .job: return saved.job.map { .job($0) }
        }
    }

    /// The drive screen takes the save (once); it's removed from the career so it can't be continued twice.
    func takePendingResume() -> SavedDrive? {
        defer { pendingResume = nil }
        guard let saved = pendingResume else { return nil }
        clearSavedDrive()
        return saved
    }

    func refreshBoard() {
        state.refreshBoard()
        save()
    }

    /// Checks for new achievements, then saves.
    private func save(trip: TripResult? = nil) {
        guard !isDemo else { return }
        let new = state.checkAchievements(after: trip)
        if !new.isEmpty {
            justUnlocked += new
            GameCenter.shared.report(new)
        }
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
