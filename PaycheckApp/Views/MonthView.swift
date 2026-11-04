import SwiftUI

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
                    // Headline numbers
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                        stat(money(mt.income), "Coming in", "\(mt.count) paychecks")
                        stat(money(mt.actual), "Going out", "\(money(mt.budget)) budgeted")
                        stat(money(left), left < 0 ? "Over budget" : "Left over", "\(pct(abs(left)))% of take-home", color: left < 0 ? Theme.over : Theme.good)
                        stat(money(mt.paid), "Paid so far", mt.actual > 0 ? "\(Int((mt.paid / mt.actual * 100).rounded()))% of going out" : "")
                    }
                    .card()

                    // Share of take-home by category type
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Where your pay goes").font(.headline)
                        ForEach(TypeInfo.order, id: \.self) { k in
                            let v = mt.byType[k] ?? 0
                            if v > 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(TypeInfo.of(k).label); Spacer(); Text("\(money(v))  \(pct(v))%").monospacedDigit().foregroundStyle(.secondary) }
                                        .font(.subheadline)
                                    ProgressBar(value: mt.income > 0 ? v / mt.income : 0, color: TypeInfo.of(k).color)
                                }
                            }
                        }
                        if left > 0 {
                            HStack { Text("Unassigned"); Spacer(); Text("\(money(left))  \(pct(left))%").monospacedDigit().foregroundStyle(.secondary) }.font(.subheadline)
                        }
                    }
                    .card()

                    // Over budget
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Over budget").font(.headline)
                        if over.isEmpty {
                            Text("Nothing is over budget this month.").font(.subheadline).foregroundStyle(Theme.good)
                        } else {
                            ForEach(over) { item in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).font(.subheadline.weight(.semibold))
                                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("+" + money(item.over)).font(.subheadline.weight(.bold)).foregroundStyle(Theme.over)
                                }
                                Divider()
                            }
                        }
                    }
                    .card()

                    // Every category
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Every category").font(.headline)
                        ForEach(cats, id: \.name) { r in
                            HStack {
                                Circle().fill(TypeInfo.of(r.type).color).frame(width: 8, height: 8)
                                Text(r.name).font(.subheadline)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text(money(r.actual)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                    let d = r.budget - r.actual
                                    if abs(d) > 0.5 {
                                        Text((d > 0 ? "+" : "−") + money(abs(d)) + " vs budget").font(.caption2).foregroundStyle(d > 0 ? Theme.good : Theme.over)
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                    .card()
                }
                .padding()
                .readableWidth()
            }
            .background(Theme.bg)
            .toolbar {
                ToolbarItem(placement: .principal) { MonthBar() }
                ToolbarItem(placement: .primaryAction) {
                    Button { reviewing = true } label: { Image(systemName: "list.bullet.clipboard") }
                        .accessibilityLabel("Review this month")
                }
            }
            .inlineTitle()
            .sheet(isPresented: $reviewing) { MonthlyReviewView(month: store.month).macSheet() }
        }
    }

    func stat(_ v: String, _ l: String, _ sub: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.title2.weight(.heavy)).monospacedDigit().foregroundStyle(color).minimumScaleFactor(0.7).lineLimit(1)
            Text(l).font(.subheadline)
            if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) }
        }
    }

    struct Cat { var name: String; var type: String; var budget: Double; var actual: Double }

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

    struct OverItem: Identifiable { let title: String; let detail: String; let over: Double; var id: String { title + detail } }

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
