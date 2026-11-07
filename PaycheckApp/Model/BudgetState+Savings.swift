import Foundation

/// Spending money you saved in a goal, like a babysitter fund.
///
/// Using savings adds three linked things:
/// 1. income on the paycheck, "From <goal>" (an `IncomeItem` with `goalId`)
/// 2. the spending it paid for, already marked paid (a `OneTime` with `useId` pointing at the income)
/// 3. a lower goal balance
///
/// The income and the spending cancel out, so the paycheck's left-to-spend doesn't change.
/// Changing the amount of either one changes the other and the goal, and deleting either
/// one removes both and puts the money back on the goal.
extension BudgetState {
    /// Records spending `amount` from a goal on a paycheck. Returns the new income item's id,
    /// or nil if the goal doesn't exist or the amount isn't positive.
    @discardableResult
    mutating func useSavings(goalId: String, amount: Double, for name: String, type: String,
                             key: String, n: Int) -> String? {
        let a = r2(amount)
        guard a > 0.004, let gi = goals.firstIndex(where: { $0.id == goalId }) else { return nil }
        goals[gi].balance = r2(goals[gi].balance - a)

        var income = IncomeItem()
        income.name = "From \(goals[gi].name)"
        income.amount = a
        income.goalId = goalId

        var spend = OneTime()
        spend.name = name
        spend.type = type
        spend.amount = a
        spend.paid = true
        spend.paidAt = DU.stamp()
        spend.useId = income.id

        var m = months[key] ?? [:]
        var c = m[String(n)] ?? Cell()
        c.addIncome.append(income)
        c.extras.append(spend)
        m[String(n)] = c
        months[key] = m
        return income.id
    }

    /// Removes a use of savings: the income, its spending, and puts the money back on the goal.
    /// `id` can be either the income item's id or the spending's id.
    mutating func removeSavingsUse(key: String, n: Int, id: String) {
        guard var c = months[key]?[String(n)], let incomeId = savingsUseId(in: c, id: id) else { return }
        if let inc = c.addIncome.first(where: { $0.id == incomeId }),
           let gid = inc.goalId, let gi = goals.firstIndex(where: { $0.id == gid }) {
            goals[gi].balance = r2(goals[gi].balance + inc.amount)
        }
        c.addIncome.removeAll { $0.id == incomeId }
        c.extras.removeAll { $0.useId == incomeId }
        months[key]?[String(n)] = c
    }

    /// Changes how much a use of savings was for, keeping the income, the spending and the
    /// goal in step. `id` can be either the income item's id or the spending's id.
    mutating func setSavingsUseAmount(key: String, n: Int, id: String, to amount: Double) {
        guard var c = months[key]?[String(n)], let incomeId = savingsUseId(in: c, id: id),
              let ii = c.addIncome.firstIndex(where: { $0.id == incomeId }) else { return }
        let a = r2(max(0, amount))
        let delta = a - c.addIncome[ii].amount
        if let gid = c.addIncome[ii].goalId, let gi = goals.firstIndex(where: { $0.id == gid }) {
            goals[gi].balance = r2(goals[gi].balance - delta)
        }
        c.addIncome[ii].amount = a
        for xi in c.extras.indices where c.extras[xi].useId == incomeId { c.extras[xi].amount = a }
        months[key]?[String(n)] = c
    }

    /// The income item id behind a use of savings, given its own id or its spending's id.
    /// nil if `id` isn't part of a use of savings.
    func savingsUseId(in c: Cell, id: String) -> String? {
        if let inc = c.addIncome.first(where: { $0.id == id }), inc.goalId != nil { return inc.id }
        if let x = c.extras.first(where: { $0.id == id }), let u = x.useId,
           c.addIncome.contains(where: { $0.id == u }) { return u }
        return nil
    }
}
