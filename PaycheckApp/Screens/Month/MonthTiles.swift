import SwiftUI

/// Four tiles under the Month tab's green card, in the same style as Home and Payoff
/// (SummaryTile in HomeTiles.swift): spending against its budget, how many bills are
/// paid, what went to savings, and how much spending room is left per day (or, for a
/// past month, the biggest item). Two across, or one column at the largest text sizes.
struct MonthTiles: View {
    @EnvironmentObject var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let s = Summary(store)
        if typeSize.isAccessibilitySize {
            VStack(spacing: 14) { spending(s); bills(s); saved(s); last(s) }
        } else {
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow { spending(s); bills(s) }
                GridRow { saved(s); last(s) }
            }
        }
    }

    /// The month's numbers the tiles need, added up over its paychecks.
    struct Summary {
        var spent = 0.0, spendBudget = 0.0        // spending categories
        var billsPaid = 0, bills = 0, billsLeft = 0.0   // bills, subscriptions and debt payments
        var saved = 0.0, income = 0.0
        var biggest: (name: String, amount: Double)? = nil
        var daysLeft: Int? = nil                  // only for the current month, today included

        init(_ store: Store) {
            let e = store.engine
            let key = store.month
            var byName: [String: (String, Double)] = [:]
            for c in e.checksIn(key) {
                income += e.totals(key, c.n).income
                for l in e.lines(key, c.n) where !l.skip {
                    if l.isEnv {
                        spent += l.spent; spendBudget += l.env
                    } else if l.type != "savings" {
                        bills += 1
                        if l.paid { billsPaid += 1 } else { billsLeft += l.amount }
                    }
                    if l.type == "savings" { saved += l.amount }
                    let k = l.name.lowercased()
                    byName[k] = (l.name, (byName[k]?.1 ?? 0) + l.amount)
                }
            }
            biggest = byName.values.max { $0.1 < $1.1 }.map { (name: $0.0, amount: $0.1) }
            if key == DU.ym(Date()) {
                let cal = Calendar.current
                let days = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
                daysLeft = max(1, days - cal.component(.day, from: Date()) + 1)
            }
        }
    }

    /// Spent on spending categories so far, against what's budgeted for them.
    func spending(_ s: Summary) -> some View {
        let over = s.spent > s.spendBudget + 0.004
        return SummaryTile(title: "Spending", icon: "cart", value: money0(s.spent),
                           note: s.spendBudget <= 0 ? "No spending budget" : over ? "\(money0(s.spent - s.spendBudget)) over" : "of \(money0(s.spendBudget))",
                           noteColor: over ? Theme.over : .secondary, open: nil) {
            ProgressBar(value: s.spendBudget > 0 ? min(1, s.spent / s.spendBudget) : 0,
                        color: over ? Theme.over : TypeInfo.of("expense").color, height: 8)
        }
    }

    /// Bills, subscriptions and debt payments marked paid, and what's still to pay.
    func bills(_ s: Summary) -> some View {
        let done = s.bills > 0 && s.billsPaid == s.bills
        return SummaryTile(title: "Bills paid", icon: "checkmark.circle", value: "\(s.billsPaid) of \(s.bills)",
                           note: s.bills == 0 ? "No bills this month" : done ? "All paid" : "\(money0(s.billsLeft)) to go",
                           noteColor: done ? Theme.good : .secondary, open: nil) {
            ProgressBar(value: s.bills > 0 ? Double(s.billsPaid) / Double(s.bills) : 0,
                        color: TypeInfo.of("bill").color, height: 8)
        }
    }

    /// What went to savings, as a share of take-home.
    func saved(_ s: Summary) -> some View {
        let share = s.income > 0 ? s.saved / s.income : 0
        return SummaryTile(title: "Saved", icon: "banknote", value: money0(s.saved),
                           note: s.saved <= 0 ? "Nothing set aside yet" : "\(Int((share * 100).rounded()))% of take-home",
                           noteColor: s.saved > 0 ? Theme.good : .secondary, open: nil) {
            ProgressBar(value: min(1, share), color: Theme.moss, height: 8)
        }
    }

    /// This month: spending room left per day. Another month: the biggest item.
    @ViewBuilder func last(_ s: Summary) -> some View {
        if let days = s.daysLeft {
            let room = max(0, s.spendBudget - s.spent)
            SummaryTile(title: "Per day", icon: "calendar", value: money0(room / Double(days)),
                        note: "to spend, \(days) \(days == 1 ? "day" : "days") left", open: nil) {
                // How much of the spending budget is still unspent.
                ProgressBar(value: s.spendBudget > 0 ? room / s.spendBudget : 0, color: Theme.midnight, height: 8)
            }
        } else {
            let b = s.biggest
            SummaryTile(title: "Biggest item", icon: "arrow.up.circle", value: b.map { money0($0.amount) } ?? "—",
                        note: b?.name ?? "Nothing this month", open: nil) {
                ProgressBar(value: b.map { s.income > 0 ? min(1, $0.amount / s.income) : 0 } ?? 0,
                            color: Theme.midnight, height: 8)
            }
        }
    }
}
