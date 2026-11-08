import SwiftUI
import Charts

/// The Month tab: what came in and went out across the month's paychecks, where your
/// pay goes by type, and items over budget. The clipboard button opens the monthly review.
struct MonthView: View {
    @EnvironmentObject var store: Store
    @State private var reviewing = false

    var body: some View {
        let e = store.engine
        let mt = e.monthTotals(store.month)
        let left = mt.income - mt.actual
        let pct: (Double) -> Int = { mt.income > 0 ? Int(($0 / mt.income * 100).rounded()) : 0 }
        let cats = categories()
        let over = overBudget()
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PageTitle("Month")
                    MonthPill()
                    MonthSummaryCard(income: mt.income, out: mt.actual, planned: mt.budget, paid: mt.paid,
                                     lastLeft: lastMonthLeft, lastLabel: DU.monthName(DU.addMonths(store.month, -1)),
                                     monthDone: monthElapsed)

                    // Share of take-home by category type
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader("Where your pay goes")
                        let slices = TypeInfo.order.compactMap { k in (mt.byType[k] ?? 0) > 0 ? Slice(label: TypeInfo.of(k).label, value: mt.byType[k] ?? 0, color: TypeInfo.of(k).color) : nil }
                            + (left > 0 ? [Slice(label: "Unassigned", value: left, color: Theme.track)] : [])
                        // A donut of take-home, with the total in the middle.
                        Chart(slices) { s in
                            SectorMark(angle: .value("Amount", s.value), innerRadius: .ratio(0.64), angularInset: 1.5)
                                .cornerRadius(4)
                                .foregroundStyle(s.color)
                        }
                        .chartLegend(.hidden)
                        .chartBackground { _ in
                            VStack(spacing: 0) {
                                Text("Take-home").font(.ui(.caption)).foregroundStyle(.secondary)
                                Text(money0(mt.income)).font(.display(.title3, weight: .bold)).monospacedDigit()
                                    .rollingNumber(mt.income)
                            }
                            // The hole in the ring is a fixed size, so keep the label inside it.
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            .frame(maxWidth: 110)
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .animation(.snappy, value: slices.map(\.value))
                        .accessibilityHidden(true)   // the rows below read the same numbers
                        ForEach(slices) { s in
                            ValueRow(spacing: Space.s) {
                                Circle().fill(s.color).frame(width: 10, height: 10)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                                Text(s.label)
                            } value: {
                                Text(money(s.value)).monospacedDigit()
                                Text("\(pct(s.value))%").monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 40, alignment: .trailing)
                            }
                            .font(.ui(.subheadline))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    // Over budget
                    VStack(alignment: .leading, spacing: 8) {
                        CardHeader("Over budget")
                        if over.isEmpty {
                            Text("Nothing is over budget this month.").font(.ui(.subheadline)).foregroundStyle(Theme.good)
                        } else {
                            ForEach(over) { item in
                                ValueRow(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).font(.ui(.subheadline).weight(.semibold))
                                        Text(item.detail).font(.ui(.caption)).foregroundStyle(.secondary)
                                    }
                                } value: {
                                    Text("+" + money(item.over)).font(.ui(.subheadline).weight(.bold)).foregroundStyle(Theme.over)
                                }
                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    // Every category
                    VStack(alignment: .leading, spacing: 8) {
                        CardHeader("Every category")
                        ForEach(cats, id: \.name) { r in
                            ValueRow {
                                // The item's own icon if it's a recurring item; one-time items get a guess from the name.
                                IconBadge(icon: store.state.recurring.first { $0.name == r.name && $0.type == r.type }.map { ItemIcon.of($0) }
                                          ?? ItemIcon.guess(r.name, type: r.type), color: TypeInfo.of(r.type).color, size: 28)
                                Text(r.name).font(.ui(.subheadline))
                            } value: {
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text(money(r.actual)).font(.ui(.subheadline).weight(.semibold)).monospacedDigit()
                                    // Green "+$20 vs budget" when under, red "−$20" when over; nothing within 50¢.
                                    let d = r.budget - r.actual
                                    if abs(d) > 0.5 {
                                        Text((d > 0 ? "+" : "−") + money(abs(d)) + " vs budget").font(.ui(.caption2)).foregroundStyle(d > 0 ? Theme.good : Theme.over)
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                .padding()
                .readableWidth()
            }
            .background(Theme.bg)
            // The clipboard button opens the full monthly review for the month shown.
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { reviewing = true } label: { Image(systemName: "list.bullet.clipboard") }
                        .accessibilityLabel("Review this month")
                }
            }
            .monthScreen("Month")
            .sheet(isPresented: $reviewing) { MonthlyReviewView(month: store.month).macSheet() }
        }
    }

    /// Last month's left over, to compare with. Nil before the plan starts or with no paychecks.
    var lastMonthLeft: Double? {
        let prev = DU.addMonths(store.month, -1)
        guard prev >= store.state.settings.startMonth else { return nil }
        let t = store.engine.monthTotals(prev)
        return t.count > 0 ? t.income - t.actual : nil
    }

    /// How far through the month today is (0...1), only when viewing this month.
    var monthElapsed: Double? {
        guard store.month == DU.ym(Date()) else { return nil }
        let cal = Calendar.current
        let days = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        return Double(cal.component(.day, from: Date())) / Double(days)
    }

    /// One wedge of the donut chart.
    struct Slice: Identifiable { let label: String; let value: Double; let color: Color; var id: String { label } }

    /// One item's planned and actual amounts across every paycheck in the month.
    struct Cat { var name: String; var type: String; var budget: Double; var actual: Double }

    /// Adds up each item over the month's paychecks. Items are matched by type and name,
    /// so one-time items with the same name are grouped too. Sorted by type, then biggest first.
    func categories() -> [Cat] {
        var map: [String: Cat] = [:]
        let e = store.engine
        for c in e.checksIn(store.month) {
            for l in e.lines(store.month, c.n) where !l.skip {
                let k = l.type + "|" + l.name.lowercased()
                var r = map[k] ?? Cat(name: l.name, type: l.type, budget: 0, actual: 0)
                r.budget += l.budget; r.actual += l.amount
                map[k] = r
            }
        }
        return map.values.sorted {
            let a = TypeInfo.order.firstIndex(of: $0.type) ?? 9, b = TypeInfo.order.firstIndex(of: $1.type) ?? 9
            return a == b ? $0.actual > $1.actual : a < b
        }
    }

    /// Something that went over: a category, a bill that cost more, or a whole paycheck.
    struct OverItem: Identifiable { let title: String; let detail: String; let over: Double; var id: String { title + detail } }

    /// Everything over budget this month: spending over its budget, bills over their
    /// usual amount (not the extra debt line), and paychecks with more assigned than they bring in.
    func overBudget() -> [OverItem] {
        let e = store.engine
        var out: [OverItem] = []
        for c in e.checksIn(store.month) {
            for l in e.lines(store.month, c.n) where !l.skip && l.kind == "rec" {
                if l.isEnv && l.spent > l.env + 0.004 {
                    out.append(OverItem(title: "\(l.name), \(DU.short(c.date))", detail: "Spent \(money(l.spent)) of \(money(l.env))", over: l.spent - l.env))
                } else if !l.isEnv && !l.isExtraLine && l.amount > l.budget + 0.004 {
                    out.append(OverItem(title: "\(l.name), \(DU.short(c.date))", detail: "\(money(l.amount)) instead of \(money(l.budget))", over: l.amount - l.budget))
                }
            }
            let t = e.totals(store.month, c.n)
            if t.left < -0.004 { out.append(OverItem(title: "\(DU.short(c.date)) paycheck", detail: "More assigned than it brings in", over: -t.left)) }
        }
        return out.sorted { $0.over > $1.over }
    }
}

/// The card the Month tab leads with: what's left over (dollars big, cents small), how it
/// compares with last month, a bar of how much pay is assigned with a tick for today,
/// and what came in, went out and is paid. Kept sparse on purpose: more room, fewer
/// pieces, so the numbers stand out.
struct MonthSummaryCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let income: Double, out: Double, planned: Double, paid: Double
    var lastLeft: Double? = nil        // last month's left over, for the comparison chip
    var lastLabel: String = ""         // "Oct"
    var monthDone: Double? = nil       // how far through the month today is; nil hides the tick

    var body: some View {
        let left = income - out
        let over = left < -0.004
        let used = income > 0 ? min(1, out / income) : 0
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.s) {
                ValueRow(alignment: .firstTextBaseline) {
                    Text(over ? "Over budget" : "Left over")
                        .font(.display(.headline, weight: .bold)).foregroundStyle(.secondary)
                } value: {
                    if out > planned + 0.5 || over {
                        chip(over ? "Over plan" : "Above plan", icon: "exclamationmark.triangle.fill", color: Theme.over)
                    } else {
                        chip("On plan", icon: "checkmark.circle.fill", color: Theme.good)
                    }
                }
                SplitMoney(value: abs(left), size: 56)
                    .foregroundStyle(over ? Theme.over : .primary)
                if let lastLeft { compare(left - lastLeft) }
            }

            AssignedBar(used: used, today: monthDone, over: over)

            // Three columns normally; one under another at the largest text sizes.
            let stats = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.m))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Space.l))
            stats {
                stat("Coming in", income, nil)
                stat("Going out", out, planDiff, subColor: out <= planned + 0.5 ? Theme.good : Theme.over)
                stat("Paid", paid, nil)
            }
        }
        .padding(Space.s)              // extra room on top of the card's own padding
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.leadCard)
    }

    /// Only shown when it's off plan by more than a rounding error.
    var planDiff: String? {
        let d = planned - out
        if abs(d) < 0.5 { return nil }
        return d > 0 ? "\(money0(d)) under plan" : "\(money0(-d)) over plan"
    }

    /// "▲ $120 vs Oct": up is good (more left over), down is rose.
    func compare(_ d: Double) -> some View {
        let up = d >= 0
        return Label("\(money0(abs(d))) vs \(lastLabel)", systemImage: up ? "arrow.up.right" : "arrow.down.right")
            .font(.ui(.subheadline).weight(.bold))
            .foregroundStyle(abs(d) < 0.5 ? .secondary : up ? Theme.good : Theme.over)
            .contentTransition(.numericText(value: d))
            .animation(.snappy, value: d)
            .accessibilityLabel("\(money0(abs(d))) \(up ? "more" : "less") than \(lastLabel)")
    }

    /// A small colored capsule with an icon, like "On track".
    func chip(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.ui(.caption).weight(.bold))
            .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    /// A big money figure with a label above and an optional note below.
    func stat(_ label: String, _ value: Double, _ sub: String?, subColor: Color = .secondary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.ui(.subheadline).weight(.semibold)).foregroundStyle(.secondary)
            Text(money0(value)).font(.display(.title2, weight: .heavy)).monospacedDigit()
                .minimumScaleFactor(0.7).lineLimit(1).rollingNumber(value)
            if let sub { Text(sub).font(.ui(.caption).weight(.semibold)).foregroundStyle(subColor).lineLimit(1).minimumScaleFactor(0.8) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A money amount with the cents smaller and raised, like "$2,459⁵¹".
struct SplitMoney: View {
    let value: Double
    var size: CGFloat = 56
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        let s = money(value)
        let parts = s.split(separator: ".", maxSplits: 1).map(String.init)
        // Smaller cents on the same baseline as the dollars. One piece of text, so at large
        // text sizes both parts shrink together instead of the dollars getting cut off.
        let dollars = Text(parts[0]).font(.display(size: size * scale, weight: .heavy))
        let cents = Text(parts.count > 1 ? "." + parts[1] : "")
            .font(.display(size: size * scale * 0.5, weight: .heavy))
        Text("\(dollars)\(cents)")
        .monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.3)
        .contentTransition(.numericText(value: value))
        .animation(.snappy, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s)
    }
}

