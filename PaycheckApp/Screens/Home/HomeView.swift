import SwiftUI
import Charts

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
                    #if os(macOS)
                    // Mac windows don't show the big iPhone-style title, so put the greeting on the page.
                    Text(greeting)
                        .font(.display(.largeTitle, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    #endif
                    PageTitle(greeting)
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
                                    .font(.ui(.headline))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button { windfall = true } label: {
                            Label("Got extra money? Plan it", systemImage: "sparkles")
                                .font(.ui(.subheadline).weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .readableWidth()
            }
            .background(Theme.bg)
            .pageTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showSetup = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Setup")
                        .accessibilityLabel("Setup")
                }
            }
            .sheet(isPresented: $adding) { AddPurchaseSheet(envs: envs, preset: nil).macSheet() }
            .sheet(isPresented: $showSetup) { SettingsView(showsDone: true).macSheet() }
            .sheet(item: Binding(get: { reviewMonth.map { IdentifiedMonth(id: $0) } }, set: { reviewMonth = $0?.id })) { m in
                MonthlyReviewView(month: m.id).macSheet()
            }
            .sheet(isPresented: $windfall) { WindfallView().macSheet() }
            .navigationDestination(isPresented: $showGoals) { GoalsView() }
        }
    }

    var greeting: String {
        let hello: String
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: hello = "Good morning"
        case 12..<17: hello = "Good afternoon"
        default: hello = "Good evening"
        }
        let name = store.state.settings.firstName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? hello : "\(hello), \(name)"
    }
}

// MARK: - Cards

/// Money left on the current paycheck and when the next one lands.
private struct PaycheckSummary: View {
    @EnvironmentObject var store: Store
    let u: Engine.Upcoming

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DU.dayLabel(Date())).font(.ui(.subheadline)).foregroundStyle(.secondary)
            if let c = u.cur {
                let t = store.engine.totals(c.key, c.n)
                let left = t.left
                Text("Left on this paycheck").font(.ui(.caption).weight(.semibold)).foregroundStyle(.secondary)
                Text(money(left))
                    .heroNumber(left)
                    .foregroundStyle(left < 0 ? Theme.over : .primary)
                ProgressBar(value: t.actual > 0 ? (t.paid + t.aside) / t.actual : 0, color: Theme.moss)
                // The figures are what you read first, so they're darker than the words around them.
                Text("\(Text(money(t.paid + t.aside)).foregroundStyle(.primary).fontWeight(.semibold)) of \(Text(money(t.actual)).foregroundStyle(.primary).fontWeight(.semibold)) paid or set aside, from your \(DU.short(c.date)) paycheck")
                    .font(.ui(.subheadline)).foregroundStyle(.secondary)
            } else {
                Text("No paycheck yet this period").font(.ui(.headline))
            }
            if let n = u.next {
                Divider()
                ValueRow {
                    Image(systemName: "calendar").foregroundStyle(Theme.accent)
                    Text("Next payday").font(.ui(.subheadline))
                } value: {
                    Text("\(DU.short(n.date)), \(daysAway(n.date))").font(.ui(.subheadline).weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.leadCard)   // the one card Home leads with
    }

    func daysAway(_ d: Date) -> String {
        let n = DU.days(DU.today, d)
        return n <= 0 ? "today" : n == 1 ? "tomorrow" : "in \(n) days"
    }
}

/// A Home card that folds down to its header and one summary number.
/// Tapping the card opens its tab; the chevron folds it. There's no second arrow for
/// "open", since two arrows side by side read as the same control.
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
                CardHeader(title, icon: icon)
                Spacer(minLength: 8)
                if isFolded {
                    Text(summary).font(.ui(.subheadline).weight(.semibold)).monospacedDigit()
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
        .accessibilityAction(named: "Open \(title)", open)
    }
}

/// Bills still to pay from this paycheck, plus anything past due.
private struct DueCard: View {
    @EnvironmentObject var store: Store
    let u: Engine.Upcoming
    let open: () -> Void

