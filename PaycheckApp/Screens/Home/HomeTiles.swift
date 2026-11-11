import SwiftUI
import Charts

/// Colors for charts with one color per item (the spending ring's categories, the
/// investment holdings strip), taken from the app's palette.
enum HomePalette {
    static let colors: [Color] = [Theme.moss, Theme.midnight, Theme.rosy,
                                  Color(hex: 0xC9A66B), Color(hex: 0x6E8F8A), Theme.darkGreen]
    static func color(_ i: Int) -> Color { colors[i % colors.count] }
}

/// Goals, Debt, Net worth and Investments on Home as small tiles, two across, each
/// with one figure and a small picture. Tapping a tile opens its screen. At the
/// largest text sizes they stack in one column so the numbers have room.
struct HomeTiles: View {
    let goals: () -> Void
    let debt: () -> Void
    let investments: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 14) {
                GoalsTile(open: goals); DebtTile(open: debt)
                NetWorthTile(open: investments); InvestTile(open: investments)
            }
        } else {
            // A Grid (not LazyVGrid) so both tiles in a row are the same height.
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow { GoalsTile(open: goals); DebtTile(open: debt) }
                GridRow { NetWorthTile(open: investments); InvestTile(open: investments) }
            }
        }
    }
}

/// One tile: icon and title, a big figure, a short note, and a picture at the bottom.
/// Used on Home and Payoff. Tappable when `open` is set.
struct SummaryTile<Visual: View>: View {
    let title: String
    let icon: String
    let value: String
    let note: String
    var noteColor: Color = .secondary
    let open: (() -> Void)?
    @ViewBuilder let visual: () -> Visual

    var body: some View {
        if let open {
            Button(action: open) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens \(title)")
        } else {
            content.accessibilityElement(children: .combine)
        }
    }

    var content: some View {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon).font(.ui(.caption).weight(.semibold)).foregroundStyle(Theme.accent)
                    .lineLimit(1)
                Text(value).font(.display(size: 22, weight: .bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(note).font(.ui(.caption).weight(.medium)).foregroundStyle(noteColor)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                visual()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card()
    }
}

/// Savings goals: the total saved, and a ring for each of the first three goals.
private struct GoalsTile: View {
    @EnvironmentObject var store: Store
    let open: () -> Void
    var body: some View {
        let goals = store.state.goals
        let saved = goals.reduce(0) { $0 + store.engine.goalStatus($1).saved }
        let target = goals.reduce(0) { $0 + $1.target }
        SummaryTile(title: "Goals", icon: "target", value: money0(saved),
             note: goals.isEmpty ? "Add a goal" : "of \(money0(target))", open: open) {
            HStack(spacing: 8) {
                ForEach(goals.prefix(3)) { g in
                    let st = store.engine.goalStatus(g)
                    ZStack {
                        Circle().stroke(Theme.track, lineWidth: 5)
                        Circle().trim(from: 0, to: max(0.02, min(1, st.progress)))
                            .stroke(st.done ? Theme.good : Theme.moss, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int((st.progress * 100).rounded()))%").font(.ui(.caption2).weight(.bold)).monospacedDigit()
                            .minimumScaleFactor(0.6)
                    }
                    .frame(width: 38, height: 38)
                    .dynamicTypeSize(...DynamicTypeSize.large)   // fixed-size ring, so its label can't grow
                    .accessibilityLabel("\(g.name), \(Int((st.progress * 100).rounded())) percent")
                }
            }
        }
    }
}

/// Debt: what's owed now, and how much of the starting balances is paid off.
private struct DebtTile: View {
    @EnvironmentObject var store: Store
    let open: () -> Void
    var body: some View {
        let debts = store.state.debts
        let now = debts.reduce(0) { $0 + store.engine.curBal($1) }
        let start = debts.reduce(0) { $0 + max($1.original, store.engine.curBal($1)) }
        let paid = start > 0 ? max(0, min(1, 1 - now / start)) : 0
        SummaryTile(title: "Debt", icon: "creditcard", value: money0(now),
             note: debts.isEmpty ? "None added" : now <= 0.005 ? "All paid off" : "\(Int((paid * 100).rounded()))% paid off",
             noteColor: debts.isEmpty ? .secondary : Theme.good, open: open) {
            ProgressBar(value: paid, color: Theme.rosy, height: 8)
        }
    }
}

/// Net worth: how it's changed since the last saved point (green up, red down), and a
/// small line of recent points. The figure itself stays neutral even when negative.
private struct NetWorthTile: View {
    @EnvironmentObject var store: Store
    let open: () -> Void
    var body: some View {
        let nw = store.engine.netWorth()
        let last = store.engine.lastValuePoint()
        let change = last.map { nw.total - $0.net }
        let since = last.flatMap { DU.parseISO($0.date) }.map { DU.short($0) } ?? ""
        let pts = store.state.investHistory.suffix(12).map(\.net) + [nw.total]
        SummaryTile(title: "Net worth", icon: "chart.line.uptrend.xyaxis",
             value: nw.total < 0 ? "−" + money0(-nw.total) : money0(nw.total),
             note: change.map { "\($0 >= 0 ? "▲" : "▼") \(money0(abs($0))) since \(since)" } ?? "Tracking starts today",
             noteColor: change.map { $0 >= 0 ? Theme.good : Theme.over } ?? .secondary, open: open) {
            if pts.count > 2 {
                Sparkline(values: pts, color: (change ?? 0) >= 0 ? Theme.good : Theme.rosy)
            } else {
                ProgressBar(value: 0, color: Theme.moss, height: 8).opacity(0.5)
            }
        }
    }
}

/// Investments: the total, and a strip showing how it's split across holdings.
private struct InvestTile: View {
    @EnvironmentObject var store: Store
    let open: () -> Void
    var body: some View {
        let total = store.engine.investTotal()
        let holdings = store.state.accounts.flatMap(\.holdings).filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let sum = holdings.reduce(0) { $0 + $1.value }
        SummaryTile(title: "Investments", icon: "chart.pie", value: money0(total),
             note: store.state.accounts.isEmpty ? "Add an account" : "\(holdings.count) \(holdings.count == 1 ? "holding" : "holdings")",
             open: open) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if holdings.isEmpty {
                        Capsule().fill(Theme.track)
                    }
                    ForEach(Array(holdings.prefix(6).enumerated()), id: \.offset) { i, h in
                        RoundedRectangle(cornerRadius: 3).fill(HomePalette.color(i))
                            .frame(width: max(4, geo.size.width * h.value / max(sum, 1) - 2))
                    }
                }
            }
            .frame(height: 8)
        }
    }
}

/// A tiny line chart with no axes.
private struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { i, v in
            LineMark(x: .value("i", i), y: .value("v", v)).interpolationMethod(.catmullRom)
                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            AreaMark(x: .value("i", i), yStart: .value("min", values.min() ?? 0), yEnd: .value("v", v))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}
