import SwiftUI
import UniformTypeIdentifiers

/// Setup (the gear on Home): your name, pay schedule, recurring items, reminders, bank
/// import, sync and backups, privacy and appearance. Debts and goals are edited on their own screens.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage(Zoom.key) private var zoom = 1.0
    @AppStorage(Notifier.enabledKey) private var remindersOn = false
    @AppStorage(Notifier.hourKey) private var reminderHour = 9
    @AppStorage(AppExpiry.reminderKey) private var expiryReminderOn = true
    @State private var importing = false
    @State private var pickingFolder = false
    @State private var foundSync: BudgetState?
    @State private var exportURL: URL?
    @State private var importedOK = false
    @Environment(\.dismiss) private var dismiss
    @State private var bankImport = false
    @AppStorage(AppLock.enabledKey) private var lockOn = false
    @State private var firstName = ""
    /// Show a Done button when opened as a sheet from Home.
    var showsDone = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .onSubmit(saveName)
                } header: { Text("You") } footer: {
                    Text("Used to greet you on Home.")
                }

                Section("Pay schedule") {
                    NavigationLink("Paydays and take-home") { ScheduleView() }
                    NavigationLink("Recurring bills and spending") { RecurringListView() }
                }

                Section {
                    Toggle("Bill and payday reminders", isOn: $remindersOn)
                        .onChange(of: remindersOn) { _, on in
                            // Turning on asks iOS for permission; if it's denied, the switch goes back off.
                            // Either way, rebuild the scheduled reminders to match.
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
                    // Only on installs that expire (run from Xcode with a free Apple ID).
                    if let expires = AppExpiry.date {
                        Toggle(isOn: $expiryReminderOn) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remind me to reinstall")
                                Text("This copy stops opening \(AppExpiry.label(expires)).")
                                    .font(.ui(.caption)).foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: expiryReminderOn) { _, on in
                            Task {
                                if on { expiryReminderOn = await Notifier.requestPermission() }
                                await Notifier.reschedule(store.engine)
                            }
                        }
                    }
                } header: { Text("Reminders") } footer: {
                    Text("A heads-up the day before each unpaid bill is due, and on payday with what to pay from that check."
                         + (AppExpiry.date == nil ? "" : " The reinstall reminder comes two days and one day before the app expires."))
                }

                Section {
                    Button { bankImport = true } label: { Label("Import from bank (CSV)", systemImage: "building.columns") }
                        .disabled(store.isEmpty)
                } header: { Text("Bank transactions") } footer: {
                    Text(store.isEmpty
                         ? "Set up your budget or import a backup first, so transactions have somewhere to go."
                         : "Adds purchases and marks bills paid from a file you download from your bank. Your choices are remembered for next time.")
                }

                // Sync folder: its own view (SyncSection.swift).
                SyncSection(sync: store.sync, choose: { pickingFolder = true; importing = true }, found: $foundSync)

                Section {
                    Button { importing = true } label: { Label("Import a backup", systemImage: "square.and.arrow.down") }
                    if let url = exportURL {
                        ShareLink(item: url) { Label("Share backup file", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { exportURL = writeBackup() } label: { Label("Create a backup", systemImage: "square.and.arrow.up") }
                    }
                } header: { Text("Your data") } footer: {
                    Text("A backup is one file with your whole plan. Save it somewhere safe, or import it on another device to pick up where you left off.")
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
            .onAppear { firstName = store.state.settings.firstName }
            .onDisappear(perform: saveName)
            .sheet(isPresented: $bankImport) { BankImportView().macSheet() }
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            // One file picker for two jobs: picking a sync folder (`pickingFolder`) or a backup file.
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

    /// Saves the first name (used in Home's greeting) if it changed.
    func saveName() {
        let n = firstName.trimmingCharacters(in: .whitespaces)
        if n != store.state.settings.firstName { store.settings { $0.firstName = n } }
    }

    /// 24-hour number to "9 AM" / "5 PM", for the reminder time picker.
    func hourLabel(_ h: Int) -> String { h == 12 ? "12 PM" : h > 12 ? "\(h - 12) PM" : "\(h) AM" }

    /// Writes a backup file to a temporary folder for the share sheet. The file uses the
    /// web app's format, so it can be imported there too.
    func writeBackup() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paycheck-plan-backup-\(DU.iso(Date())).json")
        do { try store.exportData().write(to: url); return url } catch { store.lastError = error.localizedDescription; return nil }
    }
}
