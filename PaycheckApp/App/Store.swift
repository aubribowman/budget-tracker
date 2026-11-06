import Foundation
import SwiftUI
import Combine

/// Holds the budget, saves it to the phone, and applies every change.
///
/// The one rule: screens never change `state` directly. Every change goes through
/// `update` (or a helper below that calls it), which stamps `savedAt`, makes a new
/// `Engine` so every number is worked out fresh, and saves a moment later.
/// Screens read data from `state` and calculated numbers from `engine`.
///
/// The Store is created once in PaycheckApp.swift and passed to every screen as an
/// `@EnvironmentObject`. Bank import helpers are in Store+Import.swift.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var state: BudgetState
    @Published private(set) var engine: Engine
    @Published var month: String = DU.ym(Date())   // month shown on Paychecks, Purchases and Month
    @Published var lastError: String?               // shown as an alert by RootView
    /// Optional shared folder (like iCloud Drive) that keeps your devices in step.
    let sync = SyncFolder()

    private var saveTask: Task<Void, Never>?
    private static let stampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    /// This device's copy: Application Support/budget.json.
    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("budget.json")
    }

    /// Loads this device's copy, or starts empty if there isn't one or it can't be read.
    init() {
        var loaded = BudgetState()
        if let data = try? Data(contentsOf: Store.fileURL), let s = try? JSONDecoder().decode(BudgetState.self, from: data) {
            loaded = s
        }
        state = loaded
        engine = Engine(loaded)
    }

    /// Nothing set up yet, so screens can show a getting-started message.
    var isEmpty: Bool { state.recurring.isEmpty && state.debts.isEmpty }

    // MARK: Saving

    /// Applies a change to the budget. Everything that edits the budget comes through here.
    func update(_ change: (inout BudgetState) -> Void) {
        var s = state
        change(&s)
        s.savedAt = Store.stampFormatter.string(from: Date())
        state = s
        engine = Engine(s)
        scheduleSave(push: true)
    }

    /// Recomputes "today"-based numbers (autopay, what's due) without counting as a change,
    /// so just opening the app doesn't make this device's copy look newest to sync.
    func refresh() { engine = Engine(state) }

    /// Saves to this device, then (for your own changes) to the sync folder. Waits 0.4
    /// seconds first, so typing or quick taps turn into one save. Also refreshes the
    /// widget and reminders.
    private func scheduleSave(push: Bool) {
        saveTask?.cancel()
        let snapshot = state
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                try enc.encode(snapshot).write(to: Store.fileURL, options: .atomic)
            } catch {
                self.lastError = "Couldn’t save: \(error.localizedDescription)"
            }
            WidgetSync.write(self.engine, goals: snapshot.goals)
            if push { await self.sync.push(snapshot) }
            await Notifier.reschedule(self.engine)
        }
    }

    // MARK: Sync

    /// Brings in the other device's changes if they're newer, or sends ours if ours are.
    func syncNow() async {
        guard sync.isOn else { return }
        if let remote = await sync.pull() {
            if remote.savedDate > state.savedDate { useSynced(remote) }
            else if state.savedDate > remote.savedDate { await sync.push(state) }
        } else if sync.problem == nil {
            await sync.push(state)      // empty folder: start it with this device's budget
        }
    }

    /// Replaces this device's budget with the copy from the sync folder.
    func useSynced(_ s: BudgetState) {
        state = s
        engine = Engine(s)
        scheduleSave(push: false)
    }

    /// Starts syncing with a folder. Returns the budget already there, if any, so you can
    /// choose which copy to keep.
    func connectSync(_ url: URL) -> BudgetState? {
        do { return try sync.connect(url) }
        catch { sync.problem = "Couldn’t use that folder: \(error.localizedDescription)"; return nil }
    }

    /// Makes this device's budget the one in the sync folder.
    func pushThisDevice() async { await sync.push(state) }

    // MARK: Backup

    /// The whole budget as a backup file, in the web app's format.
    func exportData() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(state)) ?? Data()
    }

    /// Replaces the budget with a backup file. Returns false (and sets `lastError`) if
    /// the file isn't a Paycheck Plan backup.
    @discardableResult
    func importBackup(_ data: Data) -> Bool {
        guard BudgetState.looksValid(data), let s = try? JSONDecoder().decode(BudgetState.self, from: data) else {
            lastError = "That file isn’t a Paycheck Plan backup."
            return false
        }
        update { $0 = s }
        month = DU.ym(Date())
        return true
    }

    // MARK: Paycheck cells

    /// Changes one paycheck's saved data, creating it if needed.
    func editCell(_ key: String, _ n: Int, _ f: (inout Cell) -> Void) {
        update { s in
            var m = s.months[key] ?? [:]
            var c = m[String(n)] ?? Cell()
            f(&c)
            m[String(n)] = c
            s.months[key] = m
        }
    }

    /// Changes a recurring line's override on the paycheck it belongs to (its home paycheck,
    /// even if it's shown on another one after a move).
    func editOverride(_ line: Line, _ f: @escaping (inout Override) -> Void) {
        editCell(line.homeKey, line.home) { c in
            var o = c.ov[line.id] ?? Override()
            f(&o)
            c.ov[line.id] = o
        }
    }

    /// Not paid → set aside → paid → not paid.
    func cycleStatus(_ line: Line) {
        let next = line.paid ? "unpaid" : line.aside ? "paid" : "aside"
        setStatus(line, next)
    }

    /// Sets a line to "unpaid", "aside" or "paid". When the extra debt line is marked
    /// paid, it saves which debt and amount it went to, so later changes to the plan
    /// don't rewrite what you already paid.
    func setStatus(_ line: Line, _ status: String) {
        if line.kind == "ex" {
            editCell(line.homeKey, line.home) { c in
                if let i = c.extras.firstIndex(where: { $0.id == line.id }) {
                    c.extras[i].paid = status == "paid"
                    c.extras[i].aside = status == "aside"
                }
            }
            return
        }
        let focus = engine.focusDebtId()
        let extraAmt = engine.perCheckExtra(line.homeKey)
        editOverride(line) { o in
            o.paid = status == "paid"
            o.aside = status == "aside"
            if line.isExtraLine {
                if status == "paid" {
                    if o.debtId == nil { o.debtId = focus }
                    if o.amount == nil { o.amount = extraAmt }
                } else if o.debtLocked != true { o.debtId = nil }
            }
        }
    }

    /// Changes the amount on this paycheck only. Setting it back to the usual amount
    /// clears the override.
    func setAmount(_ line: Line, _ v: Double) {
        if line.kind == "ex" {
            if isSavingsUse(key: line.homeKey, n: line.home, id: line.id) {
                update { $0.setSavingsUseAmount(key: line.homeKey, n: line.home, id: line.id, to: v) }
                return
            }
            editCell(line.homeKey, line.home) { c in if let i = c.extras.firstIndex(where: { $0.id == line.id }) { c.extras[i].amount = v } }
            return
        }
        let base = state.recurring.first { $0.id == line.id }?.amount ?? 0
        editOverride(line) { o in o.amount = abs(v - base) < 0.005 ? nil : v }
    }

    /// Skips a recurring line on this paycheck, or brings it back.
    func toggleSkip(_ line: Line) {
        editOverride(line) { o in
            let s = !(o.skip ?? false)
            o.skip = s
            if s { o.paid = false; o.aside = false }
        }
    }

    /// Shows a recurring line on another paycheck. Moving it back home clears the move.
    func move(_ line: Line, to c: Check) {
        let home = "\(line.homeKey)|\(line.home)", target = "\(c.key)|\(c.n)"
        editOverride(line) { o in o.moveTo = target == home ? nil : target }
    }

    /// Points this paycheck's extra payment at a specific debt, and keeps it there.
    func setExtraDebt(_ line: Line, _ debtId: String) {
        editOverride(line) { o in o.debtId = debtId; o.debtLocked = true }
    }

    /// Deletes a one-time item. If it was paid for with savings, the matching income goes
    /// too and the money goes back on the goal.
    func deleteOneTime(_ line: Line) {
        if isSavingsUse(key: line.homeKey, n: line.home, id: line.id) {
            update { $0.removeSavingsUse(key: line.homeKey, n: line.home, id: line.id) }
            return
        }
        editCell(line.homeKey, line.home) { c in c.extras.removeAll { $0.id == line.id } }
    }

    func addOneTime(key: String, n: Int, name: String, type: String, amount: Double) {
        editCell(key, n) { c in
            var x = OneTime(); x.name = name; x.type = type; x.amount = amount
            c.extras.append(x)
        }
    }

    /// Sets this paycheck's take-home. nil goes back to the default pay.
    func setIncome(key: String, n: Int, _ v: Double?) {
        editCell(key, n) { c in c.income = v }
    }

    /// Adds or updates an extra income item on a paycheck. For money taken from savings, a new
    /// amount also changes the spending it paid for and the goal.
    func saveIncomeItem(key: String, n: Int, _ item: IncomeItem) {
        if isSavingsUse(key: key, n: n, id: item.id) {
            update { s in
                s.setSavingsUseAmount(key: key, n: n, id: item.id, to: item.amount)
                if let i = s.months[key]?[String(n)]?.addIncome.firstIndex(where: { $0.id == item.id }) {
                    s.months[key]?[String(n)]?.addIncome[i].name = item.name
                }
            }
            return
        }
        editCell(key, n) { c in
            if let i = c.addIncome.firstIndex(where: { $0.id == item.id }) { c.addIncome[i] = item } else { c.addIncome.append(item) }
        }
    }

    /// Deletes an extra income item. For money taken from savings, the spending it paid for
    /// goes too and the money goes back on the goal.
    func deleteIncomeItem(key: String, n: Int, id: String) {
        if isSavingsUse(key: key, n: n, id: id) {
            update { $0.removeSavingsUse(key: key, n: n, id: id) }
            return
        }
        editCell(key, n) { c in c.addIncome.removeAll { $0.id == id } }
    }

    // MARK: Using savings

    /// Spends money from a savings goal on a paycheck. See BudgetState+Savings.swift.
    func useSavings(goalId: String, amount: Double, for name: String, type: String, on check: Check) {
        update { $0.useSavings(goalId: goalId, amount: amount, for: name, type: type, key: check.key, n: check.n) }
    }

    /// True if this income item or one-time item is part of money taken from savings.
    func isSavingsUse(key: String, n: Int, id: String) -> Bool {
        state.savingsUseId(in: engine.cell(key, n), id: id) != nil
    }

    // MARK: Purchases

    /// Logs a purchase on the paycheck its date falls in.
    /// Returns an error message if the date is before the budget starts.
    func addPurchase(date: Date, note: String, amount: Double, recId: String) -> String? {
        guard let pc = engine.periodCheck(DU.startOfDay(date)) else {
            return "\(DU.short(date)) is before your budget starts (\(DU.monthLabel(state.settings.startMonth)))."
        }
        editCell(pc.key, pc.n) { c in
            var b = Buy(); b.amt = r2(amount); b.note = note; b.date = DU.iso(date)
            c.buys[recId, default: []].append(b)
        }
        return nil
    }

    func deletePurchase(key: String, n: Int, recId: String, buyId: String) {
        editCell(key, n) { c in c.buys[recId]?.removeAll { $0.id == buyId } }
    }

    func movePurchase(key: String, n: Int, from: String, to: String, buyId: String) {
        editCell(key, n) { c in
            guard var src = c.buys[from], let i = src.firstIndex(where: { $0.id == buyId }) else { return }
            let b = src.remove(at: i)
            c.buys[from] = src
            c.buys[to, default: []].append(b)
        }
    }

    // MARK: Setup

    // The save functions add the item if its id is new, or replace it if not.
    // Deleting a debt or goal also unlinks any recurring items that pointed at it.

    func saveRecurring(_ r: Recurring) {
        update { s in
            if let i = s.recurring.firstIndex(where: { $0.id == r.id }) { s.recurring[i] = r } else { s.recurring.append(r) }
        }
    }
    func deleteRecurring(_ id: String) { update { $0.recurring.removeAll { $0.id == id } } }

    func saveDebt(_ d: Debt) {
        update { s in
            if let i = s.debts.firstIndex(where: { $0.id == d.id }) { s.debts[i] = d } else { s.debts.append(d) }
        }
    }
    func deleteDebt(_ id: String) {
        update { s in
            s.debts.removeAll { $0.id == id }
            for i in s.recurring.indices where s.recurring[i].debtId == id { s.recurring[i].debtId = "" }
        }
    }

    func saveLoan(_ l: Loan) {
        update { s in
            if let i = s.loans.firstIndex(where: { $0.id == l.id }) { s.loans[i] = l } else { s.loans.append(l) }
        }
        syncLoanPlanLine()
    }
    func deleteLoan(_ id: String) {
        update { $0.loans.removeAll { $0.id == id } }
        syncLoanPlanLine()
    }

    /// Adds or removes the "Student loans" line on paychecks.
    func setLoanPlanLine(on: Bool) {
        update { s in
            if on {
                guard !s.recurring.contains(where: { $0.loanPlan }) else { return }
                var r = Recurring()
                r.name = "Student loans"; r.type = "debt"; r.when = "1"; r.loanPlan = true
                s.recurring.append(r)
            } else {
                s.recurring.removeAll { $0.loanPlan }
            }
        }
        syncLoanPlanLine()
    }

    /// Sets the monthly student loan plan and when it starts.
    func setLoanPlan(payment: Double, start: String) {
        update { s in s.loanPlan.payment = max(0, r2(payment)); s.loanPlan.start = start }
        syncLoanPlanLine()
    }

    /// Keeps the paycheck line's amount and start month in step with the plan.
    private func syncLoanPlanLine() {
        let sim = engine.simulateLoans()
        let firstRepay = state.loans.map { engine.repayMonth($0) }.min() ?? DU.ym(Date())
        let start = state.loanPlan.start.count >= 7 ? String(state.loanPlan.start.prefix(7)) : firstRepay
        update { s in
            guard let i = s.recurring.firstIndex(where: { $0.loanPlan }) else { return }
            if s.loans.isEmpty { s.recurring.remove(at: i); return }
            s.recurring[i].amount = sim.monthly
            s.recurring[i].start = start
        }
    }

    /// Puts a one-time windfall straight onto balances: debts and loans go down,
    /// goals go up, each starting fresh from today.
    func applyWindfall(debts: [String: Double], loans: [String: Double], goals: [String: Double]) {
        let e = engine
        let loanBal = e.loanBalances()
        let today = DU.iso(DU.today)
        update { s in
            for i in s.debts.indices {
                guard let a = debts[s.debts[i].id], a > 0.004 else { continue }
                s.debts[i].balance = max(0, r2(e.curBal(s.debts[i]) - a)); s.debts[i].asOf = today
            }
            for i in s.loans.indices {
                guard let a = loans[s.loans[i].id], a > 0.004 else { continue }
                s.loans[i].balance = max(0, r2((loanBal[s.loans[i].id] ?? s.loans[i].balance) - a)); s.loans[i].asOf = today
            }
            for i in s.goals.indices {
                guard let a = goals[s.goals[i].id], a > 0.004 else { continue }
                s.goals[i].balance = r2(e.goalStatus(s.goals[i]).saved + a); s.goals[i].asOf = today
            }
        }
    }

    func saveGoal(_ g: Goal) {
        update { s in
            if let i = s.goals.firstIndex(where: { $0.id == g.id }) { s.goals[i] = g } else { s.goals.append(g) }
        }
    }
    func deleteGoal(_ id: String) {
        update { s in
            s.goals.removeAll { $0.id == id }
            for i in s.recurring.indices where s.recurring[i].goalId == id { s.recurring[i].goalId = "" }
        }
    }

    /// Adds or removes the "Extra → debt" line on paychecks.
    func setExtraLine(on: Bool) {
        update { s in
            if on {
                if !s.recurring.contains(where: { $0.extraLine }) {
                    var r = Recurring()
                    r.name = "Extra debt payment"; r.type = "debt"; r.when = s.extraWhen ?? "1"
                    r.start = DU.ym(Date()); r.extraLine = true
                    s.recurring.append(r)
                }
            } else {
                s.recurring.removeAll { $0.extraLine }
            }
        }
    }

    /// Which paycheck the extra payment goes on: "1", "2" or "each".
    func setExtraWhen(_ w: String) {
        update { s in
            s.extraWhen = w
            if let i = s.recurring.firstIndex(where: { $0.extraLine }) { s.recurring[i].when = w }
        }
    }

    /// Changes settings, e.g. `store.settings { $0.rollover = true }`.
    func settings(_ f: (inout BudgetSettings) -> Void) { update { f(&$0.settings) } }
}
