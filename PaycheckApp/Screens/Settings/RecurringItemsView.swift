import SwiftUI

/// Every recurring item, grouped by type, with add and edit.
struct RecurringListView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Recurring?

    var body: some View {
        List {
            ForEach(TypeInfo.order, id: \.self) { type in
                let items = store.state.recurring.filter { $0.type == type && !$0.extraLine }
                Section {
                    ForEach(items) { r in
                        Button { editing = r } label: {
                            HStack(spacing: Space.m) {
                                IconBadge(icon: ItemIcon.of(r), color: TypeInfo.of(r.type).color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).foregroundStyle(.primary)
                                    Text(summary(r)).font(.ui(.caption)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(money(r.amount)).monospacedDigit().foregroundStyle(.primary)
                            }
                        }
                    }
                    .onDelete { idx in for i in idx { store.deleteRecurring(items[i].id) } }
                    Button { var r = Recurring(); r.type = type; r.name = "New " + TypeInfo.of(type).label.lowercased().replacingOccurrences(of: "debt payments", with: "payment"); r.start = DU.ym(Date())
                        if type == "expense" || type == "savings" { r.when = "each" } else { r.due = "1" }
                        editing = r
                    } label: { Label("Add", systemImage: "plus") }
                } header: {
                    HStack { Circle().fill(TypeInfo.of(type).color).frame(width: 8, height: 8); Text(TypeInfo.of(type).label) }
                }
            }
        }
        .navigationTitle("Recurring")
        .inlineTitle()
        .sheet(item: $editing) { r in RecurringEditSheet(item: r).macSheet() }
    }

    func summary(_ r: Recurring) -> String {
        var p: [String] = []
        if r.when == "each" { p.append("Every check") }
        else {
            if r.when == "1" || r.when == "2" { p.append("Check \(r.when)") }
            if let d = r.dueDay { p.append("due the \(DU.ordinal(d))") } else if r.when == "auto" { p.append("by due date") }
        }
        if r.every > 1 { p.append("every \(r.every) months") }
        if !r.end.isEmpty { p.append("ends \(DU.monthLabel(r.end, short: true))") }
        if r.autopay { p.append("autopay") }
        let t = p.joined(separator: ", ")
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}

/// Add or edit a recurring item: name, type, amount, due day, which paycheck, how often.
struct RecurringEditSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var item: Recurring
    @State private var amount = ""
    @State private var hasEnd = false
    @State private var endDate = Date()
    @State private var startDate = Date()

    var isNew: Bool { !store.state.recurring.contains { $0.id == item.id } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $item.name)
                HStack { Text("Amount"); Spacer(); TextField("0.00", text: $amount).decimalPad().multilineTextAlignment(.trailing) }
                Picker("Type", selection: $item.type) { ForEach(TypeInfo.order, id: \.self) { Text(TypeInfo.of($0).label).tag($0) } }
                Picker("Paid from", selection: $item.when) {
                    Text("By due date").tag("auto"); Text("Always check 1").tag("1"); Text("Always check 2").tag("2"); Text("Every check").tag("each")
                }
                if item.when != "each" {
                    Picker("Due day", selection: $item.due) {
                        Text("None").tag("")
                        ForEach(1...31, id: \.self) { Text(DU.ordinal($0)).tag(String($0)) }
                    }
                }
                Picker("Repeats", selection: $item.every) {
                    Text("Monthly").tag(1); Text("Every 2 months").tag(2); Text("Every 3 months").tag(3); Text("Every 6 months").tag(6); Text("Yearly").tag(12)
                }
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                Toggle("Has an end date", isOn: $hasEnd)
                if hasEnd { DatePicker("Ends", selection: $endDate, displayedComponents: .date) }
                if item.type != "expense" { Toggle("Autopay", isOn: $item.autopay) }
                if item.type == "debt" {
                    Picker("Debt", selection: $item.debtId) {
                        Text("Not linked").tag("")
                        ForEach(store.state.debts) { Text($0.name).tag($0.id) }
                    }
                }
                if item.type == "savings" && !store.state.goals.isEmpty {
                    Picker("Goal", selection: $item.goalId) {
                        Text("Not linked").tag("")
                        ForEach(store.state.goals) { Text($0.name).tag($0.id) }
                    }
                }
                Section("Icon") {
                    IconPicker(icon: $item.icon, name: item.name, type: item.type)
                }
                if !isNew {
                    Button("Delete", role: .destructive) { store.deleteRecurring(item.id); dismiss() }
                }
            }
            .navigationTitle(isNew ? "New item" : item.name)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var r = item
                        r.amount = Double(amount) ?? r.amount
                        r.start = DU.ym(startDate)
                        r.end = hasEnd ? DU.ym(endDate) : ""
                        store.saveRecurring(r)
                        dismiss()
                    }
                }
            }
            .onAppear {
                amount = String(format: "%.2f", item.amount)
                startDate = DU.firstOfMonth(item.start.isEmpty ? DU.ym(Date()) : item.start)
                hasEnd = !item.end.isEmpty
                if hasEnd { endDate = DU.firstOfMonth(item.end) }
            }
        }
    }
}
