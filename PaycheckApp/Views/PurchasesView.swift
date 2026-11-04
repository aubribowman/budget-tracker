import SwiftUI

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
                Section {
                    VStack(spacing: 8) {
                        ForEach(envs) { r in categoryCard(r) }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                Section {
                    if shown.isEmpty {
                        Text("No purchases logged\(filter == nil ? "" : " in this category") for \(DU.monthLabel(store.month)) yet. Tap + to add one.")
                            .foregroundStyle(.secondary).font(.subheadline)
                    }
                    ForEach(shown) { x in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(x.buy.note.isEmpty ? "Purchase" : x.buy.note)
                                Text("\(DU.parseISO(x.buy.date).map { DU.short($0) } ?? ""), \(envs.first { $0.id == x.recId }?.name ?? "Spending")\(x.buy.tx != nil ? ", imported" : "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(money(abs(x.buy.amt))).monospacedDigit().foregroundStyle(x.buy.amt < 0 ? Theme.good : .primary)
                        }
                        .swipeActions {
                            Button(role: .destructive) { store.deletePurchase(key: x.check.key, n: x.check.n, recId: x.recId, buyId: x.buy.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                        .contextMenu {
                            Menu("Move to category") {
                                ForEach(envs) { r in
                                    Button(r.name) { store.movePurchase(key: x.check.key, n: x.check.n, from: x.recId, to: r.id, buyId: x.buy.id) }
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(filter.flatMap { f in envs.first { $0.id == f }?.name } ?? "All purchases")
                        Spacer()
                        Text(money(shown.reduce(0) { $0 + $1.buy.amt }))
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) { MonthBar() }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { adding = true } label: { Label("Log a purchase", systemImage: "square.and.pencil") }
                        Button { bankImport = true } label: { Label("Import from bank", systemImage: "building.columns") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .inlineTitle()
            .sheet(isPresented: $adding) { AddPurchaseSheet(envs: envs, preset: filter).macSheet() }
            .sheet(isPresented: $bankImport) { BankImportView().macSheet() }
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
                HStack(alignment: .firstTextBaseline) {
                    Text(r.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(over ? "Over \(money(spent - budget))" : "\(money(budget - spent)) left")
                        .font(.headline).monospacedDigit().foregroundStyle(over ? Theme.over : .primary)
                }
                ProgressBar(value: budget > 0 ? spent / budget : 0, color: over ? Theme.over : TypeInfo.of("expense").color, height: 6)
                Text("\(money(spent)) of \(money(budget))").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

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
                if let error { Text(error).foregroundStyle(Theme.bad).font(.footnote) }
                Section { Text("Counts toward the paycheck you were most recently paid before this date.").font(.footnote).foregroundStyle(.secondary) }
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
