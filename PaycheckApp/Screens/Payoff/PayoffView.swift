import SwiftUI
import Charts

/// The Payoff tab. Two sections: Debts (cards and personal loans, strategy, extra
/// payment, chart, utilization) and Student loans (StudentLoansView.swift).
/// Payoff dates come from `Engine.simulateAll`.
struct PayoffView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject var store: Store
    @State private var editing: Debt?
    @State private var extraText = ""
    @State private var dragExtra: Double?          // while the slider is moving
    @State private var showUtilization = false
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
                    PageTitle("Payoff")
                    Picker("Section", selection: $section) {
                        Text("Debts").tag("debts"); Text("Student loans").tag("loans")
                    }
                    .pickerStyle(.segmented)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // segments don't wrap, so cap them to fit the screen

                    if section == "loans" {
                        StudentLoansSection()
                    } else {
                    // Headline
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hasLoans ? "\(money(all.total(0))) owed across \(all.count) debts, student loans included"
                                      : "\(money(total)) left across \(ranked.count) debts")
                            .font(.ui(.caption)).foregroundStyle(.secondary)
                        // A small label over a big date ("Debt-free by" / "Jan 2031"), with a ring
                        // for how much of the cards and personal loans is paid off.
                        let h = headline(all: all, owed: total + loanTotal, both: hasLoans && !ranked.isEmpty, now: now)
                        // The ring sits beside the date normally, and under it at the largest text sizes.
                        let row = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.m))
                            : AnyLayout(HStackLayout(alignment: .center, spacing: Space.l))
                        row {
                            VStack(alignment: .leading, spacing: 0) {
                                if let label = h.label {
                                    Text(label).font(.display(.subheadline, weight: .semibold)).foregroundStyle(Theme.accent)
                                }
                                Text(h.big).font(.display(.largeTitle, weight: .heavy))
                                    .minimumScaleFactor(0.6).lineLimit(2)
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: h.big)
                            }
                            Spacer(minLength: 0)
                            if let p = paidOffShare {
                                ProgressRing(value: p, color: PayoffChartCard.debtColor)
                                    .frame(width: 72, height: 72)
                                    .accessibilityLabel("Cards and personal loans \(Int((p * 100).rounded())) percent paid off")
                            }
                        }
                        // How long and how much interest, then each group's own payoff month.
                        if total + loanTotal > 0.005 && !all.stuck {
                            let months = all.months
                            Text("In \(months) months" + (months >= 24 ? " (\((Double(months) / 12).formatted(.number.precision(.fractionLength(1)))) years)" : "") +
                                 " · about \(money0(all.interest)) in interest")
                                .font(.ui(.subheadline)).foregroundStyle(.secondary)
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 16) { groupDates(all, debts: !ranked.isEmpty, loans: hasLoans, now: now) }
                                VStack(alignment: .leading, spacing: 4) { groupDates(all, debts: !ranked.isEmpty, loans: hasLoans, now: now) }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(tint: Theme.leadCard)   // the card this screen leads with, like Home's paycheck card

                    // Owed, interest ahead, next payoff and utilization as tiles (PayoffTiles.swift).
                    if total + loanTotal > 0.005 || !store.state.debts.isEmpty {
                        let first = ranked.first
                        PayoffTiles(debtOwed: total, loanOwed: loanTotal,
                                    interest: all.stuck ? nil : all.interest,
                                    next: first.flatMap { d in
                                        sim.payoff[d.id].map { m in
                                            let o = d.original > 0 ? d.original : d.balance
                                            return (d.name, DU.monthLabel(DU.addMonths(now, m), short: true),
                                                    o > 0 ? max(0, min(1, 1 - e.curBal(d) / o)) : 0)
                                        }
                                    },
                                    openUtilization: { showUtilization = true })
                    }

                    // Strategy and extra
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader("Your plan", icon: "slider.horizontal.3")
                        Picker("Strategy", selection: Binding(get: { store.state.strategy }, set: { v in
                            store.update { s in
                                s.strategy = v
                                if v == "target" && s.targetDebt == nil { s.targetDebt = ranked.first?.id }
                            }
                        })) {
                            Text("Avalanche").tag("avalanche"); Text("Snowball").tag("snowball"); Text("Pick a debt").tag("target")
                        }
                        .pickerStyle(.segmented)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // segments don't wrap, so cap them to fit the screen
                        Text(store.state.strategy == "avalanche" ? "Extra goes to the highest interest rate first." :
                             store.state.strategy == "snowball" ? "Extra goes to the smallest balance first." :
                             "All extra goes to one debt until it’s paid off, then highest interest first.")
                            .font(.ui(.caption)).foregroundStyle(.secondary)
                        if store.state.strategy == "target" {
                            Picker("Put the extra toward", selection: Binding(get: { store.state.targetDebt ?? "" }, set: { v in store.update { $0.targetDebt = v } })) {
                                ForEach(ranked) { d in Text(d.name).tag(d.id) }
                            }
                        }
                        ValueRow {
                            Text("Extra toward debt each month")
                        } value: {
                            HStack(spacing: 2) {
                                Text("$").foregroundStyle(.secondary)
                                TextField("0.00", text: $extraText, onCommit: commitExtra)
                                    .decimalPad().multilineTextAlignment(.trailing)
                                    .font(.display(.title3, weight: .bold)).monospacedDigit()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.bg, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                            .frame(maxWidth: 130)
                        }
                        Slider(value: Binding(get: { dragExtra ?? store.state.extra },
                                              set: { dragExtra = $0; extraText = String(format: "%.2f", $0) }),
                               in: 0 ... sliderMax, step: 25) { editing in
                            if !editing, let v = dragExtra { store.update { $0.extra = v }; dragExtra = nil }
                        }
                        .tint(Theme.rosy)
                        Text("On top of \(money(ranked.reduce(0) { $0 + $1.min })) in minimums.").font(.ui(.caption)).foregroundStyle(.secondary)
                        if hasLoans {
                            Toggle("When a card or personal loan is paid off, roll its payment into student loans",
                                   isOn: Binding(get: { store.state.settings.rollLoans }, set: { v in store.update { $0.settings.rollLoans = v } }))
                                .font(.ui(.subheadline))
                                .toggleStyle(CheckboxToggle())
                        }
                        if hasLoans && alt.months != all.months {
                            // Compared with the checkbox the other way, like the web app.
                            let diff = alt.months - all.months, saved = alt.interest - all.interest
                            // Good news reads as good news: green with a sparkle when it's helping.
                            Label(roll ? "Debt-free \(diff) \(diff == 1 ? "month" : "months") sooner, saving about \(money0(saved)) in interest."
                                       : "Turning it on would make you debt-free \(-diff) \(diff == -1 ? "month" : "months") sooner and save about \(money0(-saved)).",
                                  systemImage: roll ? "sparkles" : "lightbulb")
                                .font(.ui(.caption).weight(.semibold))
                                .foregroundStyle(roll ? Theme.good : .secondary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background((roll ? Theme.good : Color.secondary).opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                        }
                    }
                    .card()

                    if total + loanTotal > 0.005 {
                        PayoffChartCard(sim: all, debts: !ranked.isEmpty, loans: hasLoans)
                    }

                    ExtraLineCard()

                    // Debts, in the order they'll be paid off; paid-off ones last.
                    if !store.state.debts.isEmpty {
                        Text("Your debts").font(.display(.title3, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    ForEach(store.state.debts.sorted { (ranked.firstIndex(of: $0) ?? 999) < (ranked.firstIndex(of: $1) ?? 999) }) { d in
                        let b = e.curBal(d)
                        let o = d.original > 0 ? d.original : d.balance
                        let paid = o > 0 ? max(0, min(1, 1 - b / o)) : 0
                        let rank = ranked.firstIndex(where: { $0.id == d.id })
                        Button { editing = d } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: Space.m) {
                                    IconBadge(icon: ItemIcon.guess(d.name, type: "debt"), color: TypeInfo.of("debt").color, size: 40)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(d.name).font(.ui(.headline)).lineLimit(1)
                                        // Where today's balance comes from, so a payment that did or didn't
                                        // count is easy to spot.
                                        Text(balanceSource(d)).font(.ui(.caption)).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 4)
                                    if b <= 0.005 { Tag(text: "Paid off", color: Theme.good) }
                                    else if let r = rank { Tag(text: "\(DU.ordinal(r + 1)) to pay off") }
                                }
                                ValueRow(alignment: .firstTextBaseline) {
                                    Text(money(b)).font(.display(.title2, weight: .bold)).monospacedDigit().rollingNumber(b)
                                } value: {
                                    if o > 0 && paid > 0.004 {
                                        Text("\(Int((paid * 100).rounded()))% paid off").font(.ui(.caption).weight(.semibold))
                                            .foregroundStyle(Theme.good)
                                    }
                                }
                                ProgressBar(value: paid, color: Theme.rosy, height: 8)
                                // The details as small chips that wrap to a second line when needed.
                                FlowLayout(spacing: 6, lineSpacing: 6) {
                                    PayoffChip(icon: "percent", text: "\(String(format: "%.2f", d.apr))% APR")
                                    if let m = sim.payoff[d.id], b > 0.005 {
                                        PayoffChip(icon: "flag.checkered", text: "Gone by \(DU.monthLabel(DU.addMonths(now, m), short: true))")
                                    }
                                    if d.min > 0, b > 0.005 { PayoffChip(icon: "arrow.down.circle", text: "\(money0(d.min)) min") }
                                    // Cards with a statement day set (in the debt editor).
                                    if b > 0.005, let close = d.nextStatement() {
                                        PayoffChip(icon: "calendar", text: "Statement \(DU.statementLabel(close))")
                                    }
                                    if let lim = d.limit, lim > 0 {
                                        let u = b / lim * 100
                                        PayoffChip(icon: "gauge.with.dots.needle.33percent", text: "Using \(Int(u.rounded()))% of \(money0(lim))",
                                                   color: u >= 30 ? Theme.over : Theme.good)
                                    }
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
            .pageTitle("Payoff")
            .sheet(item: $editing) { d in DebtEditSheet(debt: d).macSheet() }
            .navigationDestination(isPresented: $showUtilization) { UtilizationView() }
            .onAppear { extraText = String(format: "%.2f", store.state.extra) }
            .keyboardDoneButton { commitExtra() }
        }
    }

    /// Saves the typed extra payment (when the field is submitted or the keyboard closes).
    func commitExtra() {
        if let v = Double(extraText) { store.update { $0.extra = max(0, v) } }
    }

    /// "$5,891.73 on Nov 5 · $122.00 paid since": the balance you entered and the payments
    /// marked paid after it, which together make today's balance.
    func balanceSource(_ d: Debt) -> String {
        let paid = store.engine.paidSince(debtId: d.id, asOf: d.asOf, asOfAt: d.asOfAt)
        let day = DU.parseISO(d.asOf).map { DU.short($0) } ?? d.asOf
        let base = "\(money(d.balance)) on \(day)"
        return paid > 0.004 ? "\(base) · \(money(paid)) paid since" : "\(base) · no payments marked since"
    }

    /// Slider goes to $1,000, or twice your extra if that's more.
    var sliderMax: Double { max(1000, (store.state.extra * 2 / 100).rounded(.up) * 100) }

    /// The headline as a small label and a big line, like "Debt-free by" over "Jan 2031".
    func headline(all: PayoffSim, owed: Double, both: Bool, now: String) -> (label: String?, big: String) {
        if all.count == 0 { return (nil, store.state.debts.isEmpty && store.state.loans.isEmpty ? "Add your debts" : "Debt\u{2011}free") }
        if owed <= 0.005 { return (nil, "Debt\u{2011}free") }
        if all.stuck { return (nil, "Payments don’t cover interest") }
        return (both ? "Completely debt\u{2011}free by" : "Debt\u{2011}free by", DU.monthLabel(all.finish(now), short: true))
    }

    /// How much of the cards and personal loans is paid off, from their starting balances.
    /// Nil when no debt has a starting balance (student loans don't keep one).
    var paidOffShare: Double? {
        let ds = store.state.debts.filter { $0.original > 0 }
        let start = ds.reduce(0) { $0 + $1.original }
        guard start > 0 else { return nil }
        let now = ds.reduce(0) { $0 + store.engine.curBal($1) }
        return max(0, min(1, 1 - now / start))
    }

    /// The payoff month for each group, as legend dots matching the chart's colors.
    @ViewBuilder func groupDates(_ all: PayoffSim, debts: Bool, loans: Bool, now: String) -> some View {
        if debts {
            PayoffLegendDot(color: PayoffChartCard.debtColor, label: "Cards & personal loans", value: DU.monthLabel(all.debtsDone(now), short: true))
        }
        if loans {
            PayoffLegendDot(color: PayoffChartCard.loanColor, label: "Student loans", value: DU.monthLabel(all.loansDone(now), short: true))
        }
    }
}

/// A small rounded label with an icon, for a debt's details (APR, payoff month, minimum).
struct PayoffChip: View {
    let icon: String
    let text: String
    var color: Color = .secondary
    var body: some View {
        Label(text, systemImage: icon)
            .font(.ui(.caption).weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.bg, in: Capsule())
            .lineLimit(1)
    }
}
