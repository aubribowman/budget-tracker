import SwiftUI

/// Everything the monthly review needs for one month.
struct MonthReview {
    struct Cat: Identifiable { let id: String; let name: String; let budget: Double; let spent: Double
        var diff: Double { budget - spent } }
    var income = 0.0, out = 0.0, planned = 0.0
    var byType: [String: Double] = [:], plannedByType: [String: Double] = [:]
    var cats: [Cat] = []
    var billsPaid = 0, billsTotal = 0
    var unpaid: [Line] = []
    var debtPaid = 0.0, saved = 0.0
    var biggest: [Buy] = []
    var buyCount = 0
    var spent: Double { cats.reduce(0) { $0 + $1.spent } }
    var kept: Double { income - out }

    init(_ e: Engine, _ key: String) {
        var catMap: [String: (String, Double, Double)] = [:]
        var buys: [Buy] = []
        for c in e.checksIn(key) {
            let t = e.totals(key, c.n)
            income += t.income; out += t.actual; planned += t.budget
            for (k, v) in t.byType { byType[k, default: 0] += v }
            for (k, v) in t.budgetByType { plannedByType[k, default: 0] += v }
            for l in e.lines(key, c.n) where !l.skip {
                if l.type == "expense" {
                    var x = catMap[l.id] ?? (l.name, 0, 0)
                    x.1 += l.env; x.2 += l.spent
                    catMap[l.id] = x
                    buys += l.buys
                } else {
                    billsTotal += 1
                    if l.paid || l.aside { billsPaid += 1 } else { unpaid.append(l) }
                    if l.paid && l.type == "debt" { debtPaid += l.amount }
                    if l.paid && l.type == "savings" { saved += l.amount }
                }
            }
        }
        cats = catMap.map { Cat(id: $0.key, name: $0.value.0, budget: $0.value.1, spent: $0.value.2) }.sorted { $0.diff < $1.diff }
        buyCount = buys.filter { $0.amt > 0 }.count
        biggest = Array(buys.filter { $0.amt > 0 }.sorted { $0.amt > $1.amt }.prefix(3))
    }
}

enum Review {
    static let key = "reviewedMonths"
    /// The month to nudge about on Home: last month, early in this month, if not reviewed yet.
    static func pending(_ store: Store, reviewed: String) -> String? {
        let last = DU.addMonths(DU.ym(Date()), -1)
        guard last >= store.state.settings.startMonth, DU.day(Date()) <= 15, !Fold.has(reviewed, last), !store.isEmpty else { return nil }
        return last
    }
}

