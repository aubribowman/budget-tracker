import SwiftUI

/// Savings goals: how much is saved, what's planned each month, and when you'll get there.
struct GoalsView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Goal?

    var body: some View {
        let e = store.engine
        let goals = store.state.goals
        let saved = goals.reduce(0) { $0 + e.goalStatus($1).saved }
        let target = goals.reduce(0) { $0 + $1.target }
        ScrollView {
            VStack(spacing: 16) {
                if goals.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "target").font(.ui(.largeTitle)).foregroundStyle(Theme.accent)
                        Text("Save toward something").font(.ui(.title3).bold())
                        Text("Add a goal like an emergency fund or a trip. Link a savings item from your paychecks to it, and every time you mark it paid, the goal moves forward.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).card()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved across \(goals.count) \(goals.count == 1 ? "goal" : "goals")").font(.ui(.caption)).foregroundStyle(.secondary)
                        Text(money(saved)).font(.display(size: 34, weight: .heavy)).monospacedDigit()
                        ProgressBar(value: target > 0 ? saved / target : 0, color: TypeInfo.of("savings").color)
                        Text("of \(money(target))").font(.ui(.subheadline)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).card()

                    ForEach(goals) { g in
                        Button { editing = g } label: { GoalCard(goal: g) }.buttonStyle(.plain)
                    }
                }

                Button { editing = Goal() } label: {
                    Label("Add a goal", systemImage: "plus").font(.ui(.headline))
                }
                .padding(.top, 4)
            }
            .padding()
            .readableWidth()
        }
        .background(Theme.bg)
        .navigationTitle("Savings goals")
        .sheet(item: $editing) { g in GoalEditSheet(goal: g).macSheet() }
    }
}

/// One goal: progress, pace, and the paycheck items linked to it.
struct GoalCard: View {
    @EnvironmentObject var store: Store
    let goal: Goal

    var body: some View {
        let st = store.engine.goalStatus(goal)
        let linked = store.state.recurring.filter { $0.goalId == goal.id }
        VStack(alignment: .leading, spacing: 10) {
            ValueRow(alignment: .firstTextBaseline) {
                Text(goal.name).font(.ui(.headline))
            } value: {
                if st.done { Tag(text: "Reached", color: Theme.good) }
                else if let ok = st.onTrack { Tag(text: ok ? "On track" : "Behind", color: ok ? Theme.good : Theme.over) }
            }
            ValueRow(alignment: .firstTextBaseline) {
                Text(money(st.saved)).font(.display(.title2, weight: .bold)).monospacedDigit().rollingNumber(st.saved)
            } value: {
                Text("of \(money(goal.target))").font(.ui(.subheadline)).foregroundStyle(.secondary)
            }
            ProgressBar(value: st.progress, color: st.done ? Theme.good : TypeInfo.of("savings").color)
            VStack(alignment: .leading, spacing: 4) {
                if !st.done {
                    Text(paceLine(st)).font(.ui(.subheadline)).foregroundStyle(.secondary)
                }
                if let need = st.needPerMonth, !st.done, let due = DU.parseISO(goal.due) {
                    Text("Due \(DU.monthLabel(DU.ym(due))): save \(money(need)) a month to make it.")
                        .font(.ui(.caption)).foregroundStyle(st.onTrack == false ? Theme.over : .secondary)
                }
                if linked.isEmpty {
                    Text("Not linked to a savings item yet").font(.ui(.caption)).foregroundStyle(.tertiary)
                } else {
                    Text("From " + linked.map(\.name).joined(separator: ", ")).font(.ui(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    func paceLine(_ st: GoalStatus) -> String {
        if st.perMonth <= 0.005 { return "\(money(st.left)) to go. Nothing planned this month." }
        let when = st.finish.map { "reach it in \(DU.monthLabel($0))" } ?? ""
        return "\(money(st.left)) to go. \(money(st.perMonth))/month planned, \(when)."
    }
}

/// Add or edit a savings goal.
struct GoalEditSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var goal: Goal
    @State private var target = ""
    @State private var saved = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var startSaved = 0.0
    @State private var linkTo = ""

    var isNew: Bool { !store.state.goals.contains { $0.id == goal.id } }
    var savingsItems: [Recurring] { store.state.recurring.filter { $0.type == "savings" && !$0.extraLine } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (Emergency fund, Trip…)", text: $goal.name)
                    HStack { Text("Goal amount"); Spacer(); TextField("0.00", text: $target).decimalPad().multilineTextAlignment(.trailing) }
                    HStack { Text("Saved so far"); Spacer(); TextField("0.00", text: $saved).decimalPad().multilineTextAlignment(.trailing) }
                } footer: {
                    Text("Enter what’s in the account today. After that, savings you mark paid on your paychecks are added automatically.")
                }
                Section {
                    Toggle("Has a target date", isOn: $hasDue)
                    if hasDue { DatePicker("Reach it by", selection: $due, displayedComponents: .date) }
                }
                if isNew && !savingsItems.isEmpty {
                    Section {
                        Picker("Saving from", selection: $linkTo) {
                            Text("Choose later").tag("")
                            ForEach(savingsItems) { r in Text("\(r.name), \(money(r.amount))").tag(r.id) }
                        }
                    } footer: {
                        Text("Pick the savings item on your paychecks that goes toward this goal. You can change it later under Setup → Recurring.")
                    }
                }
                if !isNew {
                    Section {
                        Button("Delete goal", role: .destructive) { store.deleteGoal(goal.id); dismiss() }
                    }
                }
            }
            .navigationTitle(isNew ? "New goal" : goal.name)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(goal.name.trimmingCharacters(in: .whitespaces).isEmpty || (Double(target) ?? 0) <= 0)
                }
            }
            .onAppear {
                startSaved = isNew ? 0 : store.engine.goalStatus(goal).saved
                if isNew { goal.name = "" }
                target = goal.target > 0 ? String(format: "%.2f", goal.target) : ""
                saved = startSaved > 0 ? String(format: "%.2f", startSaved) : ""
                hasDue = !goal.due.isEmpty
                due = DU.parseISO(goal.due) ?? DU.addDays(DU.today, 365)
            }
        }
    }

    func save() {
        var g = goal
        g.target = r2(Double(target) ?? 0)
        let newSaved = r2(Double(saved) ?? 0)
        // Only reset the starting point when the saved amount was changed, so
        // savings already counted since the last update aren't lost.
        if isNew || abs(newSaved - startSaved) >= 0.005 {
            g.balance = newSaved
            g.asOf = DU.iso(DU.today)
        }
        g.due = hasDue ? DU.iso(due) : ""
        store.saveGoal(g)
        if isNew, !linkTo.isEmpty, var r = store.state.recurring.first(where: { $0.id == linkTo }) {
            r.goalId = g.id
            store.saveRecurring(r)
        }
        dismiss()
    }
}
