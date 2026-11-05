import SwiftUI

/// Plan a tax refund, bonus or gift: split it across debts, loans and goals and see what it changes.
struct WindfallView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    enum Kind: String { case debt, loan, goal, keep }
    struct Dest: Identifiable {
        let id: String; let kind: Kind; let name: String; let detail: String
        let cap: Double   // most it can take (balance owed or goal left); .infinity for keep
        let apr: Double
    }

    @State private var amountText = ""
    @State private var split: [String: String] = [:]   // destination id → amount text
    @State private var confirming = false
    @State private var done = false

    var amount: Double { Double(amountText) ?? 0 }

    var dests: [Dest] {
        let e = store.engine
        var out: [Dest] = []
        for d in store.state.debts {
            let b = e.curBal(d)
            if b > 0.005 { out.append(Dest(id: "d:" + d.id, kind: .debt, name: d.name, detail: "\(money(b)) at \(String(format: "%.1f", d.apr))%", cap: b, apr: d.apr)) }
        }
        let lb = e.loanBalances()
        for l in store.state.loans {
            let b = lb[l.id] ?? l.balance
            if b > 0.005 { out.append(Dest(id: "l:" + l.id, kind: .loan, name: l.name, detail: "\(money(b)) at \(String(format: "%.1f", l.apr))%", cap: b, apr: l.apr)) }
        }
        out.sort { $0.apr > $1.apr }
        for g in store.state.goals {
            let st = e.goalStatus(g)
            if st.left > 0.005 { out.append(Dest(id: "g:" + g.id, kind: .goal, name: g.name, detail: "\(money(st.left)) to go", cap: st.left, apr: 0)) }
        }
        out.append(Dest(id: "keep", kind: .keep, name: "Keep for yourself", detail: "Spend it or leave it in checking", cap: .infinity, apr: 0))
        return out
    }

    func value(_ id: String) -> Double { Double(split[id] ?? "") ?? 0 }
    var assigned: Double { dests.reduce(0) { $0 + value($1.id) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$").foregroundStyle(.secondary)
                        TextField("Amount (tax refund, bonus…)", text: $amountText).decimalPad()
                            .font(.title2.weight(.semibold))
                    }
                    Button("Suggest a split") { suggest() }.disabled(amount <= 0)
                } footer: {
                    Text("The suggestion keeps 10% for you, fills an emergency fund next, then pays the highest interest rates first. Change any amount below.")
                }

                Section {
                    ForEach(dests) { d in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Image(systemName: icon(d.kind)).foregroundStyle(color(d.kind)).font(.caption)
                                    Text(d.name)
                                }
                                Text(d.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField("0", text: Binding(get: { split[d.id] ?? "" }, set: { split[d.id] = $0 }))
                                .decimalPad().multilineTextAlignment(.trailing).frame(maxWidth: 100)
                                .foregroundStyle(value(d.id) > d.cap + 0.005 ? Theme.over : .primary)
                        }
                    }
                } header: { Text("Where it goes") } footer: {
                    let left = amount - assigned
                    Text(amount <= 0 ? "" : abs(left) < 0.005 ? "All \(money(amount)) is planned."
                         : left > 0 ? "\(money(left)) not planned yet." : "That's \(money(-left)) more than you have.")
                        .foregroundStyle(left < -0.005 ? Theme.over : .secondary)
                }

                if assigned > 0.005 { impactSection }

                Section {
                    Button { confirming = true } label: {
                        Text("Apply to my balances").frame(maxWidth: .infinity).fontWeight(.semibold)
                    }
                    .disabled(!canApply)
                } footer: {
                    Text("Lowers your debt and loan balances and adds to your goals as of today. Do this after the money has actually moved.")
                }
            }
            .navigationTitle("Windfall planner")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .keyboardDoneButton()
            .confirmationDialog("Apply \(money(assigned - value("keep"))) to your balances?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Apply") { apply() }
            }
            .alert("Done", isPresented: $done) { Button("OK") { dismiss() } } message: {
                Text("Your balances and goals are updated.")
            }
        }
    }

    var canApply: Bool {
        assigned - value("keep") > 0.005 && assigned <= amount + 0.005
            && !dests.contains { value($0.id) > $0.cap + 0.005 }
    }

    // MARK: What it changes

    var impactSection: some View {
        let e = store.engine
        // Same math as the Payoff tab, including the roll-over checkbox. The money goes in this
        // month, and a debt it pays off keeps its payment in the plan for the next debt.
        var lump: [String: Double] = [:]
        for d in store.state.debts { lump[d.id] = value("d:" + d.id) }
        for l in store.state.loans { lump[l.id] = value("l:" + l.id) }
        let roll = e.loanBalances().values.contains { $0 > 0.005 } && store.state.settings.rollLoans
        let before = e.simulateAll(extra: store.state.extra, strategy: store.state.strategy, roll: roll)
        let after = e.simulateAll(extra: store.state.extra, strategy: store.state.strategy, roll: roll, lump: lump)
        let now = DU.ym(Date())
        let debtMoney = store.state.debts.reduce(0) { $0 + value("d:" + $1.id) }
        let loanMoney = store.state.loans.reduce(0) { $0 + value("l:" + $1.id) }
        let hasDebts = store.state.debts.contains { e.curBal($0) > 0.005 }
        func sooner(_ a: Int, _ b: Int) -> String? { a > b ? "\(a - b) months sooner" : nil }
        return Section("What it changes") {
            if debtMoney + loanMoney > 0 && !before.stuck && !after.stuck {
                if hasDebts && before.loanMonths > 0 {
                    impact("Cards & personal loans paid off", after.debtMonths == 0 ? "Now" : DU.monthLabel(after.debtsDone(now)),
                           sooner(before.debtMonths, after.debtMonths))
                }
                impact("Completely debt-free", after.months == 0 ? "Now" : DU.monthLabel(after.finish(now)),
                       sooner(before.months, after.months))
                impact("Interest saved", money0(max(0, before.interest - after.interest)), nil)
            }
            ForEach(store.state.goals) { g in
                let a = value("g:" + g.id)
                if a > 0 {
                    let st = e.goalStatus(g)
                    let newSaved = st.saved + a
                    impact(g.name, "\(money0(newSaved)) of \(money0(g.target))",
                           newSaved >= g.target - 0.005 ? "Goal reached" : "\(Int((min(1, newSaved / max(1, g.target)) * 100).rounded()))% there")
                }
            }
        }
    }

    func impact(_ label: String, _ value: String, _ note: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).fontWeight(.semibold).monospacedDigit()
                if let note { Text(note).font(.caption).foregroundStyle(Theme.good) }
            }
        }
    }

    // MARK: Suggestion and apply

    func suggest() {
        var left = r2(amount)
        var plan: [String: Double] = [:]
        let ds = dests
        func give(_ id: String, _ want: Double) {
            let a = r2(min(left, want)); guard a > 0.004 else { return }
            plan[id, default: 0] += a; left = r2(left - a)
        }
        give("keep", amount * 0.10)
        // An emergency fund first, up to 40% of the money.
        if let em = ds.first(where: { $0.kind == .goal && $0.name.lowercased().contains("emergency") }) {
            give(em.id, min(em.cap, amount * 0.40))
        }
        // Then high-interest debt and loans, highest rate first.
        for d in ds where (d.kind == .debt || d.kind == .loan) && d.apr >= 8 { give(d.id, d.cap - (plan[d.id] ?? 0)) }
        // Then other goals, then any remaining debt.
        for d in ds where d.kind == .goal { give(d.id, d.cap - (plan[d.id] ?? 0)) }
        for d in ds where d.kind == .debt || d.kind == .loan { give(d.id, d.cap - (plan[d.id] ?? 0)) }
        give("keep", left)
        split = plan.mapValues { String(format: "%.2f", $0) }
    }

    func apply() {
        var debts: [String: Double] = [:], loans: [String: Double] = [:], goals: [String: Double] = [:]
        for d in dests {
            let a = value(d.id); guard a > 0 else { continue }
            let raw = String(d.id.dropFirst(2))
            switch d.kind {
            case .debt: debts[raw] = a
            case .loan: loans[raw] = a
            case .goal: goals[raw] = a
            case .keep: break
            }
        }
        store.applyWindfall(debts: debts, loans: loans, goals: goals)
        done = true
    }

    func icon(_ k: Kind) -> String {
        switch k { case .debt: "creditcard"; case .loan: "graduationcap"; case .goal: "target"; case .keep: "hand.thumbsup" }
    }
    func color(_ k: Kind) -> Color {
        switch k { case .debt: TypeInfo.of("debt").color; case .loan: Theme.midnight; case .goal: TypeInfo.of("savings").color; case .keep: Theme.moss }
    }
}
