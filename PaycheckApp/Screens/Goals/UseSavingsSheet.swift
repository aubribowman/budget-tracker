import SwiftUI

/// Spend money saved in a goal, like paying the babysitter from a babysitter fund.
/// Adds the money to a paycheck as income from the goal, records what it paid for as
/// paid, and takes it off the goal. See BudgetState+Savings.swift.
struct UseSavingsSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    /// The goal to start with (opened from a goal), or nil to pick one.
    var startGoal: String? = nil
    /// The paycheck to start with (opened from a paycheck), or nil for the current one.
    var startCheck: Check? = nil

    @State private var goalId = ""
    @State private var checkId = ""
    @State private var name = ""
    @State private var amount = ""
    @State private var type = "bill"

    private static let types = ["bill", "subscription", "expense", "debt"]

    var body: some View {
        let e = store.engine
        let goals = store.state.goals
        let goal = goals.first { $0.id == goalId }
        let saved = goal.map { e.goalStatus($0).saved } ?? 0
        let checks = options()
        let check = checks.first { id($0) == checkId }
        let value = r2(Double(amount) ?? 0)
        let tooMuch = value > saved + 0.005

        NavigationStack {
            Form {
                Section {
                    Picker("From", selection: $goalId) {
                        ForEach(goals) { g in Text(g.name).tag(g.id) }
                    }
                    TextField("What it's for (babysitter, car repair…)", text: $name)
                    TextField("Amount", text: $amount).decimalPad()
                } footer: {
                    if goal != nil {
                        Text(tooMuch ? "That's more than the \(money(saved)) saved."
                                     : "\(money(saved)) saved.")
                            .foregroundStyle(tooMuch ? Theme.over : .secondary)
                    }
                }
                Section {
                    Picker("Paycheck", selection: $checkId) {
                        ForEach(checks, id: \.self) { c in Text("\(DU.short(c.date)) paycheck").tag(id(c)) }
                    }
                    Picker("Counts as", selection: $type) {
                        ForEach(Self.types, id: \.self) { Text(TypeInfo.of($0).label).tag($0) }
                    }
                } footer: {
                    if let g = goal, let c = check, value > 0.004, !tooMuch {
                        Text("Adds \(money(value)) to your \(DU.short(c.date)) paycheck from \(g.name) and marks \(label) paid, so what's left to spend doesn't change. \(g.name) goes from \(money(saved)) to \(money(saved - value)).")
                    } else {
                        Text("The money is added to that paycheck and what it paid for is marked paid, so what's left to spend doesn't change. Delete either one later to put the money back.")
                    }
                }
            }
            .navigationTitle("Use savings")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        if let c = check {
                            store.useSavings(goalId: goalId, amount: value, for: label, type: type, on: c)
                        }
                        dismiss()
                    }
                    .disabled(goal == nil || check == nil || value <= 0.004 || tooMuch)
                }
            }
            .keyboardDoneButton()
            .onAppear(perform: setUp)
        }
    }

    /// What the spending is called: what was typed, or the goal's name.
    private var label: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? (store.state.goals.first { $0.id == goalId }?.name ?? "Savings") : t
    }

    private func id(_ c: Check) -> String { "\(c.key)|\(c.n)" }

    /// Paychecks from last month through next month (from the budget's start), plus the
    /// one this was opened from.
    private func options() -> [Check] {
        let e = store.engine
        let now = DU.ym(Date())
        var out = [-1, 0, 1].map { DU.addMonths(now, $0) }
            .filter { $0 >= store.state.settings.startMonth }
            .flatMap { e.checksIn($0) }
        if let c = startCheck, !out.contains(c) { out.append(c) }
        return out.sorted { $0.date < $1.date }
    }

    private func setUp() {
        let e = store.engine
        if goalId.isEmpty {
            goalId = startGoal
                ?? store.state.goals.first { e.goalStatus($0).saved > 0.005 }?.id
                ?? store.state.goals.first?.id ?? ""
        }
        if checkId.isEmpty, let c = startCheck ?? e.periodCheck(DU.today) ?? options().first {
            checkId = id(c)
        }
    }
}