/// How much of take-home is assigned, with a thin tick for how far through the month
/// today is. Filled past the tick means money is going out faster than the calendar.
struct AssignedBar: View {
    let used: Double          // 0...1
    var today: Double? = nil  // 0...1, nil to hide the tick
    var over = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    Group {
                        Capsule().fill(Theme.track)
                        Capsule().fill(over ? Theme.over : Theme.moss).frame(width: used * w)
                    }
                    .frame(height: 10)
                    .offset(y: 22)
                    if let today {
                        // "Today" over a thin tick, kept inside the card at the ends.
                        Text("Today").font(.ui(.caption2).weight(.bold)).foregroundStyle(.secondary)
                            .dynamicTypeSize(...DynamicTypeSize.xLarge)   // sits in a fixed-height space above the bar
                            .fixedSize()
                            .position(x: min(max(today * w, 18), w - 18), y: 7)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.primary.opacity(0.6))
                            .frame(width: 2, height: 18)
                            .offset(x: today * w - 1, y: 18)
                    }
                }
            }
            .frame(height: 36)
            .animation(.snappy, value: used)
            Text("\(Int((used * 100).rounded()))% of take-home assigned")
                .font(.ui(.caption).weight(.semibold)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((used * 100).rounded())) percent of take-home assigned"
                            + (today.map { ", \(Int(($0 * 100).rounded())) percent through the month" } ?? ""))
    }
}
