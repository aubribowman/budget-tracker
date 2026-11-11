import SwiftUI
import Charts

/// A colored dot with a label, for the payoff chart legend.
struct PayoffLegendDot: View {
    let color: Color
    let label: String
    var value: String? = nil
    var font: Font = .ui(.subheadline)
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(font)
            if let value { Text(value).font(font.weight(.bold)) }
        }
        // Keep its natural width when there's room, but let the words wrap at large text sizes.
        .fixedSize(horizontal: false, vertical: true)
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

    /// One month on the chart: what's owed on cards/personal loans and on student loans.
    struct Point: Identifiable { let id: Int; let date: Date; let debt: Double; let loan: Double }
    /// A debt or loan and the month (counting from now) it's paid off, for the markers.
    struct Payoff: Identifiable { let id: String; let name: String; let month: Int; let loan: Bool }

    var body: some View {
        let start = DU.firstOfMonth(DU.ym(Date()))
        let span = max(1, sim.debtSeries.count - 1)
        let points = (0 ... span).map { Point(id: $0, date: date(start, $0), debt: $0 < sim.debtSeries.count ? sim.debtSeries[$0] : 0,
                                             loan: $0 < sim.loanSeries.count ? sim.loanSeries[$0] : 0) }
        let payoffs = sim.debtPayoff.map { k, m in Payoff(id: k, name: store.state.debts.first { $0.id == k }?.name ?? "Debt", month: m, loan: false) }
            + sim.loanPayoff.map { k, m in Payoff(id: k, name: store.state.loans.first { $0.id == k }?.name ?? "Student loan", month: m, loan: true) }

        VStack(alignment: .leading, spacing: 10) {
            CardHeader("Balance over time", icon: "chart.xyaxis.line")
            Chart {
                ForEach(points) { p in
                    if loans {
                        AreaMark(x: .value("Month", p.date), yStart: .value("Owed", p.debt), yEnd: .value("Owed", p.debt + p.loan),
                                 series: .value("Group", "Student loans"))
                            .foregroundStyle(Self.loanFill.gradient)
                            .interpolationMethod(.monotone)
                    }
                    if debts {
                        AreaMark(x: .value("Month", p.date), yStart: .value("Owed", 0), yEnd: .value("Owed", p.debt),
                                 series: .value("Group", "Cards"))
                            .foregroundStyle(Self.debtFill.gradient)
                            .interpolationMethod(.monotone)
                    }
                    // A crisp line along the top edge of everything owed.
                    LineMark(x: .value("Month", p.date), y: .value("Owed", (debts ? p.debt : 0) + (loans ? p.loan : 0)),
                             series: .value("Group", "Total"))
                        .foregroundStyle(loans ? Self.loanColor : Self.debtColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
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
                    let m = monthIndex(picked, start)
                    PointMark(x: .value("Month", date(start, m)), y: .value("Owed", sim.total(m)))
                        .symbol { Circle().fill(Theme.accent).overlay(Circle().stroke(Theme.card, lineWidth: 2)).frame(width: 12, height: 12) }
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
            // A light tick each time the picked month changes while scrubbing.
            .sensoryFeedback(.selection, trigger: picked.map { monthIndex($0, start) })

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { legend }
                VStack(alignment: .leading, spacing: 4) { legend }
            }
            if sim.stuck {
                Text("At these payments some balances never get paid off, so the chart stops at 50 years.")
                    .font(.ui(.caption)).foregroundStyle(Theme.over)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder var legend: some View {
        if debts { PayoffLegendDot(color: Self.debtColor, label: "Cards & personal loans", font: .ui(.caption)) }
        if loans { PayoffLegendDot(color: Self.loanColor, label: "Student loans", font: .ui(.caption)) }
        #if os(macOS)
        Text("Hover over the chart for any month.").font(.ui(.caption)).foregroundStyle(.secondary)
        #else
        Text("Tap the chart for any month.").font(.ui(.caption)).foregroundStyle(.secondary)
        #endif
    }

    /// $0, half, and the starting total, like the web app.
    var yTicks: [Double] {
        let top = (0 ..< sim.debtSeries.count).map { sim.total($0) }.max() ?? 0
        return top > 0 ? [0, top / 2, top] : [0]
    }

    // Converting between chart dates and month numbers (0 = this month).
    func date(_ start: Date, _ m: Int) -> Date { Calendar.current.date(byAdding: .month, value: m, to: start) ?? start }

    /// Which month of the simulation a chart date falls in, kept within the data.
    func monthIndex(_ d: Date, _ start: Date) -> Int {
        max(0, min(sim.debtSeries.count - 1, Calendar.current.dateComponents([.month], from: start, to: d).month ?? 0))
    }

    func sameMonth(_ a: Date, _ b: Date) -> Bool { Calendar.current.isDate(a, equalTo: b, toGranularity: .month) }

    /// The box shown while dragging across the chart: the month, what's owed,
    /// and anything paid off that month.
    func callout(at d: Date, start: Date, payoffs: [Payoff]) -> some View {
        let m = monthIndex(d, start)
        let gone = payoffs.filter { $0.month == m }.map(\.name)
        return VStack(alignment: .leading, spacing: 3) {
            Text(date(start, m).formatted(.dateTime.month(.wide).year())).font(.ui(.caption).weight(.semibold))
            if debts { Text("Cards & loans \(money(sim.debtSeries[m]))").font(.ui(.caption)) }
            if loans { Text("Student loans \(money(m < sim.loanSeries.count ? sim.loanSeries[m] : 0))").font(.ui(.caption)) }
            if debts && loans { Text("Total \(money(sim.total(m)))").font(.ui(.caption).weight(.bold)) }
            if !gone.isEmpty {
                Text("Paid off: " + gone.joined(separator: ", ")).font(.ui(.caption2)).foregroundStyle(Theme.good)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .monospacedDigit()
        .frame(maxWidth: 210, alignment: .leading)
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).stroke(.secondary.opacity(0.3)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    /// Short axis labels: "$12k", or "$800" under a thousand.
    func compact(_ v: Double) -> String {
        v >= 1000 ? "$\(Int((v / 1000).rounded()))k" : money0(v)
    }
}
