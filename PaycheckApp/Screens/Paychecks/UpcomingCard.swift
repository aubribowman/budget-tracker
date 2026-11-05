import SwiftUI

/// The foldable "Coming up" card: bills to pay now, ones set aside or on autopay, and past-due ones.
struct UpcomingCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let u = store.engine.upcoming()
        let collapsed = store.state.settings.upCollapsed
        VStack(alignment: .leading, spacing: 12) {
            Button {
                store.settings { $0.upCollapsed.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary(u)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if !u.overdue.isEmpty {
                            Text("\(u.overdue.count) past due").font(.caption.weight(.semibold)).foregroundStyle(Theme.bad)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(collapsed ? -90 : 0)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if !collapsed {
                if let c = u.cur {
                    SectionLabel("Pay from your \(DU.short(c.date)) paycheck")
                    if u.toPay.isEmpty {
                        Text("Everything on this paycheck is paid.").font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(u.toPay, id: \.uid) { l in QuickRow(line: l, late: false) }
                    }
                }
                if !u.pending.isEmpty {
                    SectionLabel("Waiting to come out, \(money(u.pending.reduce(0) { $0 + $1.amount }))")
                    ForEach(Array(u.pending.prefix(8)), id: \.uid) { l in QuickRow(line: l, late: false, pending: true) }
                }
                if !u.overdue.isEmpty {
                    SectionLabel("Past due, not marked paid", color: Theme.bad)
                    ForEach(Array(u.overdue.prefix(6)), id: \.uid) { l in QuickRow(line: l, late: true) }
                }
                if let nx = u.next {
                    Text("Next payday \(DU.dayLabel(nx.date)): \(u.nextCount) items, \(money(u.nextTotal)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private func summary(_ u: Engine.Upcoming) -> String {
        var bits: [String] = []
        if !u.toPay.isEmpty { bits.append("\(u.toPay.count) to pay") } else if u.cur != nil { bits.append("This paycheck is paid") }
        if !u.pending.isEmpty { bits.append("\(money(u.pending.reduce(0) { $0 + $1.amount })) waiting to come out") }
        return bits.isEmpty ? "Nothing to do right now" : bits.joined(separator: ", ")
    }
}

/// Small all-caps heading inside a card.
struct SectionLabel: View {
    let text: String
    var color: Color = .secondary
    init(_ t: String, color: Color = .secondary) { text = t; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).tracking(0.5).foregroundStyle(color).padding(.top, 4)
    }
}

/// A compact bill row in the "Coming up" card, with Set aside and Paid buttons.
struct QuickRow: View {
    @EnvironmentObject var store: Store
    let line: Line
    let late: Bool
    var pending = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name).font(.subheadline)
                if let d = line.dueDate {
                    Text(pending ? (line.aside ? "Set aside" : "Autopay") + ", \(line.autopay ? "comes out" : "due") \(DU.short(d))" : "Due \(DU.dayLabel(d))")
                        .font(.caption).foregroundStyle(late ? Theme.bad : .secondary)
                }
            }
            Spacer()
            Text(money(line.amount)).font(.subheadline.weight(.bold)).monospacedDigit()
            Menu {
                if !line.aside && !pending { Button("Set aside") { store.setStatus(line, "aside") } }
                Button(pending ? "Cleared" : "Paid") { store.setStatus(line, "paid") }
            } label: {
                Image(systemName: "checkmark.circle").font(.title3)
            }
        }
    }
}
