import Foundation
import SwiftUI
import Combine

/// Holds the budget, saves it to the phone, and applies every change.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var state: BudgetState
    @Published private(set) var engine: Engine
    @Published var month: String = DU.ym(Date())
    @Published var lastError: String?
    /// Optional shared folder (like iCloud Drive) that keeps your devices in step.
    let sync = SyncFolder()

    private var saveTask: Task<Void, Never>?
    private static let stampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("budget.json")
    }

    init() {
        var loaded = BudgetState()
        if let data = try? Data(contentsOf: Store.fileURL), let s = try? JSONDecoder().decode(BudgetState.self, from: data) {
            loaded = s
        }
        state = loaded
        engine = Engine(loaded)
    }

    var isEmpty: Bool { state.recurring.isEmpty && state.debts.isEmpty }

    // MARK: Saving

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

    /// Saves to this device, then (for your own changes) to the sync folder.
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

    func exportData() -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(state)) ?? Data()
    }

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

    func editCell(_ key: String, _ n: Int, _ f: (inout Cell) -> Void) {
        update { s in
            var m = s.months[key] ?? [:]
            var c = m[String(n)] ?? Cell()
            f(&c)
            m[String(n)] = c
            s.months[key] = m
        }
    }

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

    func setAmount(_ line: Line, _ v: Double) {
        if line.kind == "ex" {
            editCell(line.homeKey, line.home) { c in if let i = c.extras.firstIndex(where: { $0.id == line.id }) { c.extras[i].amount = v } }
            return
        }
        let base = state.recurring.first { $0.id == line.id }?.amount ?? 0
        editOverride(line) { o in o.amount = abs(v - base) < 0.005 ? nil : v }
    }

    func toggleSkip(_ line: Line) {
        editOverride(line) { o in
            let s = !(o.skip ?? false)
            o.skip = s
            if s { o.paid = false; o.aside = false }
        }
    }

    func move(_ line: Line, to c: Check) {
        let home = "\(line.homeKey)|\(line.home)", target = "\(c.key)|\(c.n)"
        editOverride(line) { o in o.moveTo = target == home ? nil : target }
    }

    func setExtraDebt(_ line: Line, _ debtId: String) {
        editOverride(line) { o in o.debtId = debtId; o.debtLocked = true }
    }

    func deleteOneTime(_ line: Line) {
        editCell(line.homeKey, line.home) { c in c.extras.removeAll { $0.id == line.id } }
    }

    func addOneTime(key: String, n: Int, name: String, type: String, amount: Double) {
        editCell(key, n) { c in
            var x = OneTime(); x.name = name; x.type = type; x.amount = amount
            c.extras.append(x)
        }
    }

    func setIncome(key: String, n: Int, _ v: Double?) {
        editCell(key, n) { c in c.income = v }
    }

    /// Adds or updates an extra income item on a paycheck.
    func saveIncomeItem(key: String, n: Int, _ item: IncomeItem) {
        editCell(key, n) { c in
            if let i = c.addIncome.firstIndex(where: { $0.id == item.id }) { c.addIncome[i] = item } else { c.addIncome.append(item) }
        }
    }

    func deleteIncomeItem(key: String, n: Int, id: String) {
        editCell(key, n) { c in c.addIncome.removeAll { $0.id == id } }
    }

    // MARK: Purchases

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

    func setExtraWhen(_ w: String) {
        update { s in
            s.extraWhen = w
            if let i = s.recurring.firstIndex(where: { $0.extraLine }) { s.recurring[i].when = w }
        }
    }

    func settings(_ f: (inout BudgetSettings) -> Void) { update { f(&$0.settings) } }
}
