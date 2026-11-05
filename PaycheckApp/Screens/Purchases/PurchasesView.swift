import SwiftUI

/// The Purchases tab: spending categories with what's left in each, and every purchase
/// logged this month. The + menu adds a purchase or imports from your bank.
struct PurchasesView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var bankImport = false
    @State private var filter: String? = nil

    var envs: [Recurring] { store.state.recurring.filter { $0.type == "expense" } }

    var body: some View {
        let e = store.engine
        let all = e.monthBuys(store.month)
        let shown = filter == nil ? all : all.filter { $0.recId == filter }
        NavigationStack {
            List {
                #if os(iOS)
                Section {
                    MonthPill()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                .listSectionSpacing(Space.s)
                #endif
                Section {
                    VStack(spacing: 8) {
                        ForEach(envs) { r in categoryCard(r) }
                    }
                    #if os(macOS)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    #else
                    // No side inset: the list already indents its sections, so these line up with the purchases below.
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    #endif
                    .listRowBackground(Color.clear)
                }
                #if os(macOS)
                // Mac: one rounded card holding every purchase, like the other tabs.
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        ValueRow {
                            CardHeader(listTitle)
                        } value: {
                            Text(money(shown.reduce(0) { $0 + $1.buy.amt })).font(.ui(.headline)).monospacedDigit()
                        }
                        .padding(.bottom, 8)
                        if shown.isEmpty { emptyText.padding(.vertical, 6) }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, x in
                            if i > 0 { Divider() }
                            purchaseRow(x).padding(.vertical, 8)
                        }
                    }
                    .card()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                #else
                Section {
                    if shown.isEmpty { emptyText }
                    ForEach(shown) { x in
                        purchaseRow(x)
                            .swipeActions {
                                Button(role: .destructive) { delete(x) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                } header: {
                    HStack {
                        Text(listTitle)
                        Spacer()
                        Text(money(shown.reduce(0) { $0 + $1.buy.amt }))
                    }
                }
                #endif
            }
            .macListLook()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { adding = true } label: { Label("Log a purchase", systemImage: "square.and.pencil") }
                        Button { bankImport = true } label: { Label("Import from bank", systemImage: "building.columns") }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add a purchase")
                }
            }
            .monthScreen("Purchases")
            .sheet(isPresented: $adding) { AddPurchaseSheet(envs: envs, preset: filter).macSheet() }
            .sheet(isPresented: $bankImport) { BankImportView().macSheet() }
        }
    }

    var listTitle: String { filter.flatMap { f in envs.first { $0.id == f }?.name } ?? "All purchases" }

    var emptyText: some View {
        EmptyState(icon: "bag", title: "No purchases yet",
                   message: "Nothing logged\(filter == nil ? "" : " in this category") for \(DU.monthLabel(store.month)).",
                   color: TypeInfo.of("expense").color,
                   actionTitle: envs.isEmpty ? nil : "Log a purchase") { adding = true }
    }

    func delete(_ x: BuyEntry) {
        store.deletePurchase(key: x.check.key, n: x.check.n, recId: x.recId, buyId: x.buy.id)
    }

    func purchaseRow(_ x: BuyEntry) -> some View {
        let cat = envs.first { $0.id == x.recId }
        return ValueRow(spacing: Space.m) {
            IconBadge(icon: cat.map { ItemIcon.of($0) } ?? "bag", color: TypeInfo.of("expense").color)
            VStack(alignment: .leading, spacing: 2) {
                Text(x.buy.note.isEmpty ? "Purchase" : x.buy.note)
                Text("\(DU.parseISO(x.buy.date).map { DU.short($0) } ?? ""), \(envs.first { $0.id == x.recId }?.name ?? "Spending")\(x.buy.tx != nil ? ", imported" : "")")
                    .font(.ui(.caption)).foregroundStyle(.secondary)
            }
        } value: {
            Text(money(abs(x.buy.amt))).monospacedDigit().foregroundStyle(x.buy.amt < 0 ? Theme.good : .primary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Menu("Move to category") {
                ForEach(envs) { r in
                    Button(r.name) { store.movePurchase(key: x.check.key, n: x.check.n, from: x.recId, to: r.id, buyId: x.buy.id) }
                }
            }
            Button(role: .destructive) { delete(x) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    func categoryCard(_ r: Recurring) -> some View {
        var budget = 0.0, spent = 0.0
        for c in store.engine.checksIn(store.month) {
            for l in store.engine.lines(store.month, c.n) where l.id == r.id && !l.skip { budget += l.env; spent += l.spent }
        }
        let over = spent > budget + 0.004
        let on = filter == r.id
        return Button { filter = on ? nil : r.id } label: {
            VStack(alignment: .leading, spacing: 6) {
                ValueRow(spacing: Space.s) {
                    IconBadge(icon: ItemIcon.of(r), color: TypeInfo.of("expense").color, size: 28)
                    Text(r.name).font(.ui(.subheadline).weight(.semibold)).lineLimit(1)
                } value: {
                    Text(over ? "Over \(money(spent - budget))" : "\(money(budget - spent)) left")
                        .font(.ui(.headline)).monospacedDigit().foregroundStyle(over ? Theme.over : .primary)
                }
                ProgressBar(value: budget > 0 ? spent / budget : 0, color: over ? Theme.over : TypeInfo.of("expense").color, height: 6)
                Text("\(money(spent)) of \(money(budget))").font(.ui(.caption2)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).stroke(on ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// Log a purchase. It goes on the paycheck its date falls in.
struct AddPurchaseSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let envs: [Recurring]
    let preset: String?
    @State private var note = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var recId = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Where (Kroger, Shell, Target…)", text: $note)
                TextField("Amount", text: $amount).decimalPad()
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Category", selection: $recId) { ForEach(envs) { Text($0.name).tag($0.id) } }
                if let error { Text(error).foregroundStyle(Theme.bad).font(.ui(.footnote)) }
                Section { Text("Counts toward the paycheck you were most recently paid before this date.").font(.ui(.footnote)).foregroundStyle(.secondary) }
            }
            .navigationTitle("Log a purchase")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let v = Double(amount), !recId.isEmpty else { return }
                        if let err = store.addPurchase(date: date, note: note, amount: v, recId: recId) { error = err } else { dismiss() }
                    }.disabled(Double(amount) == nil || recId.isEmpty)
                }
            }
            .onAppear { recId = preset ?? envs.first?.id ?? "" }
        }
        .presentationDetents([.medium, .large])
    }
}
