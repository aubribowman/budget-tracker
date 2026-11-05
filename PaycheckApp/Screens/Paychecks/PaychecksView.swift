import SwiftUI

/// The Paychecks tab: each paycheck in the month as a card (CheckCard), with its
/// lines grouped by type. Most edits happen in LineSheet, opened by tapping a line.
struct PaychecksView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.isEmpty {
                        EmptyStart()
                    } else {
                        UpcomingCard()
                        ForEach(store.engine.checksIn(store.month), id: \.self) { c in
                            CheckCard(check: c)
                        }
                        StatusLegend()
                    }
                }
                .padding()
                .readableWidth()
            }
            .background(Theme.bg)
            .toolbar { ToolbarItem(placement: .principal) { MonthBar() } }
            .inlineTitle()
        }
    }
}

/// Shown when there's no budget yet: how to bring one over from the web app.
struct EmptyStart: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down").font(.largeTitle).foregroundStyle(Theme.accent)
            Text("Bring your budget over").font(.title3.bold())
            Text("In the web app, open Setup and tap Download a backup. Then in this app tap the gear on Home, choose Import a backup, and pick that file.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).card()
    }
}

// MARK: - Top card: what to pay now

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

// MARK: - A paycheck

/// One paycheck: payday, what's coming in, what's left, the lines grouped by type,
/// extra income, and buttons to add one-time items or extra income.
struct CheckCard: View {
    @EnvironmentObject var store: Store
    let check: Check
    @State private var editingIncome = false
    @State private var incomeText = ""
    @State private var addingOneTime = false
    @State private var editingExtra: IncomeItem?
    @AppStorage(Fold.key) private var folded = ""

    var body: some View {
        let e = store.engine
        let t = e.totals(check.key, check.n)
        let ls = e.lines(check.key, check.n)
        let w = e.windowFor(check.key, check.n)
        let cardId = "check.\(check.key).\(check.n)"
        let cardFolded = Fold.has(folded, cardId)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(["First", "Second", "Third"][min(2, check.n - 1)] + " paycheck").font(.headline)
                    Text("Payday \(DU.dayLabel(check.date))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if cardFolded {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(t.left < 0 ? "Over budget" : "Left").font(.caption2).foregroundStyle(.secondary)
                        Text(money(t.left)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(t.left < 0 ? Theme.over : .primary)
                    }
                } else {
                    Button { incomeText = String(format: "%.2f", t.income - t.extraIncome); editingIncome = true } label: {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(t.extraIncome > 0.004 ? "Coming in" : "Take-home").font(.caption2).foregroundStyle(.secondary)
                            Text(money(t.income)).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                    }.buttonStyle(.plain)
                }
                Button { withAnimation(.snappy) { folded = Fold.toggled(folded, cardId) } } label: { FoldChevron(folded: cardFolded) }
                    .buttonStyle(.plain)
            }

