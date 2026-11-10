import SwiftUI

/// Credit card utilization: how much of your limits you're using, and what it takes to get lower.
struct Utilization {
    /// One credit card with a limit set.
    struct Card: Identifiable { let id: String; let name: String; let balance: Double; let limit: Double
        var statement: Date? = nil   // next statement closing day, if set
        var pct: Double { limit > 0 ? balance / limit * 100 : 0 }
        /// Payment that brings this card to `target` percent.
        func toReach(_ target: Double) -> Double { max(0, balance - limit * target / 100) }
    }
    let cards: [Card]
    var balance: Double { cards.reduce(0) { $0 + $1.balance } }
    var limit: Double { cards.reduce(0) { $0 + $1.limit } }
    var pct: Double { limit > 0 ? balance / limit * 100 : 0 }
    /// Total payment that brings all cards together to `target` percent.
    func toReach(_ target: Double) -> Double { max(0, balance - limit * target / 100) }

    /// Every debt that has a credit limit (debts without one are loans, not cards).
    init(_ store: Store) {
        cards = store.state.debts.compactMap { d in
            guard let lim = d.limit, lim > 0 else { return nil }
            return Card(id: d.id, name: d.name, balance: store.engine.curBal(d), limit: lim, statement: d.nextStatement())
        }
    }

    /// Credit scores usually reward staying under 30%, and under 10% even more.
    static func band(_ pct: Double) -> (label: String, color: Color) {
        switch pct {
        case ..<10: return ("Excellent", Theme.good)
        case ..<30: return ("Good", Theme.good)
        case ..<50: return ("Fair", Color.orange)
        default: return ("High", Theme.over)
        }
    }
}

/// Summary card for the Payoff tab. Taps through to the full breakdown.
struct UtilizationCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let u = Utilization(store)
        if !u.cards.isEmpty {
            let band = Utilization.band(u.pct)
            NavigationLink { UtilizationView() } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CardHeader("Credit utilization", icon: "gauge.with.dots.needle.33percent")
                        Spacer()
                        Tag(text: band.label, color: band.color)
                        Image(systemName: "chevron.right").font(.ui(.caption).weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(u.pct.rounded()))%").font(.ui(.title).bold()).monospacedDigit().foregroundStyle(band.color)
                        Text("of \(money0(u.limit)) in limits").font(.ui(.subheadline)).foregroundStyle(.secondary)
                    }
                    UtilBar(pct: u.pct)
                    if u.pct >= 30 {
                        Text("Pay \(money(u.toReach(30))) to get under 30%.").font(.ui(.caption)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .buttonStyle(.plain)
        }
    }
}

/// Full utilization screen: overall and per card, and what to pay to get under 30% and 10%.
struct UtilizationView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let u = Utilization(store)
        let band = Utilization.band(u.pct)
        ScrollView {
            VStack(spacing: 16) {
                // All cards together, colored by band (good / fair / high).
                VStack(alignment: .leading, spacing: 10) {
                    Text("Overall").font(.ui(.caption)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(u.pct.rounded()))%").font(.display(size: 44, weight: .heavy)).foregroundStyle(band.color)
                        Tag(text: band.label, color: band.color)
                    }
                    UtilBar(pct: u.pct, height: 10)
                    Text("\(money(u.balance)) used of \(money(u.limit))").font(.ui(.subheadline)).foregroundStyle(.secondary)
                    Divider()
                    targetRow("Under 30%", u.toReach(30))
                    targetRow("Under 10%", u.toReach(10))
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()

                // Each card, highest utilization first, with what to pay to reach the next band.
                ForEach(u.cards.sorted { $0.pct > $1.pct }) { c in
                    let b = Utilization.band(c.pct)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(c.name).font(.ui(.headline))
                            Spacer()
                            Text("\(Int(c.pct.rounded()))%").font(.ui(.headline)).monospacedDigit().foregroundStyle(b.color)
                        }
                        UtilBar(pct: c.pct)
                        Text("\(money(c.balance)) of \(money0(c.limit)) limit").font(.ui(.caption)).foregroundStyle(.secondary)
                        // With a statement day, say when to pay by: the balance on that day is what's reported.
                        let by = c.statement.map { " before the statement closes \(DU.statementLabel($0))" } ?? ""
                        if c.pct >= 30 {
                            Text("Pay \(money(c.toReach(30)))\(by) to get this card under 30%.").font(.ui(.caption)).foregroundStyle(Theme.over)
                        } else if c.pct >= 10 {
                            Text("Pay \(money(c.toReach(10)))\(by) to get it under 10%.").font(.ui(.caption)).foregroundStyle(.secondary)
                        } else if let s = c.statement {
                            Text("Statement closes \(DU.statementLabel(s)).").font(.ui(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card()
                }

                VStack(alignment: .leading, spacing: 6) {
                    CardHeader("Why it matters")
                    Text("Utilization is how much of your credit limits you're using. It's one of the biggest parts of a credit score. Under 30% is good and under 10% is best, both overall and on each card. Card companies usually report your statement balance, so paying before the statement date lowers what they report.")
                        .font(.ui(.subheadline)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()
            }
            .padding()
            .readableWidth()
        }
        .background(Theme.bg)
        .navigationTitle("Credit utilization")
    }

    /// "Under 30%" with the payment it takes, or "You're there".
    func targetRow(_ label: String, _ amt: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(amt <= 0.005 ? "You're there" : "Pay \(money(amt))").monospacedDigit()
                .foregroundStyle(amt <= 0.005 ? Theme.good : .primary).fontWeight(.semibold)
        }
        .font(.ui(.subheadline))
    }
}

/// Bar with marks at 10% and 30%.
struct UtilBar: View {
    let pct: Double
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(Utilization.band(pct).color).frame(width: max(0, min(1, pct / 100)) * g.size.width)
                ForEach([10.0, 30.0], id: \.self) { m in
                    Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1.5, height: height + 4)
                        .offset(x: g.size.width * m / 100)
                }
            }
        }
        .frame(height: height)
    }
}
