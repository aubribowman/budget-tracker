import SwiftUI

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
