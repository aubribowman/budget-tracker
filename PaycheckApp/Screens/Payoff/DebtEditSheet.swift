import SwiftUI

/// Add or edit a card or personal loan.
struct DebtEditSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var debt: Debt
    // Text fields edit strings; save() turns them back into numbers.
    @State private var balance = ""
    @State private var apr = ""
    @State private var minPay = ""
    @State private var limit = ""
    @State private var original = ""
    @State private var confirmDelete = false

    var isNew: Bool { !store.state.debts.contains { $0.id == debt.id } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $debt.name)
                // "Starting balance" is the highest it was, for the paid-off progress bar.
                // A credit limit makes it a card for the utilization screen.
                Section {
                    field("Balance on latest statement", $balance)
                    field("Starting balance", $original)
                    field("APR %", $apr)
                    field("Minimum payment", $minPay)
                    field("Credit limit (cards only)", $limit)
                } footer: {
                    Text("Changing the balance resets tracking to today. Payments you mark paid after today come off it automatically.")
                }
                if !isNew {
                    Button("Delete this debt", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(isNew ? "New debt" : debt.name)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
            }
            .confirmationDialog("Delete \(debt.name)?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { store.deleteDebt(debt.id); dismiss() }
            }
            // Fill the text fields from the debt.
            .onAppear {
                balance = String(format: "%.2f", debt.balance); apr = String(format: "%.2f", debt.apr)
                minPay = String(format: "%.2f", debt.min); original = String(format: "%.2f", debt.original)
                limit = debt.limit.map { String(format: "%.2f", $0) } ?? ""
            }
        }
    }

    /// A label with a number field on the right.
    func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack { Text(label); Spacer(); TextField("0.00", text: text).decimalPad().multilineTextAlignment(.trailing).frame(maxWidth: 120) }
    }

    /// Saves the debt. A new balance also moves `asOf` to now, so only payments marked
    /// paid after this moment come off it (see Engine.paidSince).
    func save() {
        var d = debt
        let nb = Double(balance) ?? d.balance
        if abs(nb - d.balance) > 0.004 || isNew { d.balance = nb; d.asOf = DU.iso(Date()); d.asOfAt = DU.stamp() }
        d.apr = Double(apr) ?? d.apr
        d.min = Double(minPay) ?? d.min
        d.original = Double(original) ?? d.original
        if d.original <= 0 { d.original = d.balance }
        d.limit = Double(limit).flatMap { $0 > 0 ? $0 : nil }
        store.saveDebt(d)
    }
}
