import SwiftUI
import Charts

/// The Payoff tab. Two sections: Debts (cards and personal loans, strategy, extra
/// payment, chart, utilization) and Student loans (StudentLoansView.swift).
/// Payoff dates come from `Engine.simulateAll`.
struct PayoffView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Debt?
    @State private var extraText = ""
    @State private var dragExtra: Double?          // while the slider is moving
    @AppStorage("payoffSection") private var section = "debts"

    var body: some View {
        let e = store.engine
        let extra = dragExtra ?? store.state.extra
        let sim = e.simulate(extra: extra, strategy: store.state.strategy)
        let now = DU.ym(Date())
        let total = store.state.debts.reduce(0) { $0 + e.curBal($1) }
        let ranked = store.state.debts.filter { e.curBal($0) > 0.005 }.sorted { (sim.payoff[$0.id] ?? 999) < (sim.payoff[$1.id] ?? 999) }
        let loanBal = e.loanBalances()
        let loanTotal = loanBal.values.reduce(0, +)
        let hasLoans = loanTotal > 0.005
        let roll = hasLoans && store.state.settings.rollLoans
        let all = e.simulateAll(extra: extra, strategy: store.state.strategy, roll: roll)
        let alt = e.simulateAll(extra: extra, strategy: store.state.strategy, roll: !roll)   // the checkbox flipped
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
                        Text(hasLoans ? "\(money(all.total(0))) owed across \(all.count) debts, student loans included"
                                      : "\(money(total)) left across \(ranked.count) debts")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(headline(all: all, owed: total + loanTotal, both: hasLoans && !ranked.isEmpty, now: now))
                            .font(.system(size: 34, weight: .heavy)).minimumScaleFactor(0.6)
                        if total + loanTotal > 0.005 && !all.stuck {
                            let months = all.months
                            Text("\(months) months from now" + (months >= 24 ? " (\((Double(months) / 12).formatted(.number.precision(.fractionLength(1)))) years)" : "") +
                                 ", about \(money0(all.interest)) in interest along the way.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 16) { groupDates(all, debts: !ranked.isEmpty, loans: hasLoans, now: now) }
                                VStack(alignment: .leading, spacing: 4) { groupDates(all, debts: !ranked.isEmpty, loans: hasLoans, now: now) }
                            }
                            .padding(.top, 2)
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
                            Text("Extra toward debt each month")
                            Spacer()
                            TextField("0.00", text: $extraText, onCommit: commitExtra)
                                .decimalPad().multilineTextAlignment(.trailing).frame(maxWidth: 110)
                                .textFieldStyle(.roundedBorder)
                        }
                        Slider(value: Binding(get: { dragExtra ?? store.state.extra },
                                              set: { dragExtra = $0; extraText = String(format: "%.2f", $0) }),
                               in: 0 ... sliderMax, step: 25) { editing in
                            if !editing, let v = dragExtra { store.update { $0.extra = v }; dragExtra = nil }
                        }
                        .tint(Theme.rosy)
                        Text("On top of \(money(ranked.reduce(0) { $0 + $1.min })) in minimums.").font(.caption).foregroundStyle(.secondary)
                        if hasLoans {
                            Toggle("When a card or personal loan is paid off, roll its payment into student loans",
                                   isOn: Binding(get: { store.state.settings.rollLoans }, set: { v in store.update { $0.settings.rollLoans = v } }))
                                .font(.subheadline)
                                .toggleStyle(CheckboxToggle())
                        }
                        if hasLoans && alt.months != all.months {
                            // Compared with the checkbox the other way, like the web app.
                            let diff = alt.months - all.months, saved = alt.interest - all.interest
                            Text(roll ? "That gets you debt-free \(diff) \(diff == 1 ? "month" : "months") sooner and saves about \(money0(saved)) in interest."
                                      : "Turning it on would make you debt-free \(-diff) \(diff == -1 ? "month" : "months") sooner and save about \(money0(-saved)).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .card()

                    if total + loanTotal > 0.005 {
                        PayoffChartCard(sim: all, debts: !ranked.isEmpty, loans: hasLoans)
                    }

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
                .readableWidth()
            }
            .background(Theme.bg)
            .navigationTitle("Payoff")
            .sheet(item: $editing) { d in DebtEditSheet(debt: d).macSheet() }
            .onAppear { extraText = String(format: "%.2f", store.state.extra) }
            .keyboardDoneButton { commitExtra() }
        }
    }

    func commitExtra() {
        if let v = Double(extraText) { store.update { $0.extra = max(0, v) } }
    }

    /// Slider goes to $1,000, or twice your extra if that's more.
    var sliderMax: Double { max(1000, (store.state.extra * 2 / 100).rounded(.up) * 100) }

    func headline(all: PayoffSim, owed: Double, both: Bool, now: String) -> String {
        if all.count == 0 { return store.state.debts.isEmpty && store.state.loans.isEmpty ? "Add your debts" : "Debt\u{2011}free" }
        if owed <= 0.005 { return "Debt-free" }
        if all.stuck { return "Payments don’t cover interest" }
        return (both ? "Completely debt\u{2011}free by " : "Debt\u{2011}free by ") + DU.monthLabel(all.finish(now))
    }

    @ViewBuilder func groupDates(_ all: PayoffSim, debts: Bool, loans: Bool, now: String) -> some View {
        if debts {
            PayoffLegendDot(color: PayoffChartCard.debtColor, label: "Cards & personal loans", value: DU.monthLabel(all.debtsDone(now), short: true))
        }
        if loans {
            PayoffLegendDot(color: PayoffChartCard.loanColor, label: "Student loans", value: DU.monthLabel(all.loansDone(now), short: true))
        }
    }
}
