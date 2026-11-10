import XCTest
@testable import SimCore

final class BusinessTests: XCTestCase {
    private func summary(_ job: DeliveryJob) -> TripSummary {
        var s = TripStats()
        s.drivingTime = job.timeLimit / 2
        return TripSummary(goalName: "x", stats: s, stopError: -20)
    }

    func testBuyingADepot() {
        var c = CareerState(seed: 1)
        c.money = 25_000
        XCTAssertEqual(c.buyDepot(in: "millbrook"), .alreadyOwned, "home already has the yard")
        XCTAssertEqual(c.buyDepot(in: "ridgeport"), .bought)
        XCTAssertEqual(c.money, 5_000)
        XCTAssertEqual(c.buyDepot(in: "bayview"), .notEnoughMoney(short: 15_000))
        XCTAssertTrue(c.hasDepot(in: "ridgeport"))
    }

    func testDepotsMeanCheapFuelAndBetterPay() {
        var c = CareerState(seed: 2)
        c.money = 50_000
        c.buyDepot(in: "ridgeport")
        c.setFuel(0, for: .starter)
        let elsewhere = c.yardFillCost(for: .starter)
        c.move(to: "ridgeport")
        XCTAssertEqual(c.yardFillCost(for: .starter), Int((Double(elsewhere) / 2).rounded()), accuracy: 1)
        let job = c.jobBoard.first { $0.storyID == nil }!
        XCTAssertTrue(c.deliveryPayout(job, summary: summary(job)).lines.contains { $0.label == "Depot bonus" && $0.amount == Int((Double(job.pay) * 0.1).rounded()) })
    }

    func testLoansAndRepayment() {
        var c = CareerState(seed: 3)
        XCTAssertEqual(c.loanOptions, [5_000])
        c.reputation = 400
        XCTAssertEqual(c.loanOptions, [5_000, 15_000, 30_000])
        let start = c.money
        XCTAssertTrue(c.takeLoan(15_000))
        XCTAssertEqual(c.money, start + 15_000)
        XCTAssertEqual(c.loanOwed, 16_500)
        XCTAssertFalse(c.takeLoan(5_000), "one loan at a time")

        let job = c.jobBoard.first { $0.storyID == nil }!
        let payout = c.deliveryPayout(job, summary: summary(job))
        let line = payout.lines.first { $0.label == "Loan repayment" }!
        let before = payout.total - line.amount
        XCTAssertEqual(-line.amount, Int((Double(before) * 0.15).rounded()))
        let news = c.completeDelivery(job, summary: summary(job), payout: payout)
        XCTAssertEqual(c.loanOwed, 16_500 + line.amount)
        XCTAssertTrue(news.contains { $0.hasPrefix("You still owe the bank") })

        c.money = 100_000
        XCTAssertEqual(c.repayLoan(), c.loanOwed + (16_500 + line.amount) - c.loanOwed)
        XCTAssertEqual(c.loanOwed, 0)
        let after = c.deliveryPayout(job, summary: summary(job))
        XCTAssertFalse(after.lines.contains { $0.label == "Loan repayment" })
    }

    func testRepaymentNeverOverpays() {
        var c = CareerState(seed: 4)
        c.loanOwed = 50
        let job = c.jobBoard.first { $0.storyID == nil }!
        let payout = c.deliveryPayout(job, summary: summary(job))
        XCTAssertEqual(payout.lines.first { $0.label == "Loan repayment" }?.amount, -50)
        c.completeDelivery(job, summary: summary(job), payout: payout)
        XCTAssertEqual(c.loanOwed, 0)
    }

    func testOldSavesHaveNoDepotsOrLoans() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CareerState(seed: 5))) as! [String: Any]
        json.removeValue(forKey: "depots")
        json.removeValue(forKey: "loanOwed")
        let old = try JSONDecoder().decode(CareerState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.depots, [])
        XCTAssertEqual(old.loanOwed, 0)
    }
}
