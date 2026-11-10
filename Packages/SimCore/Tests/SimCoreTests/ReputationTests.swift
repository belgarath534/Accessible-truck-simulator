import XCTest
@testable import SimCore

final class ReputationTests: XCTestCase {
    private func summary(time: Double = 300, crashes: Int = 0, perfect: Bool = false, spilled: Bool = false) -> TripSummary {
        var s = TripStats()
        s.drivingTime = time
        s.crashes = crashes
        s.hazmatSpilled = spilled
        return TripSummary(goalName: "x", stats: s, stopError: perfect ? 0.5 : -20)
    }

    private func deliver(_ c: inout CareerState, _ job: DeliveryJob, _ sum: TripSummary) -> (Payout, [String]) {
        let payout = c.deliveryPayout(job, summary: sum)
        let news = c.completeDelivery(job, summary: sum)
        return (payout, news)
    }

    func testLevels() {
        XCTAssertEqual(ReputationLevel.level(for: 0), .rookie)
        XCTAssertEqual(ReputationLevel.level(for: 99), .rookie)
        XCTAssertEqual(ReputationLevel.level(for: 100), .reliable)
        XCTAssertEqual(ReputationLevel.level(for: 5_000), .legend)
    }

    func testGoodAndBadDeliveries() {
        let job = CareerState(seed: 1).jobBoard[0]
        XCTAssertEqual(CareerState.reputationChange(job: job, summary: summary(perfect: true)), 23)
        XCTAssertEqual(CareerState.reputationChange(job: job, summary: summary(time: job.timeLimit + 60, crashes: 2)), -1)
    }

    func testRookiesDontGetOversizeOrHazmat() {
        var c = CareerState(seed: 2)
        for _ in 0..<60 {
            c.refreshBoard()
            XCTAssertFalse(c.jobBoard.contains { $0.cargo.kind == .oversize || $0.cargo.kind == .hazmat })
        }
        XCTAssertNil(c.contractOffer, "contracts need Reliable")
        c.reputation = 300
        var sawHazmat = false
        for town in ["ridgeport", "millbrook", "ironton"] {
            c.currentTown = town
            for _ in 0..<40 { c.refreshBoard(); if c.jobBoard.contains(where: { $0.cargo.kind == .hazmat }) { sawHazmat = true } }
        }
        XCTAssertTrue(sawHazmat)
        XCTAssertNotNil(c.contractOffer)
    }

    func testReputationBonusAndLevelUpNews() {
        var c = CareerState(seed: 3)
        c.reputation = 95
        let job = c.jobBoard[0]
        let (payout, news) = deliver(&c, job, summary())
        XCTAssertFalse(payout.lines.contains { $0.label.contains("reputation bonus") }, "still a rookie when paid")
        XCTAssertEqual(c.reputationLevel, .reliable)
        XCTAssertTrue(news.contains { $0.hasPrefix("You're now Reliable") })
        let next = c.jobBoard[0]
        let (paid, _) = deliver(&c, next, summary())
        XCTAssertTrue(paid.lines.contains { $0.label == "Reliable reputation bonus" && $0.amount == Int((Double(next.pay) * 0.03).rounded()) })
    }

    func testContractFromOfferToBonus() throws {
        var c = CareerState(seed: 4)
        c.reputation = 150
        c.refreshBoard()
        let offer = try XCTUnwrap(c.contractOffer)
        c.acceptContract()
        XCTAssertEqual(c.contract?.id, offer.id)
        XCTAssertNil(c.contractOffer)
        for n in 1...offer.total {
            let job = try XCTUnwrap(c.jobBoard.first { $0.contractID == offer.id }, "job \(n) on the board")
            XCTAssertEqual(job.cargo.name, offer.cargoName)
            XCTAssertEqual(c.jobBoard.filter { $0.contractID != nil }.count, 1)
            let (payout, news) = deliver(&c, job, summary())
            if n < offer.total {
                XCTAssertFalse(payout.lines.contains { $0.label.hasPrefix("Contract bonus") })
                XCTAssertTrue(news.contains("Contract for \(offer.client): \(n) of \(offer.total) delivered."))
            } else {
                XCTAssertTrue(payout.lines.contains { $0.label == "Contract bonus from \(offer.client)" && $0.amount == offer.bonus })
                XCTAssertTrue(news.contains { $0.hasPrefix("Contract complete!") })
            }
        }
        XCTAssertNil(c.contract)
        XCTAssertNotNil(c.contractOffer, "a new offer after finishing")
    }

    func testLateDeliveryBreaksTheContract() throws {
        var c = CareerState(seed: 5)
        c.reputation = 150
        c.refreshBoard()
        c.acceptContract()
        let job = try XCTUnwrap(c.jobBoard.first { $0.contractID != nil })
        let before = c.reputation
        let (_, news) = deliver(&c, job, summary(time: job.timeLimit + 120))
        XCTAssertNil(c.contract)
        XCTAssertTrue(news.contains { $0.hasPrefix("Contract broken") })
        XCTAssertLessThan(c.reputation, before)
    }

    func testAbandoningCostsReputation() {
        var c = CareerState(seed: 6)
        c.reputation = 150
        c.refreshBoard()
        c.acceptContract()
        c.abandonContract()
        XCTAssertNil(c.contract)
        XCTAssertEqual(c.reputation, 135)
        XCTAssertFalse(c.jobBoard.contains { $0.contractID != nil })
    }

    func testHazmatSpillHurts() {
        var c = CareerState(seed: 7)
        c.reputation = 400
        let cargo = Cargo.catalog.first { $0.name == "Gasoline" }!
        let job = DeliveryJob(cargo: cargo, distance: 10_000, pay: 2_000, timeLimit: 900, origin: "ridgeport", destination: "bayview")
        let (payout, _) = deliver(&c, job, summary(crashes: 1, spilled: true))
        XCTAssertFalse(payout.lines.contains { $0.label.contains("reputation bonus") })
        XCTAssertEqual(c.reputation, 380)
    }

    func testOldSavesGetReputationForPastDeliveries() throws {
        var c = CareerState(seed: 8)
        c.jobsCompleted = 12
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]
        for k in ["reputation", "contract", "contractOffer"] { json.removeValue(forKey: k) }
        let old = try JSONDecoder().decode(CareerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.reputation, 180)
        XCTAssertEqual(old.reputationLevel, .reliable)
    }

    func testPayoutReadsTheNews() {
        var p = Payout(lines: [Payout.Line(label: "Delivery pay", amount: 100)])
        p.news = ["Reputation up 10 points, to 110."]
        XCTAssertTrue(Phrases(units: .metric).payout(p).hasSuffix("You earned $100. Reputation up 10 points, to 110."))
    }
}
