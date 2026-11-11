import SwiftUI

/// Details for one line on one paycheck: status, amount for this paycheck, purchases
/// (for spending), and which debt the extra payment goes to.
struct LineSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let original: Line
    let check: Check
    /// `line` is the line as it was when tapped; `check` is the paycheck it's shown on.
    init(line: Line, check: Check) { original = line; self.check = check }
    /// Re-read the line so changes made in this sheet show up right away.
    var line: Line { store.engine.lines(check.key, check.n).first { $0.uid == original.uid } ?? original }
    @State private var amountText = ""
    @State private var buyNote = ""
    @State private var buyAmount = ""

    var body: some View {
        NavigationStack {
            Form {
                // Status, this paycheck's amount, due date, and (for the extra line) which debt.
                Section {
                    LabeledContent("Status") {
                        Picker("", selection: Binding(get: { line.status }, set: { store.setStatus(line, $0) })) {
                            Text("Not paid").tag("unpaid"); Text("Set aside").tag("aside"); Text("Paid").tag("paid")
                        }.pickerStyle(.segmented).frame(maxWidth: 260)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // segments don't wrap
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
                    // One-time debt payments (including ones paid with savings) can be linked
                    // to a debt, so marking them paid lowers its balance on Payoff.
                    if line.kind == "ex" && line.type == "debt" && !store.state.debts.isEmpty {
                        Picker("Pays down", selection: Binding(get: { line.debtId }, set: { store.setOneTimeDebt(line, $0) })) {
                            Text("Not linked").tag("")
                            ForEach(store.state.debts) { d in Text(d.name).tag(d.id) }
                        }
                    }
                }
                // Spending categories: the purchases logged against it, with a quick add row.
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
                    // The amount is saved on Done, and only if it changed, so the override isn't
                    // created for nothing. (Status and debt changes above save right away.)
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
