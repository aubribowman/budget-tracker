import Foundation

/// Everything you own minus everything you owe.
struct NetWorth {
    var saved: Double       // savings goals
    var invested: Double    // investment accounts
    var owed: Double        // cards, personal loans and student loans
    var total: Double { saved + invested - owed }
}

// MARK: - Investment math

extension Engine {
    /// Paycheck savings linked to this account and marked paid since its last snapshot.
    /// Counted as cash until the next import, which already includes it.
    func contributedSince(_ a: InvestAccount) -> Double {
        savedSince(goalId: a.id, asOf: a.asOf, asOfAt: a.asOfAt)
    }

    /// The account's value today: its holdings at the snapshot plus contributions since.
    func accountValue(_ a: InvestAccount) -> Double { a.holdingsValue + contributedSince(a) }

    /// All investment accounts together.
    func investTotal() -> Double { s.accounts.reduce(0) { $0 + accountValue($1) } }

    /// Planned into this account on this month's paychecks.
    func plannedInto(_ a: InvestAccount) -> Double { plannedPerMonth(goalId: a.id) }

    /// Savings goals + investments − debts and student loans, all as of today.
    func netWorth() -> NetWorth {
        let saved = s.goals.reduce(0) { $0 + goalStatus($1).saved }
        let owed = s.debts.reduce(0) { $0 + curBal($1) } + loanBalances().values.reduce(0, +)
        return NetWorth(saved: saved, invested: investTotal(), owed: owed)
    }

    /// The last saved point from before today, for "since <date>" on Home.
    func lastValuePoint(before day: String = DU.iso(Date())) -> ValuePoint? {
        s.investHistory.last { $0.date < day }
    }
}
