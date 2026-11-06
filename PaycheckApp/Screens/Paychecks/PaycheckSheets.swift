import SwiftUI

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
                    if store.isSavingsUse(key: check.key, n: check.n, id: item.id) {
                        Text("Taken from a savings goal to pay for something on this paycheck. Changing the amount changes what it paid for and the goal too. Deleting it puts the money back on the goal.")
                    } else {
                        Text("Added to this paycheck's money coming in, so it shows in what's left to spend.")
                    }
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
