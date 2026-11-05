import SwiftUI
import Charts

/// The Payoff tab. Two sections: Debts (cards and personal loans, strategy, extra
/// payment, chart, utilization) and Student loans (StudentLoansView.swift).
/// Payoff dates come from `Engine.simulateAll`.
struct DebtView: View {
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

/// Add or edit a card or personal loan.
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
            .inlineTitle()
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
        HStack { Text(label); Spacer(); TextField("0.00", text: text).decimalPad().multilineTextAlignment(.trailing).frame(maxWidth: 120) }
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


/// A colored dot with a label, for the payoff chart legend.
struct PayoffLegendDot: View {
    let color: Color
    let label: String
    var value: String? = nil
    var font: Font = .subheadline
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(font)
            if let value { Text(value).font(font.weight(.bold)) }
        }
        .fixedSize()
    }
}

/// Everything you owe over time: cards and personal loans underneath, student loans on
/// top, with a ring where each one is paid off. Tap or drag for any month.
struct PayoffChartCard: View {
    let sim: PayoffSim
    let debts: Bool
    let loans: Bool
    @EnvironmentObject var store: Store
    @State private var picked: Date?

    static let debtColor = Color.adaptive(light: 0xC98577, dark: 0xD3968C)
    static let loanColor = Color.adaptive(light: 0x5B9AA6, dark: 0x8CC7D1)
    static let loanFill = Color.adaptive(light: 0xA9CBD1, dark: 0x5F7E83)
    static let debtFill = Color.adaptive(light: 0xE6B9AF, dark: 0xA9776E)

    struct Point: Identifiable { let id: Int; let date: Date; let debt: Double; let loan: Double }
    struct Payoff: Identifiable { let id: String; let name: String; let month: Int; let loan: Bool }

