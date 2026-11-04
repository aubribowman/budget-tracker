import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage(Zoom.key) private var zoom = 1.0
    @AppStorage(Notifier.enabledKey) private var remindersOn = false
    @AppStorage(Notifier.hourKey) private var reminderHour = 9
    @State private var importing = false
    @State private var pickingFolder = false
    @State private var foundSync: BudgetState?
    @State private var exportURL: URL?
    @State private var importedOK = false
    @Environment(\.dismiss) private var dismiss
    @State private var bankImport = false
    @AppStorage(AppLock.enabledKey) private var lockOn = false
    /// Show a Done button when opened as a sheet from Home.
    var showsDone = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Pay schedule") {
                    NavigationLink("Paydays and take-home") { ScheduleView() }
                    NavigationLink("Recurring bills and spending") { RecurringListView() }
                }

                Section {
                    Toggle("Bill and payday reminders", isOn: $remindersOn)
                        .onChange(of: remindersOn) { _, on in
                            Task {
                                if on { remindersOn = await Notifier.requestPermission() }
                                await Notifier.reschedule(store.engine)
                            }
                        }
                    if remindersOn {
                        Picker("Remind me at", selection: $reminderHour) {
                            ForEach(6..<22, id: \.self) { h in Text(hourLabel(h)).tag(h) }
                        }
                        .onChange(of: reminderHour) { _, _ in Task { await Notifier.reschedule(store.engine) } }
                    }
                } header: { Text("Reminders") } footer: {
                    Text("A heads-up the day before each unpaid bill is due, and on payday with what to pay from that check.")
                }

                Section {
                    Button { bankImport = true } label: { Label("Import from bank (CSV)", systemImage: "building.columns") }
                        .disabled(store.isEmpty)
                } header: { Text("Bank transactions") } footer: {
                    Text(store.isEmpty
                         ? "Set up your budget or import a backup first, so transactions have somewhere to go."
                         : "Adds purchases and marks bills paid from a file you download from your bank. Your choices are remembered for next time.")
                }

                SyncSection(sync: store.sync, choose: { pickingFolder = true; importing = true }, found: $foundSync)

                Section {
                    Button { importing = true } label: { Label("Import a backup", systemImage: "square.and.arrow.down") }
                    if let url = exportURL {
                        ShareLink(item: url) { Label("Share backup file", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { exportURL = writeBackup() } label: { Label("Create a backup", systemImage: "square.and.arrow.up") }
                    }
                } header: { Text("Your data") } footer: {
                    Text("Backups use the same file as the web app, so you can move your plan between them. To bring your plan over, use Download a backup in the web app’s Setup tab, save it to Files, then import it here.")
                }

                Section {
                    Toggle("Lock with \(AppLock.methodName)", isOn: Binding(
                        get: { lockOn },
                        set: { on in
                            // Confirm it works before turning the lock on, so you can't lock yourself out.
                            if on {
                                Task { if await AppLock.authenticate(reason: "Turn on the app lock") { lockOn = true } }
                            } else { lockOn = false }
                        }))
                    .disabled(!AppLock.available && !lockOn)
                } header: { Text("Privacy") } footer: {
                    Text(AppLock.available
                         ? "Asks for \(AppLock.methodName) each time you come back to the app, and hides your balances in the app switcher."
                         : "Set up Face ID or a passcode in the Settings app to use this.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Match my device").tag("auto"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    #if os(macOS)
                    Picker("Zoom", selection: $zoom) {
                        ForEach(Zoom.levels, id: \.self) { Text(Zoom.label($0)).tag($0) }
                    }
                    #endif
                }
            }
            .navigationTitle("Setup")
            .sheet(isPresented: $bankImport) { BankImportView().macSheet() }
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: pickingFolder ? [.folder] : [.json, .data]) { result in
                let forSync = pickingFolder
                pickingFolder = false
                guard case .success(let url) = result else { return }
                if forSync { connectSync(url); return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), store.importBackup(data) { importedOK = true }
            }
            .alert("Backup imported", isPresented: $importedOK) { Button("OK") {} } message: {
                Text("Your plan is loaded. Check the Paychecks tab.")
            }
        }
    }

    /// Starts syncing with the picked folder. If your other device already put a budget
    /// there, ask which copy to keep; otherwise start the folder with this device's.
    func connectSync(_ url: URL) {
        let existing = store.connectSync(url)
        if let existing, !(existing.recurring.isEmpty && existing.debts.isEmpty) {
            foundSync = existing
        } else {
            Task { await store.pushThisDevice() }
        }
    }

    func hourLabel(_ h: Int) -> String { h == 12 ? "12 PM" : h > 12 ? "\(h - 12) PM" : "\(h) AM" }

    func writeBackup() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paycheck-plan-backup-\(DU.iso(Date())).json")
        do { try store.exportData().write(to: url); return url } catch { store.lastError = error.localizedDescription; return nil }
    }
}

