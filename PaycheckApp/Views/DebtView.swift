import SwiftUI

struct DebtView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Debt?
    @State private var extraText = ""
    @AppStorage("payoffSection") private var section = "debts"

    var body: some View {
        let e = store.engine
        let sim = e.simulate(extra: store.state.extra, strategy: store.state.strategy)
        let base = e.simulate(extra: 0, strategy: store.state.strategy)
        let now = DU.ym(Date())
        let total = store.state.debts.reduce(0) { $0 + e.curBal($1) }
        let ranked = store.state.debts.filter { e.curBal($0) > 0.005 }.sorted { (sim.payoff[$0.id] ?? 999) < (sim.payoff[$1.id] ?? 999) }
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Section", selection: $section) {
                        Text("Debts").tag("debts"); Text("Student loans").tag("loans")
                    }
                    .pickerStyle(.segmented)

                    if section == "loans" {
                        StudentLoansSection()
                    } else {
                    // Headline
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(money(total)) left across \(ranked.count) debts").font(.caption).foregroundStyle(.secondary)
                        Text(store.state.debts.isEmpty ? "Add your debts" : total <= 0.005 ? "Debt-free" : sim.stuck ? "Payments don’t cover interest" : "Debt-free by \(DU.monthLabel(DU.addMonths(now, sim.months)))")
                            .font(.system(size: 34, weight: .heavy)).minimumScaleFactor(0.6)
                        if total > 0.005 && !sim.stuck {
                            Text("\(sim.months) months, about \(money0(sim.interest)) in interest." + (base.months > sim.months ? " That’s \(base.months - sim.months) months sooner and \(money0(base.interest - sim.interest)) less than minimums only." : ""))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    // Strategy and extra
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Strategy", selection: Binding(get: { store.state.strategy }, set: { v in
                            store.update { s in
                                s.strategy = v
                                if v == "target" && s.targetDebt == nil { s.targetDebt = ranked.first?.id }
                            }
                        })) {
                            Text("Avalanche").tag("avalanche"); Text("Snowball").tag("snowball"); Text("Pick a debt").tag("target")
                        }
                        .pickerStyle(.segmented)
                        Text(store.state.strategy == "avalanche" ? "Extra goes to the highest interest rate first." :
                             store.state.strategy == "snowball" ? "Extra goes to the smallest balance first." :
                             "All extra goes to one debt until it’s paid off, then highest interest first.")
                            .font(.caption).foregroundStyle(.secondary)
                        if store.state.strategy == "target" {
                            Picker("Put the extra toward", selection: Binding(get: { store.state.targetDebt ?? "" }, set: { v in store.update { $0.targetDebt = v } })) {
                                ForEach(ranked) { d in Text(d.name).tag(d.id) }
                            }
                        }
                        HStack {
                            Text("Extra each month")
                            Spacer()
                            TextField("0.00", text: $extraText, onCommit: commitExtra)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("On top of \(money(ranked.reduce(0) { $0 + $1.min })) in minimums.").font(.caption).foregroundStyle(.secondary)
                    }
                    .card()

                    UtilizationCard()

                    ExtraLineCard()

                    // Debts
                    ForEach(store.state.debts) { d in
                        let b = e.curBal(d)
                        let o = d.original > 0 ? d.original : d.balance
                        let rank = ranked.firstIndex(where: { $0.id == d.id })
                        Button { editing = d } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(d.name).font(.headline)
                                    Spacer()
                                    if b <= 0.005 { Tag(text: "Paid off", color: Theme.good) }
                                    else if let r = rank { Tag(text: "\(DU.ordinal(r + 1)) to pay off") }
                                }
                                Text(money(b)).font(.title2.weight(.heavy)).monospacedDigit()
                                ProgressBar(value: o > 0 ? 1 - b / o : 0, color: Theme.rosy)
                                HStack {
                                    Text("APR \(String(format: "%.2f", d.apr))%")
                                    Spacer()
                                    if let m = sim.payoff[d.id], b > 0.005 { Text("Gone by \(DU.monthLabel(DU.addMonths(now, m), short: true))") }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                                if let lim = d.limit, lim > 0 {
                                    let u = b / lim * 100
                                    Text("Using \(Int(u.rounded()))% of \(money0(lim)) limit").font(.caption)
                                        .foregroundStyle(u >= 30 ? Theme.over : Theme.good)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                    Button { var d = Debt(); d.asOf = DU.iso(Date()); editing = d } label: { Label("Add a debt", systemImage: "plus") }
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .navigationTitle("Payoff")
            .sheet(item: $editing) { d in DebtEditSheet(debt: d) }
            .onAppear { extraText = String(format: "%.2f", store.state.extra) }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { commitExtra(); hideKeyboard() } } }
        }
    }

    func commitExtra() {
        if let v = Double(extraText) { store.update { $0.extra = max(0, v) } }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// Puts the extra payment on paychecks so you can tick it off against a specific debt.
struct ExtraLineCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let e = store.engine
        let on = e.extraRec != nil
        let when = e.extraRec?.when ?? store.state.extraWhen ?? "1"
        let focus = e.focusDebtId()
        VStack(alignment: .leading, spacing: 10) {
            Text("Extra payment on your paychecks").font(.headline)
            Text(on ? "Shows up as “Extra → \(e.debtName(focus))”. When you mark it paid, it’s recorded against that debt."
                    : "Add your \(money(store.state.extra)) extra as its own line so you can tick it off and see which debt it went to.")
                .font(.subheadline).foregroundStyle(.secondary)
            Picker("Which paycheck pays it", selection: Binding(get: { when }, set: { store.setExtraWhen($0) })) {
                Text("First paycheck (\(money(store.state.extra)))").tag("1")
                Text("Second paycheck (\(money(store.state.extra)))").tag("2")
                Text("Split across both").tag("each")
            }
            Button(on ? "Remove from paychecks" : "Add to paychecks") { store.setExtraLine(on: !on) }
                .buttonStyle(.borderedProminent)
                .tint(on ? .gray : Theme.accent)
                .disabled(!on && store.state.extra <= 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct DebtEditSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var debt: Debt
    @State private var balance = ""
    @State private var apr = ""
    @State private var minPay = ""
    @State private var limit = ""
    @State private var original = ""
    @State private var confirmDelete = false

    var isNew: Bool { !store.state.debts.contains { $0.id == debt.id } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $debt.name)
                Section {
                    field("Balance on latest statement", $balance)
                    field("Starting balance", $original)
                    field("APR %", $apr)
                    field("Minimum payment", $minPay)
                    field("Credit limit (cards only)", $limit)
                } footer: {
                    Text("Changing the balance resets tracking to today. Payments you mark paid after today come off it automatically.")
                }
                if !isNew {
                    Button("Delete this debt", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(isNew ? "New debt" : debt.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
            }
            .confirmationDialog("Delete \(debt.name)?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { store.deleteDebt(debt.id); dismiss() }
            }
            .onAppear {
                balance = String(format: "%.2f", debt.balance); apr = String(format: "%.2f", debt.apr)
                minPay = String(format: "%.2f", debt.min); original = String(format: "%.2f", debt.original)
                limit = debt.limit.map { String(format: "%.2f", $0) } ?? ""
            }
        }
    }

    func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack { Text(label); Spacer(); TextField("0.00", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120) }
    }

    func save() {
        var d = debt
        let nb = Double(balance) ?? d.balance
        if abs(nb - d.balance) > 0.004 || isNew { d.balance = nb; d.asOf = DU.iso(Date()) }
        d.apr = Double(apr) ?? d.apr
        d.min = Double(minPay) ?? d.min
        d.original = Double(original) ?? d.original
        if d.original <= 0 { d.original = d.balance }
        d.limit = Double(limit).flatMap { $0 > 0 ? $0 : nil }
        store.saveDebt(d)
    }
}
