import SwiftUI

/// Four tiles under the "Debt-free by" card, in the same style as Home's (SummaryTile in
/// HomeTiles.swift): what's owed, the interest still ahead, the next debt to go, and
/// credit utilization. Two across, or one column at the largest text sizes.
struct PayoffTiles: View {
    @EnvironmentObject var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize

    let debtOwed: Double                 // cards and personal loans
    let loanOwed: Double                 // student loans
    let interest: Double?                // interest ahead on this plan; nil when payments don't cover it
    let next: (name: String, when: String, paid: Double)?   // the next debt to be paid off
    let openUtilization: () -> Void

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 14) { owed; interestTile; nextTile; utilization }
        } else {
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow { owed; interestTile }
                GridRow { nextTile; utilization }
            }
        }
    }

    /// Everything owed, with a bar split between cards/personal loans and student loans.
    var owed: some View {
        let total = debtOwed + loanOwed
        let count = store.state.debts.filter { store.engine.curBal($0) > 0.005 }.count
        let note = loanOwed > 0.005 ? "\(count) debts + student loans" : "across \(count) \(count == 1 ? "debt" : "debts")"
        return SummaryTile(title: "Owed", icon: "dollarsign.circle", value: money0(total), note: note, open: nil) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if total <= 0.005 { Capsule().fill(Theme.track) }
                    if debtOwed > 0.005 {
                        RoundedRectangle(cornerRadius: 3).fill(PayoffChartCard.debtColor)
                            .frame(width: max(4, geo.size.width * debtOwed / max(total, 1) - (loanOwed > 0.005 ? 1 : 0)))
                    }
                    if loanOwed > 0.005 {
                        RoundedRectangle(cornerRadius: 3).fill(PayoffChartCard.loanColor)
                    }
                }
            }
            .frame(height: 8)
        }
    }

    /// Interest still to pay on this plan, and how much of everything you'll pay it is.
    var interestTile: some View {
        let owed = debtOwed + loanOwed
        let share = interest.map { owed + $0 > 0 ? $0 / (owed + $0) : 0 } ?? 0
        return SummaryTile(title: "Interest ahead", icon: "percent",
                           value: interest.map(money0) ?? "Growing",
                           note: interest == nil ? "Payments don’t cover it" : "\(Int((share * 100).rounded()))% of what you’ll pay",
                           noteColor: interest == nil ? Theme.over : .secondary, open: nil) {
            ProgressBar(value: interest == nil ? 1 : share, color: Theme.rosy, height: 8)
        }
    }

    /// The next debt to be paid off, when, and how far along it is.
    var nextTile: some View {
        SummaryTile(title: "Next payoff", icon: "flag.checkered",
                    value: next?.when ?? (debtOwed <= 0.005 ? "All done" : "—"),
                    note: next?.name ?? (debtOwed <= 0.005 ? "No card or loan balances" : "Add a payment plan"),
                    open: nil) {
            ProgressBar(value: next?.paid ?? (debtOwed <= 0.005 ? 1 : 0), color: Theme.moss, height: 8)
        }
    }

    /// Credit utilization across cards with a limit. Opens the full breakdown.
    var utilization: some View {
        let u = Utilization(store)
        let band = Utilization.band(u.pct)
        return SummaryTile(title: "Utilization", icon: "gauge.with.dots.needle.33percent",
                           value: u.cards.isEmpty ? "—" : "\(Int(u.pct.rounded()))%",
                           note: u.cards.isEmpty ? "Add a card limit" : "\(band.label) · \(money0(u.limit)) limit",
                           noteColor: u.cards.isEmpty ? .secondary : band.color,
                           open: u.cards.isEmpty ? nil : openUtilization) {
            ProgressBar(value: min(1, u.pct / 100), color: u.cards.isEmpty ? Theme.track : band.color, height: 8)
        }
    }
}
