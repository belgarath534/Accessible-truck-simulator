import Foundation

// MARK: - Depots

public extension CareerState {
    static let depotPrice = 20_000
    /// Fuel at your own depot, dollars per litre (the home yard and town yards cost `yardFuelPrice`).
    static let depotFuelPrice = 1.5
    /// Jobs leaving a depot town pay this much more.
    static let depotPayBonus = 0.10

    func hasDepot(in town: String) -> Bool { depots.contains(town) }

    /// Yard fuel price in the town you're in: cheap at your depots.
    var fuelPriceHere: Double { hasDepot(in: currentTown) ? CareerState.depotFuelPrice : CareerState.yardFuelPrice }

    /// Buys a depot in a town (not Millbrook: your home yard is already there).
    @discardableResult
    mutating func buyDepot(in town: String) -> PurchaseResult {
        guard town != CareerState.homeTown, WorldMap.standard.node(town)?.isTown == true else { return .alreadyOwned }
        if hasDepot(in: town) { return .alreadyOwned }
        guard money >= CareerState.depotPrice else { return .notEnoughMoney(short: CareerState.depotPrice - money) }
        money -= CareerState.depotPrice
        depots.append(town)
        return .bought
    }
}

// MARK: - Bank loans

public extension CareerState {
    /// Interest added when you borrow.
    static let loanInterest = 0.10
    /// Share of each delivery's pay that goes to the bank until the loan is paid.
    static let loanRepaymentShare = 0.15

    /// The biggest loan the bank offers at your reputation.
    var loanLimit: Int {
        switch reputationLevel {
        case .rookie: return 5_000
        case .reliable: return 15_000
        default: return 30_000
        }
    }

    /// Loan amounts on offer.
    var loanOptions: [Int] { [5_000, 15_000, 30_000].filter { $0 <= loanLimit } }

    /// Borrows money: you owe it plus interest. One loan at a time.
    @discardableResult
    mutating func takeLoan(_ amount: Int) -> Bool {
        guard loanOwed == 0, loanOptions.contains(amount) else { return false }
        money += amount
        loanOwed = Int((Double(amount) * (1 + CareerState.loanInterest)).rounded())
        return true
    }

    /// Pays off as much of the loan as you can, or all of it.
    @discardableResult
    mutating func repayLoan() -> Int {
        let paid = min(loanOwed, max(0, money))
        money -= paid
        loanOwed -= paid
        return paid
    }

    /// The bank's share of a delivery, added to its payout (nil without a loan).
    func loanRepaymentLine(for payout: Payout) -> Payout.Line? {
        guard loanOwed > 0, payout.total > 0 else { return nil }
        let amount = min(loanOwed, Int((Double(payout.total) * CareerState.loanRepaymentShare).rounded()))
        return amount > 0 ? Payout.Line(label: "Loan repayment", amount: -amount) : nil
    }
}
