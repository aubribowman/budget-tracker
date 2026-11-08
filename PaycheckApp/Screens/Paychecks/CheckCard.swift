import SwiftUI

/// One paycheck: payday, what's coming in, what's left, the lines grouped by type,
/// extra income, and buttons to add one-time items or extra income.
struct CheckCard: View {
    @EnvironmentObject var store: Store
    let check: Check
    @State private var editingIncome = false
    @State private var incomeText = ""
    @State private var addingOneTime = false
    @State private var editingExtra: IncomeItem?
    @State private var usingSavings = false
    @AppStorage(Fold.key) private var folded = ""

    var body: some View {
        let e = store.engine
        let t = e.totals(check.key, check.n)
        let ls = e.lines(check.key, check.n)
        let w = e.windowFor(check.key, check.n)
        // Which cards are folded is saved as a comma list of ids like "check.2026-10.1".
        let cardId = "check.\(check.key).\(check.n)"
        let cardFolded = Fold.has(folded, cardId)
        VStack(alignment: .leading, spacing: 12) {
            ValueRow(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(["First", "Second", "Third"][min(2, check.n - 1)] + " paycheck").font(.display(.headline, weight: .bold))
                    Text("Payday \(DU.dayLabel(check.date))").font(.ui(.caption)).foregroundStyle(.secondary)
                }
            } value: {
                if cardFolded {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(t.left < 0 ? "Over budget" : "Left").font(.ui(.caption2)).foregroundStyle(.secondary)
                        Text(money(t.left)).font(.ui(.subheadline).weight(.semibold)).monospacedDigit().rollingNumber(t.left)
                            .foregroundStyle(t.left < 0 ? Theme.over : .primary)
                    }
                } else {
                    Button { incomeText = String(format: "%.2f", t.income - t.extraIncome); editingIncome = true } label: {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(t.extraIncome > 0.004 ? "Coming in" : "Take-home").font(.ui(.caption2)).foregroundStyle(.secondary)
                            Text(money(t.income)).font(.ui(.subheadline).weight(.semibold)).monospacedDigit()
                        }
                    }.buttonStyle(.plain)
                }
                Button { withAnimation(.snappy) { folded = Fold.toggled(folded, cardId) } } label: { FoldChevron(folded: cardFolded) }
                    .buttonStyle(.plain)
            }

            if !cardFolded {
            let left = Text(money(t.left)).heroNumber(t.left).foregroundStyle(t.left < 0 ? Theme.over : .primary)
            let label = Text(t.left < 0 ? "over budget" : "left to spend").foregroundStyle(.secondary)
            // Side by side when there's room; at large text sizes the label goes under the number.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { left; label }
                VStack(alignment: .leading, spacing: 0) { left; label }
            }
            // Only once something's been paid; "$0.00 paid so far" is noise.
            if t.paid + t.aside > 0.004 {
                Text([t.paid > 0.004 ? "\(money(t.paid)) paid" : nil, t.aside > 0.004 ? "\(money(t.aside)) set aside" : nil]
                        .compactMap { $0 }.joined(separator: ", ") + " so far")
                    .font(.ui(.subheadline)).foregroundStyle(.secondary)
            }
            // The paycheck's window: bills due in these days are paid from it.
            Tag(text: "Covers bills due \(DU.range(w.from, DU.addDays(w.to, -1)))")

            // A bar split by type (bills, spending, savings…) and its key.
            AllocationBar(totals: t)
            AllocationKey(totals: t)

            // Extra income added to this paycheck (side job, money from savings). Tap to edit.
            let extraItems = e.cell(check.key, check.n).addIncome
            if !extraItems.isEmpty {
                ValueRow {
                    Circle().fill(Theme.good).frame(width: 8, height: 8)
                    Text("EXTRA INCOME").font(.ui(.caption).weight(.bold)).tracking(0.5)
                } value: {
                    Text("+" + money(t.extraIncome)).font(.ui(.caption).weight(.semibold)).monospacedDigit().foregroundStyle(Theme.good)
                }
                .padding(.top, 6)
                ForEach(extraItems) { item in
                    ValueRow(spacing: 12) {
                        Image(systemName: "plus.circle.fill").font(.ui(.title3)).foregroundStyle(Theme.good)
                        Text(item.name)
                    } value: {
                        Text("+" + money(item.amount)).font(.ui(.subheadline).weight(.semibold)).monospacedDigit().foregroundStyle(Theme.good)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingExtra = item }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { editingExtra = item }
                    .contextMenu {
                        Button { editingExtra = item } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { store.deleteIncomeItem(key: check.key, n: check.n, id: item.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }

            // The lines, grouped by type in a fixed order, each group foldable.
            ForEach(TypeInfo.order, id: \.self) { type in
                let group = ls.filter { $0.type == type }
                if !group.isEmpty {
                    let info = TypeInfo.of(type)
                    // Folding a type (say Bills) folds it on every paycheck.
                    let typeId = "type.\(type)"
                    let typeFolded = Fold.has(folded, typeId)
                    let active = group.filter { !$0.skip }
                    let done = active.filter { $0.paid || $0.aside }.count
                    Button { withAnimation(.snappy) { folded = Fold.toggled(folded, typeId) } } label: {
                        ValueRow {
                            Circle().fill(info.color).frame(width: 8, height: 8)
                            Text(info.label.uppercased()).font(.ui(.caption).weight(.bold)).tracking(0.5)
                            if typeFolded && type != "expense" {
                                Text("\(done) of \(active.count) done").font(.ui(.caption)).foregroundStyle(.secondary)
                            }
                        } value: {
                            Text(money(active.reduce(0) { $0 + $1.amount })).font(.ui(.caption).weight(.semibold)).monospacedDigit()
                            Image(systemName: "chevron.down").font(.ui(.caption2).weight(.bold)).foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(typeFolded ? -90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    if !typeFolded {
                        ForEach(group, id: \.uid) { l in LineRow(line: l, check: check) }
                    }
                }
            }

            // One "Add" button with the choices in a menu, instead of a row of buttons.
            Menu {
                Button { addingOneTime = true } label: { Label("One-time item", systemImage: "list.bullet") }
                Button { editingExtra = IncomeItem() } label: { Label("Extra income", systemImage: "plus.circle") }
                if !store.state.goals.isEmpty {
                    Button { usingSavings = true } label: { Label("Use savings", systemImage: "arrow.down.circle") }
                }
            } label: {
                Label("Add to this paycheck", systemImage: "plus")
                    .font(.ui(.subheadline).weight(.semibold))
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            }
        }
        .card()
        .alert("Take-home pay", isPresented: $editingIncome) {
            TextField("Amount", text: $incomeText).decimalPad()
            Button("Save") { if let v = Double(incomeText) { store.setIncome(key: check.key, n: check.n, v) } }
            Button("Use default") { store.setIncome(key: check.key, n: check.n, nil) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $addingOneTime) { OneTimeSheet(check: check).macSheet() }
        .sheet(item: $editingExtra) { item in IncomeItemSheet(check: check, item: item).macSheet() }
        .sheet(isPresented: $usingSavings) { UseSavingsSheet(startCheck: check).macSheet() }
    }

}

/// A bar split by type showing where this paycheck goes.
struct AllocationBar: View {
    let totals: Totals
    var body: some View {
        let pool = max(totals.income + totals.start, totals.actual, 1)
        GeometryReader { g in
            HStack(spacing: 0) {
                ForEach(TypeInfo.order, id: \.self) { k in
                    Rectangle().fill(TypeInfo.of(k).color).frame(width: g.size.width * (totals.byType[k] ?? 0) / pool)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 12)
        .background(Theme.track)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(totals.left < 0 ? Theme.over : .clear, lineWidth: 2))
    }
}

/// The key under AllocationBar: one dot per color in the bar, plus what's left.
struct AllocationKey: View {
    let totals: Totals
    var body: some View {
        FlowLayout(spacing: Space.m) {
            ForEach(TypeInfo.order.filter { (totals.byType[$0] ?? 0) > 0.004 }, id: \.self) { k in
                item(TypeInfo.of(k).label, TypeInfo.of(k).color)
            }
            if totals.left > 0.004 { item("Left", Theme.track) }
        }
        .font(.ui(.caption))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
    /// One legend entry: a colored dot and its name.
    private func item(_ label: String, _ color: Color) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(color).frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))   // keeps the pale "Left" dot visible
            Text(label)
        }
    }
}

// MARK: - A row on a paycheck

/// Empty circle = not paid, half filled = set aside, check mark = paid.
struct StatusDot: View {
    let status: String
    var body: some View {
        ZStack {
            // strokeBorder keeps the line inside the frame, so the row's clip doesn't shave the edge.
            Circle().strokeBorder(status == "paid" ? Theme.good : status == "aside" ? TypeInfo.of("subscription").color : Color.secondary, lineWidth: 2)
            if status == "paid" {
                Circle().fill(Theme.good).transition(.scale.combined(with: .opacity))
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            } else if status == "aside" {
                Circle().trim(from: 0.25, to: 0.75).fill(TypeInfo.of("subscription").color).rotationEffect(.degrees(180))
            }
        }
        .frame(width: 22, height: 22)
        .animation(.snappy, value: status)
    }
}

/// One line on a paycheck. Tap the circle to mark it paid (or not), tap the row for details,
/// swipe right to mark it paid or left to skip it (iPhone), or long-press (right-click
/// on Mac) to skip it or move it to another paycheck.
struct LineRow: View {
    @EnvironmentObject var store: Store
    let line: Line
    let check: Check
    @State private var editing = false

    var body: some View {
        ValueRow(spacing: 12) {
            Button { store.togglePaid(line) } label: { StatusDot(status: line.status) }
                .buttonStyle(.plain)
                // A tap you can feel: stronger for "paid", lighter for the other steps.
                .sensoryFeedback(trigger: line.status) { _, new in new == "paid" ? .success : .selection }
                .disabled(line.skip)
                .accessibilityLabel("\(line.name), \(line.status == "unpaid" ? "not paid" : line.status). Tap to mark \(line.paid ? "not paid" : "paid").")
            // The icon is a circle too, so clicking it does what clicking the status circle does,
            // instead of opening the row's details.
            Button { store.togglePaid(line) } label: {
                IconBadge(icon: ItemIcon.of(line, in: store.state), color: TypeInfo.of(line.type).color)
            }
            .buttonStyle(.plain)
            .disabled(line.skip)
            .accessibilityHidden(true)   // the status circle already offers this
            VStack(alignment: .leading, spacing: 3) {
                Text(line.name)
                    .strikethrough(line.paid && !line.skip, color: Theme.good)
                    .foregroundStyle(line.paid ? .secondary : .primary)
                metaView
                if line.isEnv && line.spent > 0 && !line.skip {
                    ProgressBar(value: line.env > 0 ? line.spent / line.env : 1, color: line.spent > line.env ? Theme.over : TypeInfo.of("expense").color, height: 4)
                        .frame(maxWidth: 160)
                }
            }
        } value: {
            Text(line.skip ? "Skipped" : money(line.isEnv ? line.env : line.amount))
                .font(.ui(.subheadline).weight(.semibold)).monospacedDigit()
                .foregroundStyle(line.skip ? .secondary : .primary)
        }
        .opacity(line.skip ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editing = true }
        // VoiceOver reads the row as one item: name, then amount, status and due date.
        // Double-tap opens it; changing the status and the swipe choices are in the actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.name)
        .accessibilityValue(spokenValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { editing = true }
        .accessibilityAction(named: line.paid ? "Mark not paid" : "Mark paid") { store.togglePaid(line) }
        // Swipe right to mark paid (or not paid), left to skip this month.
        .swipeRow(
            leading: line.skip ? nil : SwipeAction(label: line.paid ? "Mark not paid" : "Mark paid",
                                                   icon: line.paid ? "arrow.uturn.backward" : "checkmark",
                                                   color: Theme.good) { store.setStatus(line, line.paid ? "unpaid" : "paid") },
            trailing: line.kind == "rec" ? SwipeAction(label: line.skip ? "Restore" : "Skip this month",
                                                       icon: line.skip ? "arrow.uturn.backward" : "forward",
                                                       color: .gray) { store.toggleSkip(line) } : nil)
        .contextMenu { menuItems }
        .sheet(isPresented: $editing) { LineSheet(line: line, check: check).macSheet() }
    }

    /// What VoiceOver says after the name, like "$80.00, not paid, Due Nov 3, Autopay".
    var spokenValue: String {
        var p = [line.skip ? "Skipped" : money(line.isEnv ? line.env : line.amount)]
        if !line.skip { p.append(line.auto ? "paid by autopay" : line.paid ? "paid" : line.aside ? "set aside" : "not paid") }
        p += metaParts
        if line.autopay && !line.paid { p.append("autopay") }
        return p.joined(separator: ", ")
    }

    /// The small gray line under the name ("Due Nov 3, every 3 months") plus a status tag.
    @ViewBuilder var metaView: some View {
        let parts = metaParts
        if !parts.isEmpty || line.autopay || line.aside || line.auto {
            HStack(spacing: 6) {
                if !parts.isEmpty { Text(parts.joined(separator: ", ")).font(.ui(.caption)).foregroundStyle(.secondary) }
                if line.auto { Tag(text: "Paid by autopay") }
                else if line.aside { Tag(text: "Set aside", color: TypeInfo.of("subscription").color) }
                else if line.autopay && !line.paid { Tag(text: "Autopay") }
            }
        }
    }

    /// The pieces of that line: due date, how often, where it was moved from, and how
    /// spending compares with its budget (or a bill with its usual amount).
    var metaParts: [String] {
        var p: [String] = []
        if !line.meta.isEmpty { p.append(line.meta) }
        if line.every > 1 { p.append("every \(line.every) months") }
        if line.moved, let d = line.homeDate { p.append("moved from \(DU.short(d)) check") }
        if line.isEnv && line.spent > 0 {
            p.append(line.spent > line.env ? "over by \(money(line.spent - line.env))" : "\(money(line.env - line.spent)) left")
        } else if line.kind == "rec" && abs(line.amount - line.budget) > 0.004 && !line.isExtraLine {
            p.append("budgeted \(money(line.budget))")
        }
        return p
    }

    /// The long-press (right-click on Mac) menu. Recurring items can be skipped or moved;
    /// one-time items can be deleted.
    @ViewBuilder var menuItems: some View {
        Button("Edit") { editing = true }
        if !line.skip {
            Button(line.paid ? "Mark not paid" : "Mark paid") { store.togglePaid(line) }
            if !line.paid {
                Button(line.aside ? "Not set aside" : "Set aside") { store.setStatus(line, line.aside ? "unpaid" : "aside") }
            }
        }
        if line.kind == "rec" {
            Button(line.skip ? "Restore" : "Skip this month") { store.toggleSkip(line) }
            if !line.each {
                Menu("Move to another paycheck") {
                    ForEach(store.engine.moveOptions(homeKey: line.homeKey), id: \.self) { c in
                        Button("\(DU.short(c.date)) paycheck" + (c.key == line.homeKey && c.n == line.home ? " (original)" : "")) { store.move(line, to: c) }
                    }
                }
            }
        } else {
            Button("Delete", role: .destructive) { store.deleteOneTime(line) }
        }
    }
}

/// Explains the three status dots.
struct StatusLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) { StatusDot(status: "unpaid").scaleEffect(0.75); Text("Not paid") }
            HStack(spacing: 5) { StatusDot(status: "aside").scaleEffect(0.75); Text("Set aside") }
            HStack(spacing: 5) { StatusDot(status: "paid").scaleEffect(0.75); Text("Paid") }
        }
        .font(.ui(.caption)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