    var body: some View {
        let start = DU.firstOfMonth(DU.ym(Date()))
        let span = max(1, sim.debtSeries.count - 1)
        let points = (0 ... span).map { Point(id: $0, date: date(start, $0), debt: $0 < sim.debtSeries.count ? sim.debtSeries[$0] : 0,
                                             loan: $0 < sim.loanSeries.count ? sim.loanSeries[$0] : 0) }
        let payoffs = sim.debtPayoff.map { k, m in Payoff(id: k, name: store.state.debts.first { $0.id == k }?.name ?? "Debt", month: m, loan: false) }
            + sim.loanPayoff.map { k, m in Payoff(id: k, name: store.state.loans.first { $0.id == k }?.name ?? "Student loan", month: m, loan: true) }

        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(points) { p in
                    if loans {
                        AreaMark(x: .value("Month", p.date), yStart: .value("Owed", p.debt), yEnd: .value("Owed", p.debt + p.loan),
                                 series: .value("Group", "Student loans"))
                            .foregroundStyle(Self.loanFill)
                    }
                    if debts {
                        AreaMark(x: .value("Month", p.date), yStart: .value("Owed", 0), yEnd: .value("Owed", p.debt),
                                 series: .value("Group", "Cards"))
                            .foregroundStyle(Self.debtFill)
                    }
                }
                ForEach(payoffs) { o in
                    PointMark(x: .value("Month", date(start, o.month)), y: .value("Owed", sim.total(o.month)))
                        .symbol {
                            Circle().strokeBorder(o.loan ? Self.loanColor : Self.debtColor, lineWidth: 2.5)
                                .background(Circle().fill(Theme.card))
                                .frame(width: 11, height: 11)
                        }
                }
                if let picked {
                    RuleMark(x: .value("Month", picked))
                        .foregroundStyle(.secondary.opacity(0.5))
                        // Beside the line, inside the chart; flips to the left near the right edge.
                        .annotation(position: .trailing, alignment: .top, spacing: 8,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            callout(at: picked, start: start, payoffs: payoffs)
                        }
                }
            }
            .chartXScale(domain: start ... date(start, span))
            .chartYScale(domain: 0 ... max(1, yTicks.last ?? 1))
            .chartYAxis {
                AxisMarks(position: .leading, values: yTicks) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(compact(d)) } }
                }
            }
            .chartXAxis {
                if span > 30 {
                    // At most about five year labels, so they never run into each other.
                    AxisMarks(values: .stride(by: .year, count: max(1, Int((Double(span) / 12 / 5).rounded(.up))))) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        AxisValueLabel(format: .dateTime.year())
                    }
                } else {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
                    let pick: (CGPoint) -> Date? = { pt in proxy.value(atX: pt.x - plot.minX, as: Date.self) }
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        // Tap a month to see it, tap again to hide. Press and drag to scrub.
                        .gesture(SpatialTapGesture().onEnded { v in
                            let d = pick(v.location)
                            picked = (picked != nil && d.map { sameMonth($0, picked!) } == true) ? nil : d
                        })
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.25)
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                            .onChanged { v in if case .second(true, let drag?) = v { picked = pick(drag.location) } })
                        #if os(macOS)
                        .onContinuousHover { phase in
                            if case .active(let pt) = phase { picked = pick(pt) } else { picked = nil }
                        }
                        #endif
                }
            }
            .frame(height: 240)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { legend }
                VStack(alignment: .leading, spacing: 4) { legend }
            }
            if sim.stuck {
                Text("At these payments some balances never get paid off, so the chart stops at 50 years.")
                    .font(.caption).foregroundStyle(Theme.over)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder var legend: some View {
        if debts { PayoffLegendDot(color: Self.debtColor, label: "Cards & personal loans", font: .caption) }
        if loans { PayoffLegendDot(color: Self.loanColor, label: "Student loans", font: .caption) }
        #if os(macOS)
        Text("Hover over the chart for any month.").font(.caption).foregroundStyle(.secondary)
        #else
        Text("Tap the chart for any month.").font(.caption).foregroundStyle(.secondary)
        #endif
    }

    /// $0, half, and the starting total, like the web app.
    var yTicks: [Double] {
        let top = (0 ..< sim.debtSeries.count).map { sim.total($0) }.max() ?? 0
        return top > 0 ? [0, top / 2, top] : [0]
    }

    func date(_ start: Date, _ m: Int) -> Date { Calendar.current.date(byAdding: .month, value: m, to: start) ?? start }

    func sameMonth(_ a: Date, _ b: Date) -> Bool { Calendar.current.isDate(a, equalTo: b, toGranularity: .month) }

    func callout(at d: Date, start: Date, payoffs: [Payoff]) -> some View {
        let m = max(0, min(sim.debtSeries.count - 1, Calendar.current.dateComponents([.month], from: start, to: d).month ?? 0))
        let gone = payoffs.filter { $0.month == m }.map(\.name)
        return VStack(alignment: .leading, spacing: 3) {
            Text(date(start, m).formatted(.dateTime.month(.wide).year())).font(.caption.weight(.semibold))
            if debts { Text("Cards & loans \(money(sim.debtSeries[m]))").font(.caption) }
            if loans { Text("Student loans \(money(m < sim.loanSeries.count ? sim.loanSeries[m] : 0))").font(.caption) }
            if debts && loans { Text("Total \(money(sim.total(m)))").font(.caption.weight(.bold)) }
            if !gone.isEmpty {
                Text("Paid off: " + gone.joined(separator: ", ")).font(.caption2).foregroundStyle(Theme.good)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .monospacedDigit()
        .frame(maxWidth: 210, alignment: .leading)
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.3)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    func compact(_ v: Double) -> String {
        v >= 1000 ? "$\(Int((v / 1000).rounded()))k" : money0(v)
    }
}

/// A checkbox on iPhone and Mac, for a long label that reads as a sentence.
struct CheckboxToggle: ToggleStyle {
    func makeBody(configuration c: Configuration) -> some View {
        Button { c.isOn.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: c.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(c.isOn ? Theme.rosy : .secondary)
                    .font(.title3)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                c.label.multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(c.isOn ? "On" : "Off")
    }
}
