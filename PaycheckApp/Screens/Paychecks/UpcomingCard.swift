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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        CardHeader("To pay now", icon: "checklist")
                        // Only when folded; open, the rows below say the same thing.
                        if collapsed { Text(summary(u)).font(.ui(.subheadline)).foregroundStyle(.secondary) }
                        if !u.overdue.isEmpty {
                            Label("\(u.overdue.count) past due", systemImage: "exclamationmark.circle.fill")
                                .font(.ui(.caption).weight(.semibold)).foregroundStyle(Theme.bad)
                        }
                    }
                    Spacer()
                    FoldChevron(folded: collapsed)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                if let c = u.cur {
                    SectionLabel("Pay from your \(DU.short(c.date)) paycheck")
                    if u.toPay.isEmpty {
                        EmptyState(icon: "checkmark.seal", title: "All paid", message: "Everything on this paycheck is paid.", color: Theme.good)
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
                    Text(u.nextCount == 0 ? "Nothing due from your next paycheck, \(DU.dayLabel(nx.date))."
                         : "Next payday \(DU.dayLabel(nx.date)): \(u.nextCount) \(u.nextCount == 1 ? "item" : "items"), \(money(u.nextTotal)).")
                        .font(.ui(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private func summary(_ u: Engine.Upcoming) -> String {
        var bits: [String] = []
        if !u.toPay.isEmpty {
            let total = u.toPay.reduce(0) { $0 + $1.amount }
            bits.append(u.toPay.count == 1 ? "\(u.toPay[0].name), \(money(total))" : "\(u.toPay.count) bills, \(money(total))")
        } else if u.cur != nil { bits.append("This paycheck is paid") }
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
        Text(text.uppercased()).font(.ui(.caption).weight(.bold)).tracking(0.5).foregroundStyle(color).padding(.top, 4)
    }
}

/// A compact bill row in the "Coming up" card, with Set aside and Paid buttons.
struct QuickRow: View {
    @EnvironmentObject var store: Store
    let line: Line
    let late: Bool
    var pending = false

    var body: some View {
        ValueRow(spacing: Space.m) {
            IconBadge(icon: ItemIcon.of(line, in: store.state), color: TypeInfo.of(line.type).color)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name).font(.ui(.subheadline))
                if let d = line.dueDate {
                    Text(pending ? (line.aside ? "Set aside" : "Autopay") + ", \(line.autopay ? "comes out" : "due") \(DU.short(d))" : "Due \(DU.dayLabel(d))")
                        .font(.ui(.caption)).foregroundStyle(late ? Theme.bad : .secondary)
                }
            }
        } value: {
            Text(money(line.amount)).font(.ui(.subheadline).weight(.bold)).monospacedDigit()
            Menu {
                if !line.aside && !pending { Button("Set aside") { store.setStatus(line, "aside") } }
                Button(pending ? "Cleared" : "Paid") { store.setStatus(line, "paid") }
            } label: {
                Image(systemName: "checkmark.circle").font(.ui(.title3))
            }
            .accessibilityLabel("Mark \(line.name) paid")
            .sensoryFeedback(trigger: line.status) { _, new in new == "paid" ? .success : .selection }
        }
        .swipeRow(leading: SwipeAction(label: pending ? "Cleared" : "Mark paid", icon: "checkmark", color: Theme.good) {
            store.setStatus(line, "paid")
        })
    }
}
