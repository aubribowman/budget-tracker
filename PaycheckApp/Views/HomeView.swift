import SwiftUI

/// First screen: a quick look at this paycheck, what's due, spending and debt.
struct HomeView: View {
    @EnvironmentObject var store: Store
    @Binding var tab: AppTab
    @State private var adding = false
    @State private var showSetup = false
    @State private var showGoals = false
    @State private var reviewMonth: String?
    @State private var windfall = false
    @AppStorage(Review.key) private var reviewed = ""

    var envs: [Recurring] { store.state.recurring.filter { $0.type == "expense" } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.isEmpty {
                        EmptyStart()
                    } else {
                        let e = store.engine
                        let u = e.upcoming()
                        PaycheckSummary(u: u)
                        if let m = Review.pending(store, reviewed: reviewed) {
                            ReviewPrompt(month: m) { reviewMonth = m }
                        }
                        DueCard(u: u) { tab = .paychecks }
                        if let c = u.cur, !envs.isEmpty {
                            SpendingCard(check: c) { tab = .purchases }
                        }
                        if !store.state.debts.isEmpty {
                            DebtSummary { tab = .debt }
                        }
                        GoalsSummary { showGoals = true }
                        if !envs.isEmpty {
                            Button { adding = true } label: {
                                Label("Log a purchase", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button { windfall = true } label: {
                            Label("Got extra money? Plan it", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSetup = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Setup")
                }
            }
            .sheet(isPresented: $adding) { AddPurchaseSheet(envs: envs, preset: nil) }
            .sheet(isPresented: $showSetup) { SettingsView(showsDone: true) }
            .sheet(item: Binding(get: { reviewMonth.map { IdentifiedMonth(id: $0) } }, set: { reviewMonth = $0?.id })) { m in
                MonthlyReviewView(month: m.id)
            }
            .sheet(isPresented: $windfall) { WindfallView() }
            .navigationDestination(isPresented: $showGoals) { GoalsView() }
        }
    }

    var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - Cards

/// Money left on the current paycheck and when the next one lands.
private struct PaycheckSummary: View {
    @EnvironmentObject var store: Store
    let u: Engine.Upcoming

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DU.dayLabel(Date())).font(.subheadline).foregroundStyle(.secondary)
            if let c = u.cur {
                let t = store.engine.totals(c.key, c.n)
                let left = t.left
                Text("Left on this paycheck").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(money(left))
                    .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(left < 0 ? Theme.over : .primary)
                ProgressBar(value: t.actual > 0 ? (t.paid + t.aside) / t.actual : 0, color: Theme.moss)
                Text("\(money(t.paid + t.aside)) of \(money(t.actual)) paid or set aside, from your \(DU.short(c.date)) paycheck")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No paycheck yet this period").font(.headline)
            }
            if let n = u.next {
                Divider()
                HStack {
                    Image(systemName: "calendar").foregroundStyle(Theme.accent)
                    Text("Next payday").font(.subheadline)
                    Spacer()
                    Text("\(DU.short(n.date)), \(daysAway(n.date))").font(.subheadline.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    func daysAway(_ d: Date) -> String {
        let n = DU.days(DU.today, d)
        return n <= 0 ? "today" : n == 1 ? "tomorrow" : "in \(n) days"
    }
}

/// A Home card that folds down to its header and one summary number.
/// Tapping the card opens its tab; the chevron folds it.
private struct HomeCard<Content: View>: View {
    @AppStorage(Fold.key) private var folded = ""
    let id: String
    let title: String
    let icon: String
    let summary: String
    var summaryColor: Color = .secondary
    let open: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        let isFolded = Fold.has(folded, id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon).font(.headline).foregroundStyle(Theme.accent).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                if isFolded {
                    Text(summary).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(summaryColor).lineLimit(1).minimumScaleFactor(0.8)
                }
                Button { withAnimation(.snappy) { folded = Fold.toggled(folded, id) } } label: { FoldChevron(folded: isFolded) }
                    .buttonStyle(.plain)
            }
            if !isFolded { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}

/// Bills still to pay from this paycheck, plus anything past due.
private struct DueCard: View {
    let u: Engine.Upcoming
    let open: () -> Void

    var body: some View {
        let total = u.toPay.reduce(0) { $0 + $1.amount }
        let summary = !u.overdue.isEmpty ? "\(u.overdue.count) past due"
            : u.toPay.isEmpty ? "All caught up" : "\(money(total)) due"
        HomeCard(id: "home.due", title: "To pay now", icon: "checklist", summary: summary,
                 summaryColor: u.overdue.isEmpty ? .secondary : Theme.bad, open: open) {
            if u.toPay.isEmpty && u.overdue.isEmpty {
                Text("You're all caught up.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                if !u.toPay.isEmpty {
                    HStack {
                        Text("\(u.toPay.count) \(u.toPay.count == 1 ? "bill" : "bills") due")
                        Spacer()
                        Text(money(total)).monospacedDigit().fontWeight(.semibold)
                    }
                    ForEach(u.toPay.prefix(3), id: \.uid) { l in
                        HStack {
                            Text(l.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Text(money(l.amount)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    if u.toPay.count > 3 {
                        Text("and \(u.toPay.count - 3) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !u.overdue.isEmpty {
                    Label("\(u.overdue.count) past due", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.bad)
                }
            }
        }
    }
}

/// Spending money left in each category on the current paycheck.
private struct SpendingCard: View {
    @EnvironmentObject var store: Store
    let check: Check
    let open: () -> Void

    var body: some View {
        let lines = store.engine.lines(check.key, check.n).filter { $0.type == "expense" && !$0.skip }
        let budget = lines.reduce(0) { $0 + $1.env }
        let spent = lines.reduce(0) { $0 + $1.spent }
        let over = spent > budget + 0.004
        HomeCard(id: "home.spending", title: "Spending left", icon: "cart",
                 summary: over ? "Over \(money(spent - budget))" : "\(money(budget - spent)) left",
                 summaryColor: over ? Theme.over : .secondary, open: open) {
            HStack(alignment: .firstTextBaseline) {
                Text(money(budget - spent)).font(.title2.bold()).monospacedDigit()
                    .foregroundStyle(over ? Theme.over : .primary)
                Spacer()
                Text("of \(money(budget))").font(.subheadline).foregroundStyle(.secondary)
            }
            ProgressBar(value: budget > 0 ? spent / budget : 0,
                        color: over ? Theme.over : TypeInfo.of("expense").color, height: 6)
            ForEach(lines.prefix(4), id: \.uid) { l in
                let o = l.spent > l.env + 0.004
                HStack {
                    Text(l.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(o ? "Over \(money(l.spent - l.env))" : "\(money(l.env - l.spent)) left")
                        .font(.subheadline).monospacedDigit()
                        .foregroundStyle(o ? Theme.over : .secondary)
                }
            }
        }
    }
}

/// Total debt still owed.
private struct DebtSummary: View {
    @EnvironmentObject var store: Store
    let open: () -> Void

    var body: some View {
        let debts = store.state.debts
        let total = debts.reduce(0) { $0 + store.engine.curBal($1) }
        HomeCard(id: "home.debt", title: "Debt", icon: "creditcard", summary: money0(total), open: open) {
            HStack(alignment: .firstTextBaseline) {
                Text(money(total)).font(.title2.bold()).monospacedDigit()
                Spacer()
                Text("across \(debts.count) \(debts.count == 1 ? "debt" : "debts")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Progress on the first few savings goals.
private struct GoalsSummary: View {
    @EnvironmentObject var store: Store
    let open: () -> Void

    var body: some View {
        let goals = store.state.goals
        let saved = goals.reduce(0) { $0 + store.engine.goalStatus($1).saved }
        let target = goals.reduce(0) { $0 + $1.target }
        HomeCard(id: "home.goals", title: "Savings goals", icon: "target",
                 summary: goals.isEmpty ? "None yet" : "\(money0(saved)) of \(money0(target))", open: open) {
            if goals.isEmpty {
                Text("Set a goal, like an emergency fund, and watch it grow each payday.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(goals.prefix(3)) { g in
                    let st = store.engine.goalStatus(g)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(g.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text("\(money0(st.saved)) of \(money0(g.target))")
                                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                        ProgressBar(value: st.progress, color: st.done ? Theme.good : TypeInfo.of("savings").color, height: 6)
                    }
                }
                if goals.count > 3 {
                    Text("and \(goals.count - 3) more").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct IdentifiedMonth: Identifiable { let id: String }

/// Early in the month: a nudge to look back at last month.
private struct ReviewPrompt: View {
    let month: String
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your \(DU.monthName(month)) review is ready").font(.headline)
                    Text("See how the month went in a minute.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
    }
}