struct MonthlyReviewView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Review.key) private var reviewed = ""
    let month: String

    var body: some View {
        let e = store.engine
        let r = MonthReview(e, month)
        let prev = MonthReview(e, DU.addMonths(month, -1))
        let hasPrev = DU.addMonths(month, -1) >= store.state.settings.startMonth && prev.income > 0
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. The bottom line
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(money(r.income)) came in, \(money(r.out)) went out").font(.subheadline).foregroundStyle(.secondary)
                        Text(r.kept >= 0 ? "You kept \(money(r.kept))" : "You went over by \(money(-r.kept))")
                            .font(.system(size: 30, weight: .heavy)).foregroundStyle(r.kept >= 0 ? Theme.good : Theme.over)
                            .minimumScaleFactor(0.6)
                        Text(r.out <= r.planned + 0.5 ? "Spent \(money(r.planned - r.out)) less than planned."
                                                      : "Spent \(money(r.out - r.planned)) more than planned.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card()

                    // 2. Plan vs what happened
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Plan vs. what happened").font(.headline)
                        ForEach(TypeInfo.order, id: \.self) { k in
                            // For spending, compare what was actually spent, so it matches the category list below.
                            let a = k == "expense" ? r.spent : (r.byType[k] ?? 0), p = r.plannedByType[k] ?? 0
                            if a > 0 || p > 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(TypeInfo.of(k).label)
                                        Spacer()
                                        Text("\(money(a)) of \(money(p))").monospacedDigit()
                                            .foregroundStyle(a > p + 0.5 ? Theme.over : .secondary)
                                    }
                                    .font(.subheadline)
                                    ProgressBar(value: p > 0 ? a / p : 0, color: a > p + 0.5 ? Theme.over : TypeInfo.of(k).color, height: 6)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card()

                    // 3. Spending categories
                    if !r.cats.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Spending").font(.headline)
                                Spacer()
                                Text("\(r.buyCount) purchases").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(r.cats) { c in
                                HStack {
                                    Text(c.name).font(.subheadline)
                                    Spacer()
                                    Text(c.diff < -0.005 ? "Over \(money(-c.diff))" : "\(money(c.diff)) under")
                                        .font(.subheadline).monospacedDigit()
                                        .foregroundStyle(c.diff < -0.005 ? Theme.over : Theme.good)
                                }
                            }
                            if !r.biggest.isEmpty {
                                Divider()
                                Text("Biggest purchases").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(r.biggest) { b in
                                    HStack {
                                        Text(b.note.isEmpty ? "Purchase" : b.note).font(.subheadline).lineLimit(1)
                                        Spacer()
                                        Text(money(b.amt)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).card()
                    }

                    // 4. Bills
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Bills").font(.headline)
                            Spacer()
                            Text("\(r.billsPaid) of \(r.billsTotal) handled").font(.subheadline).foregroundStyle(.secondary)
                        }
                        if r.unpaid.isEmpty {
                            Label("Everything was paid or set aside.", systemImage: "checkmark.circle.fill")
                                .font(.subheadline).foregroundStyle(Theme.good)
                        } else {
                            Text("Not marked paid:").font(.caption).foregroundStyle(.secondary)
                            ForEach(r.unpaid, id: \.uid) { l in
                                HStack {
                                    Text(l.name).font(.subheadline)
                                    Spacer()
                                    Text(money(l.amount)).font(.subheadline).monospacedDigit().foregroundStyle(Theme.over)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card()

                    // 5. Progress
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Progress").font(.headline)
                        row("Paid toward debt", money(r.debtPaid))
                        row("Moved to savings", money(r.saved))
                        if r.income > 0 {
                            row("Savings rate", "\(Int((r.saved / r.income * 100).rounded()))% of take-home")
                        }
                        let totalDebt = store.state.debts.reduce(0) { $0 + e.curBal($1) }
                        if totalDebt > 0 { row("Debt left today", money(totalDebt)) }
                        ForEach(store.state.goals) { g in
                            let st = e.goalStatus(g)
                            row(g.name, "\(money0(st.saved)) of \(money0(g.target))")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card()

                    // 6. Compared with the month before
                    if hasPrev {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Compared with \(DU.monthLabel(DU.addMonths(month, -1)))").font(.headline)
                            compare("Spending", r.spent, prev.spent)
                            compare("Total going out", r.out, prev.out)
                            compare("Saved", r.saved, prev.saved, higherIsGood: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).card()
                    }

                    let done = Fold.has(reviewed, month)
                    Button {
                        if !done { reviewed = Fold.toggled(reviewed, month) }
                        dismiss()
                    } label: {
                        Label(done ? "Reviewed" : "Mark as reviewed", systemImage: done ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .readableWidth()
            }
            .background(Theme.bg)
            .navigationTitle("\(DU.monthLabel(month)) review")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).monospacedDigit().foregroundStyle(.secondary) }.font(.subheadline)
    }

    func compare(_ label: String, _ now: Double, _ before: Double, higherIsGood: Bool = false) -> some View {
        let d = now - before
        let good = higherIsGood ? d >= 0 : d <= 0
        return HStack {
            Text(label)
            Spacer()
            Text(money(now)).monospacedDigit()
            Text(abs(d) < 0.5 ? "same" : "\(d > 0 ? "▲" : "▼") \(money0(abs(d)))")
                .monospacedDigit().foregroundStyle(abs(d) < 0.5 ? .secondary : good ? Theme.good : Theme.over)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .font(.subheadline)
    }
}