// MARK: - Pay schedule

struct ScheduleView: View {
    @EnvironmentObject var store: Store

    func bind<T>(_ kp: WritableKeyPath<BudgetSettings, T>) -> Binding<T> {
        Binding(get: { store.state.settings[keyPath: kp] }, set: { v in store.settings { $0[keyPath: kp] = v } })
    }
    func dateBind(_ kp: WritableKeyPath<BudgetSettings, String>) -> Binding<Date> {
        Binding(get: { DU.parseISO(store.state.settings[keyPath: kp]) ?? Date() },
                set: { v in store.settings { $0[keyPath: kp] = DU.iso(v) } })
    }
    func monthBind(_ kp: WritableKeyPath<BudgetSettings, String>) -> Binding<Date> {
        Binding(get: { DU.firstOfMonth(store.state.settings[keyPath: kp].isEmpty ? DU.ym(Date()) : store.state.settings[keyPath: kp]) },
                set: { v in store.settings { $0[keyPath: kp] = DU.ym(v) } })
    }
    func moneyBind(_ kp: WritableKeyPath<BudgetSettings, Double>) -> Binding<String> {
        Binding(get: { String(format: "%.2f", store.state.settings[keyPath: kp]) },
                set: { v in if let d = Double(v) { store.settings { $0[keyPath: kp] = d } } })
    }

    var body: some View {
        let s = store.state.settings
        Form {
            Section {
                Picker("How you’re paid", selection: bind(\.mode)) {
                    Text("Semi-monthly").tag("semi"); Text("Biweekly").tag("biweekly"); Text("Biweekly, then semi-monthly").tag("switch")
                }
                DatePicker("Budget starts", selection: monthBind(\.startMonth), displayedComponents: .date)
            } footer: { Text("Budget starts uses the month of the date you pick.") }

            if s.mode != "semi" {
                Section("Biweekly") {
                    DatePicker("Any recent payday", selection: dateBind(\.bwAnchor), displayedComponents: .date)
                    HStack { Text("Take-home per check"); Spacer(); TextField("0.00", text: moneyBind(\.bwPay)).decimalPad().multilineTextAlignment(.trailing) }
                    if s.mode == "switch" {
                        DatePicker("Last biweekly payday", selection: dateBind(\.bwEnd), displayedComponents: .date)
                        DatePicker("Semi-monthly starts", selection: monthBind(\.switchMonth), displayedComponents: .date)
                    }
                }
            }
            if s.mode != "biweekly" {
                Section("Semi-monthly") {
                    Picker("First payday", selection: bind(\.payDay1)) { ForEach(1...28, id: \.self) { Text(DU.ordinal($0)).tag($0) } }
                    Picker("Second payday", selection: bind(\.payDay2)) {
                        ForEach(1...28, id: \.self) { Text(DU.ordinal($0)).tag(String($0)) }
                        Text("Last day").tag("last")
                    }
                    Picker("Weekend paydays", selection: bind(\.weekend)) {
                        Text("Friday before").tag("friday"); Text("Monday after").tag("monday"); Text("That day").tag("none")
                    }
                    HStack { Text("Take-home per check"); Spacer(); TextField("0.00", text: moneyBind(\.pay)).decimalPad().multilineTextAlignment(.trailing) }
                }
            }
            Section {
                Picker("Each paycheck pays for", selection: bind(\.payAhead)) {
                    Text("Bills due before next payday").tag(0)
                    Text("One pay period ahead").tag(1)
                    Text("Two pay periods ahead").tag(2)
                }
                Toggle("Carry leftovers to the next check", isOn: bind(\.rollover))
            } header: { Text("Paying ahead") } footer: {
                Text("Bills set to “Every check” or pinned to a check don’t shift.")
            }
        }
        .navigationTitle("Paydays")
        .inlineTitle()
    }
}

// MARK: - Recurring items

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
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).foregroundStyle(.primary)
                                    Text(summary(r)).font(.caption).foregroundStyle(.secondary)
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