            if !cardFolded {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(money(t.left)).font(.system(size: 40, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(t.left < 0 ? Theme.over : .primary)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(t.left < 0 ? "over budget" : "left to spend").foregroundStyle(.secondary)
            }
            Text("\(money(t.paid)) paid\(t.aside > 0.004 ? ", \(money(t.aside)) set aside" : "") so far")
                .font(.caption).foregroundStyle(.secondary)
            Tag(text: "Covers bills due \(DU.range(w.from, DU.addDays(w.to, -1)))")

            AllocationBar(totals: t)

            let extraItems = e.cell(check.key, check.n).addIncome
            if !extraItems.isEmpty {
                HStack {
                    Circle().fill(Theme.good).frame(width: 8, height: 8)
                    Text("EXTRA INCOME").font(.caption.weight(.bold)).tracking(0.5)
                    Spacer()
                    Text("+" + money(t.extraIncome)).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.good)
                }
                .padding(.top, 6)
                ForEach(extraItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.good)
                        Text(item.name)
                        Spacer()
                        Text("+" + money(item.amount)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.good)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingExtra = item }
                    .contextMenu {
                        Button { editingExtra = item } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { store.deleteIncomeItem(key: check.key, n: check.n, id: item.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }

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
                        HStack {
                            Circle().fill(info.color).frame(width: 8, height: 8)
                            Text(info.label.uppercased()).font(.caption.weight(.bold)).tracking(0.5)
                            if typeFolded && type != "expense" {
                                Text("\(done) of \(active.count) done").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(money(active.reduce(0) { $0 + $1.amount })).font(.caption.weight(.semibold)).monospacedDigit()
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
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

            HStack(spacing: 20) {
                Button { addingOneTime = true } label: { Label("One-time item", systemImage: "plus") }
                Button { editingExtra = IncomeItem() } label: { Label("Extra income", systemImage: "plus") }
            }
            .font(.subheadline)
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

// MARK: - A row on a paycheck

/// Empty circle = not paid, half filled = set aside, check mark = paid.
struct StatusDot: View {
    let status: String
    var body: some View {
        ZStack {
            Circle().stroke(status == "paid" ? Theme.good : status == "aside" ? TypeInfo.of("subscription").color : Color.secondary, lineWidth: 2)
            if status == "paid" {
                Circle().fill(Theme.good)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            } else if status == "aside" {
                Circle().trim(from: 0.25, to: 0.75).fill(TypeInfo.of("subscription").color).rotationEffect(.degrees(180))
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// One line on a paycheck. Tap the dot to change its status, tap the row for details,
/// or long-press (right-click on Mac) to skip it or move it to another paycheck.
struct LineRow: View {
    @EnvironmentObject var store: Store
    let line: Line
    let check: Check
    @State private var editing = false

    var body: some View {
        HStack(spacing: 12) {
            Button { store.cycleStatus(line) } label: { StatusDot(status: line.status) }
                .buttonStyle(.plain)
                .disabled(line.skip)
                .accessibilityLabel("\(line.name), \(line.status == "unpaid" ? "not paid" : line.status). Tap to change.")
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
            Spacer()
            Text(line.skip ? "Skipped" : money(line.isEnv ? line.env : line.amount))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(line.skip ? .secondary : .primary)
        }
        .opacity(line.skip ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editing = true }
        .contextMenu { menuItems }
        .sheet(isPresented: $editing) { LineSheet(line: line, check: check).macSheet() }
    }

    @ViewBuilder var metaView: some View {
        let parts = metaParts
        if !parts.isEmpty || line.autopay || line.aside || line.auto {
            HStack(spacing: 6) {
                if !parts.isEmpty { Text(parts.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                if line.auto { Tag(text: "Paid by autopay") }
                else if line.aside { Tag(text: "Set aside", color: TypeInfo.of("subscription").color) }
                else if line.autopay && !line.paid { Tag(text: "Autopay") }
            }
        }
    }

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

    @ViewBuilder var menuItems: some View {
        Button("Edit") { editing = true }
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
        .font(.caption).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sheets

/// Details for one line on one paycheck: status, amount for this paycheck, purchases
/// (for spending), and which debt the extra payment goes to.
struct LineSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let original: Line
    let check: Check
    init(line: Line, check: Check) { original = line; self.check = check }
    /// Re-read the line so changes made in this sheet show up right away.
    var line: Line { store.engine.lines(check.key, check.n).first { $0.uid == original.uid } ?? original }
    @State private var amountText = ""
    @State private var buyNote = ""
    @State private var buyAmount = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status") {
                        Picker("", selection: Binding(get: { line.status }, set: { store.setStatus(line, $0) })) {
                            Text("Not paid").tag("unpaid"); Text("Set aside").tag("aside"); Text("Paid").tag("paid")
                        }.pickerStyle(.segmented).frame(maxWidth: 260)
                    }
                    HStack {
                        Text(line.isEnv ? "Budget this check" : "Amount")
                        Spacer()
                        TextField("0.00", text: $amountText).decimalPad().multilineTextAlignment(.trailing).frame(maxWidth: 120)
                    }
                    if let d = line.dueDate { LabeledContent("Due", value: DU.dayLabel(d)) }
                    if line.isExtraLine {
                        Picker("Goes to", selection: Binding(get: { line.debtId }, set: { store.setExtraDebt(line, $0) })) {
                            ForEach(store.state.debts) { d in Text(d.name).tag(d.id) }
                        }
                    }
                }
                if line.isEnv {
                    Section("Purchases on this paycheck") {
                        ForEach(line.buys) { b in
                            HStack { Text(b.note.isEmpty ? "Purchase" : b.note); Spacer(); Text(money(b.amt)).monospacedDigit() }
                        }
                        .onDelete { idx in for i in idx { store.deletePurchase(key: line.homeKey, n: line.home, recId: line.id, buyId: line.buys[i].id) } }
                        HStack {
                            TextField("Where", text: $buyNote)
                            TextField("0.00", text: $buyAmount).decimalPad().multilineTextAlignment(.trailing).frame(maxWidth: 90)
                            Button("Add") {
                                guard let v = Double(buyAmount), v != 0 else { return }
                                store.editCell(line.homeKey, line.home) { c in
                                    var b = Buy(); b.amt = r2(v); b.note = buyNote; b.date = DU.iso(Date())
                                    c.buys[line.id, default: []].append(b)
                                }
                                buyNote = ""; buyAmount = ""
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(line.name)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let v = Double(amountText), abs(v - (line.isEnv ? line.env : line.amount)) > 0.004 { store.setAmount(line, v) }
                        dismiss()
                    }
                }
            }
            .onAppear { amountText = String(format: "%.2f", line.isEnv ? line.env : line.amount) }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Add a one-time item to a paycheck.
struct OneTimeSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let check: Check
    @State private var name = ""
    @State private var type = "expense"
    @State private var amount = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("What is it?", text: $name)
                Picker("Type", selection: $type) { ForEach(TypeInfo.order, id: \.self) { Text(TypeInfo.of($0).label).tag($0) } }
                TextField("Amount", text: $amount).decimalPad()
            }
            .navigationTitle("One-time item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let v = Double(amount), !name.isEmpty { store.addOneTime(key: check.key, n: check.n, name: name, type: type, amount: v) }
                        dismiss()
                    }.disabled(name.isEmpty || Double(amount) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Add or change extra income on a paycheck, like a side job or a reimbursement.
struct IncomeItemSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let check: Check
    @State var item: IncomeItem
    @State private var amount = ""

    var isNew: Bool { !store.engine.cell(check.key, check.n).addIncome.contains { $0.id == item.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Where it's from (side job, refund…)", text: $item.name)
                    TextField("Amount", text: $amount).decimalPad()
                } footer: {
                    Text("Added to this paycheck's money coming in, so it shows in what's left to spend. Only this app counts it; the web app doesn't yet.")
                }
                if !isNew {
                    Button("Delete", role: .destructive) {
                        store.deleteIncomeItem(key: check.key, n: check.n, id: item.id); dismiss()
                    }
                }
            }
            .navigationTitle(isNew ? "Extra income" : item.name)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        var x = item
                        x.name = x.name.trimmingCharacters(in: .whitespaces)
                        x.amount = r2(Double(amount) ?? 0)
                        store.saveIncomeItem(key: check.key, n: check.n, x)
                        dismiss()
                    }
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty || (Double(amount) ?? 0) <= 0)
                }
            }
            .onAppear { if item.amount > 0 { amount = String(format: "%.2f", item.amount) } }
        }
        .presentationDetents([.medium])
    }
}
