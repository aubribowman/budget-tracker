import SwiftUI
import Charts

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