    var body: some View {
        let total = u.toPay.reduce(0) { $0 + $1.amount }
        let summary = !u.overdue.isEmpty ? "\(u.overdue.count) past due"
            : u.toPay.isEmpty ? "All caught up" : "\(money(total)) due"
        HomeCard(id: "home.due", title: "To pay now", icon: "checklist", summary: summary,
                 summaryColor: u.overdue.isEmpty ? .secondary : Theme.bad, open: open) {
            if u.toPay.isEmpty && u.overdue.isEmpty {
                EmptyState(icon: "checkmark.seal", title: "You're all caught up", color: Theme.good)
            } else {
                if u.toPay.count == 1, let l = u.toPay.first {
                    // One bill: just show it, rather than a "1 bill due" total that repeats its amount.
                    ValueRow(spacing: Space.m) {
                        IconBadge(icon: ItemIcon.of(l, in: store.state), color: TypeInfo.of(l.type).color, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.name).lineLimit(1)
                            if let d = l.dueDate {
                                Text("Due \(DU.dayLabel(d))").font(.ui(.subheadline)).foregroundStyle(.secondary)
                            }
                        }
                    } value: {
                        Text(money(l.amount)).monospacedDigit().fontWeight(.semibold).rollingNumber(l.amount)
                    }
                } else if !u.toPay.isEmpty {
                    ValueRow {
                        Text("\(u.toPay.count) bills due")
                    } value: {
                        Text(money(total)).monospacedDigit().fontWeight(.semibold).rollingNumber(total)
                    }
                    ForEach(u.toPay.prefix(3), id: \.uid) { l in
                        ValueRow(spacing: Space.s) {
                            IconBadge(icon: ItemIcon.of(l, in: store.state), color: TypeInfo.of(l.type).color, size: 24)
                            Text(l.name).font(.ui(.subheadline)).foregroundStyle(.secondary).lineLimit(1)
                        } value: {
                            Text(money(l.amount)).font(.ui(.subheadline)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    if u.toPay.count > 3 {
                        Text("and \(u.toPay.count - 3) more").font(.ui(.caption)).foregroundStyle(.secondary)
                    }
                }
                if !u.overdue.isEmpty {
                    Label("\(u.overdue.count) past due", systemImage: "exclamationmark.circle.fill")
                        .font(.ui(.subheadline).weight(.semibold)).foregroundStyle(Theme.bad)
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
            ValueRow(alignment: .firstTextBaseline) {
                Text(money(budget - spent)).font(.display(.title2, weight: .bold)).monospacedDigit().rollingNumber(budget - spent)
                    .foregroundStyle(over ? Theme.over : .primary)
            } value: {
                Text("of \(money(budget))").font(.ui(.subheadline)).foregroundStyle(.secondary)
            }
            ProgressBar(value: budget > 0 ? spent / budget : 0,
                        color: over ? Theme.over : TypeInfo.of("expense").color, height: 6)
            SpendingTrend(current: check)
            ForEach(lines.prefix(4), id: \.uid) { l in
                let o = l.spent > l.env + 0.004
                ValueRow(spacing: Space.s) {
                    IconBadge(icon: ItemIcon.of(l, in: store.state), color: TypeInfo.of(l.type).color, size: 24)
                    Text(l.name).font(.ui(.subheadline)).foregroundStyle(.secondary).lineLimit(1)
                } value: {
                    Text(o ? "Over \(money(l.spent - l.env))" : "\(money(l.env - l.spent)) left")
                        .font(.ui(.subheadline)).monospacedDigit()
                        .foregroundStyle(o ? Theme.over : .secondary)
                }
            }
        }
    }
}

/// Small bars of what was spent on each of the last six paychecks, this one highlighted,
/// so you can see at a glance whether this paycheck is running high or low.
private struct SpendingTrend: View {
    @EnvironmentObject var store: Store
    let current: Check

    struct Bar: Identifiable { let id: String; let label: String; let spent: Double; let now: Bool }

    var body: some View {
        let bars = recent()
        // Only once there's something to compare with: at least one earlier paycheck with spending.
        if bars.count >= 2 && bars.dropLast().contains(where: { $0.spent > 0.004 }) {
            let past = bars.dropLast().map(\.spent)
            let avg = past.reduce(0, +) / Double(past.count)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack {
                    Text("Last \(bars.count) paychecks").font(.ui(.caption)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Usually \(money0(avg))").font(.ui(.caption)).foregroundStyle(.secondary).monospacedDigit()
                }
                Chart(bars) { b in
                    BarMark(x: .value("Paycheck", b.label), y: .value("Spent", b.spent), width: .ratio(0.6))
                        .cornerRadius(3)
                        .foregroundStyle(b.now ? TypeInfo.of("expense").color : Theme.track)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 44)
                .animation(.snappy, value: bars.map(\.spent))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spending on recent paychecks: usually \(money0(avg)), \(money0(bars.last?.spent ?? 0)) so far on this one.")
        }
    }

    /// This paycheck and up to five before it, oldest first.
    func recent() -> [Bar] {
        let e = store.engine
        var checks: [Check] = []
        var m = current.key
        for _ in 0 ..< 4 { checks += e.checksIn(m); m = DU.addMonths(m, -1) }
        let picked = checks.filter { $0.date <= current.date }.sorted { $0.date < $1.date }.suffix(6)
        return picked.map { c in
            let spent = e.lines(c.key, c.n).filter { $0.type == "expense" && !$0.skip }.reduce(0) { $0 + $1.spent }
            return Bar(id: "\(c.key).\(c.n)", label: DU.short(c.date), spent: spent, now: c.key == current.key && c.n == current.n)
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
            ValueRow(alignment: .firstTextBaseline) {
                Text(money(total)).font(.display(.title2, weight: .bold)).monospacedDigit().rollingNumber(total)
            } value: {
                Text("across \(debts.count) \(debts.count == 1 ? "debt" : "debts")")
                    .font(.ui(.subheadline)).foregroundStyle(.secondary)
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
                    .font(.ui(.subheadline)).foregroundStyle(.secondary)
            } else {
                ForEach(goals.prefix(3)) { g in
                    let st = store.engine.goalStatus(g)
                    VStack(alignment: .leading, spacing: 4) {
                        ValueRow {
                            Text(g.name).font(.ui(.subheadline)).lineLimit(1)
                        } value: {
                            Text("\(money0(st.saved)) of \(money0(g.target))")
                                .font(.ui(.subheadline)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        ProgressBar(value: st.progress, color: st.done ? Theme.good : TypeInfo.of("savings").color, height: 6)
                    }
                }
                if goals.count > 3 {
                    Text("and \(goals.count - 3) more").font(.ui(.caption)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Lets a month string drive `.sheet(item:)`.
private struct IdentifiedMonth: Identifiable { let id: String }

/// Early in the month: a nudge to look back at last month.
private struct ReviewPrompt: View {
    let month: String
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard").font(.ui(.title2)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your \(DU.monthName(month)) review is ready").font(.ui(.headline))
                    Text("See how the month went in a minute.").font(.ui(.subheadline)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.ui(.caption).weight(.semibold)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
    }
}
