import Foundation

// The budget data. These types match the web app's backup file (Paycheck Plan.json)
// field for field, so the same file can move between the web app, iPhone and Mac.
//
// Rules for changing them:
// - Every type decodes by hand with defaults, so an older or newer file still loads.
//   A missing or oddly typed field falls back to its default instead of failing.
// - Keep field names the same as the web app's. Renaming one breaks backups and sync.
// - Months are "yyyy-MM" text and dates are "yyyy-MM-dd" text (see DateUtil.swift),
//   which also sort correctly as plain strings.
// - IDs are a one-letter prefix plus 7 random characters (r = recurring, x = one-time,
//   b = purchase, i = extra income, d = debt, g = goal, l = loan).

// MARK: - Flexible decoding
// The web app stores some values as either numbers or strings ("15" vs 15, "last").
// These helpers read whichever shape is there so a backup from the web app always loads.

extension KeyedDecodingContainer {
    func str(_ k: Key) -> String? {
        if let v = try? decodeIfPresent(String.self, forKey: k) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: k) { return String(v) }
        if let v = try? decodeIfPresent(Double.self, forKey: k) {
            return v == v.rounded() ? String(Int(v)) : String(v)
        }
        if let v = try? decodeIfPresent(Bool.self, forKey: k) { return v ? "true" : "false" }
        return nil
    }
    func dbl(_ k: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: k) { return v }
        if let s = try? decodeIfPresent(String.self, forKey: k), let v = Double(s) { return v }
        return nil
    }
    func int(_ k: Key) -> Int? {
        if let v = dbl(k) { return Int(v) }
        return nil
    }
    func bool(_ k: Key) -> Bool? {
        if let v = try? decodeIfPresent(Bool.self, forKey: k) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: k) { return v != 0 }
        if let v = try? decodeIfPresent(String.self, forKey: k) { return v == "true" || v == "1" }
        return nil
    }
}

// MARK: - BudgetSettings

/// How you're paid and how the plan behaves. Edited in Setup.
struct BudgetSettings: Codable, Equatable {
    var payDay1: Int = 15                 // semi-monthly: day of the first paycheck
    var payDay2: String = "last"          // semi-monthly: "last" or a day number as text
    var weekend: String = "friday"        // payday on a weekend moves to: friday | monday | none
    var pay: Double = 0                   // semi-monthly take-home per check
    var rollover: Bool = false            // carry what's left on one paycheck into the next
    var startMonth: String = DU.ym(Date()) // first month of the plan; earlier months are ignored
    var theme: String = "auto"            // web app only; the native app uses @AppStorage("appearance")
    var mode: String = "semi"             // semi | biweekly | switch (biweekly until switchMonth, then semi)
    var bwAnchor: String = ""             // any biweekly payday, yyyy-MM-dd; the rest are 14 days apart
    var bwPay: Double = 0                 // biweekly take-home per check
    var switchMonth: String = ""          // "switch" mode: first semi-monthly month
    var bwEnd: String = ""                // "switch" mode: last biweekly payday, yyyy-MM-dd
    var payAhead: Int = 0                 // each paycheck covers bills this many paychecks ahead
    var payAheadFrom: String = ""         // pay-ahead starts with paychecks on or after this date
    var payAheadCatchUp: Bool = false     // the first pay-ahead paycheck also covers the bills it skipped over
    var upCollapsed: Bool = false         // the "Coming up" card on Paychecks is folded
    var rollLoans: Bool = true            // paid-off card payments roll into student loans
    var firstName: String = ""            // for the Home greeting

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        payDay1 = c.int(.payDay1) ?? 15
        payDay2 = c.str(.payDay2) ?? "last"
        weekend = c.str(.weekend) ?? "friday"
        pay = c.dbl(.pay) ?? 0
        rollover = c.bool(.rollover) ?? false
        startMonth = c.str(.startMonth) ?? DU.ym(Date())
        theme = c.str(.theme) ?? "auto"
        mode = c.str(.mode) ?? "semi"
        bwAnchor = c.str(.bwAnchor) ?? ""
        bwPay = c.dbl(.bwPay) ?? 0
        switchMonth = c.str(.switchMonth) ?? ""
        bwEnd = c.str(.bwEnd) ?? ""
        payAhead = c.int(.payAhead) ?? 0
        payAheadFrom = c.str(.payAheadFrom) ?? ""
        payAheadCatchUp = c.bool(.payAheadCatchUp) ?? false
        upCollapsed = c.bool(.upCollapsed) ?? false
        rollLoans = c.bool(.rollLoans) ?? true
        firstName = c.str(.firstName) ?? ""
    }
}

// MARK: - Recurring items (bills, subscriptions, spending categories, debt payments, savings)

/// Something that repeats every month (or every few months). The Engine turns each one
/// into a `Line` on the right paycheck. Changes for a single paycheck go in an `Override`.
struct Recurring: Codable, Identifiable, Equatable {
    var id: String = "r" + UUID().uuidString.prefix(7).lowercased()
    var name: String = "New bill"
    var type: String = "bill"             // bill | subscription | expense (spending category) | debt | savings
    var amount: Double = 0                // planned amount each time it comes up
    var when: String = "auto"             // auto (paycheck whose window holds the due date) | 1 | 2 | 3 | each (every paycheck)
    var due: String = ""                  // day of month as text, "" if none
    var every: Int = 1                    // every N months, counted from `start` (or the plan's start month)
    var start: String = ""                // first month, yyyy-MM, "" for no limit
    var end: String = ""                  // last month, yyyy-MM, "" for no limit
    var debtId: String = ""               // debt payments: which Debt marking it paid pays down
    var goalId: String = ""               // savings: which Goal marking it paid adds to
    var autopay: Bool = false             // counts as paid once its due date has passed
    var bucket: String? = nil             // web app only; kept so it survives a round trip
    var loanPlan: Bool = false            // the student loan payment line (left out of card payoff math)
    var extraLine: Bool = false           // the "Extra → debt" line; its amount comes from BudgetState.extra
    var rolledInto: String? = nil         // web app only; kept so it survives a round trip
    var rollDismissed: Bool? = nil        // web app only; kept so it survives a round trip
    var icon: String? = nil               // apps only: SF Symbol name picked in the editor; nil = guess from the name (ItemIcon).
                                          // The web app keeps fields it doesn't know, so this survives a round trip.

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id) ?? "r" + UUID().uuidString.prefix(7).lowercased()
        name = c.str(.name) ?? "Item"
        type = c.str(.type) ?? "bill"
        amount = c.dbl(.amount) ?? 0
        when = c.str(.when) ?? "auto"
        due = c.str(.due) ?? ""
        every = max(1, c.int(.every) ?? 1)
        start = c.str(.start) ?? ""
        end = c.str(.end) ?? ""
        debtId = c.str(.debtId) ?? ""
        goalId = c.str(.goalId) ?? ""
        autopay = c.bool(.autopay) ?? false
        bucket = c.str(.bucket)
        loanPlan = c.bool(.loanPlan) ?? false
        extraLine = c.bool(.extraLine) ?? false
        rolledInto = c.str(.rolledInto)
        rollDismissed = c.bool(.rollDismissed)
        icon = c.str(.icon)
    }

    var dueDay: Int? { Int(due) }
}

// MARK: - Per-paycheck data

/// A change to one recurring item on one paycheck, stored in `Cell.ov` under the item's id.
/// `nil` means "not set", which is different from `false` (for example, autopay only
/// marks a line paid when `paid` is nil).
struct Override: Codable, Equatable {
    var amount: Double? = nil             // amount for this paycheck only
    var paid: Bool? = nil
    var aside: Bool? = nil                // money set aside but not paid yet
    var skip: Bool? = nil                 // skip it this time; not counted in totals
    var moveTo: String? = nil             // show on another paycheck: "2" (same month) or "yyyy-MM|2"
    var debtId: String? = nil             // extra line: which debt this paycheck's extra went to
    var debtLocked: Bool? = nil           // extra line: keep debtId even if the focus debt changes
    var tx: String? = nil                 // bank transaction id that marked it paid (see Store+Import)

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        amount = c.dbl(.amount)
        paid = c.bool(.paid)
        aside = c.bool(.aside)
        skip = c.bool(.skip)
        moveTo = c.str(.moveTo)
        debtId = c.str(.debtId)
        debtLocked = c.bool(.debtLocked)
        tx = c.str(.tx)
    }
}

/// A one-time item added to a single paycheck.
struct OneTime: Codable, Identifiable, Equatable {
    var id: String = "x" + UUID().uuidString.prefix(7).lowercased()
    var name: String = ""
    var type: String = "expense"          // same types as Recurring
    var amount: Double = 0
    var paid: Bool = false
    var aside: Bool? = nil
    var debtId: String? = nil
    var goalId: String? = nil
    var tx: String? = nil

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id) ?? "x" + UUID().uuidString.prefix(7).lowercased()
        name = c.str(.name) ?? ""
        type = c.str(.type) ?? "expense"
        amount = c.dbl(.amount) ?? 0
        paid = c.bool(.paid) ?? false
        aside = c.bool(.aside)
        debtId = c.str(.debtId)
        goalId = c.str(.goalId)
        tx = c.str(.tx)
    }
}

/// A purchase logged against a spending category (a Recurring with type "expense").
struct Buy: Codable, Identifiable, Equatable {
    var id: String = "b" + UUID().uuidString.prefix(7).lowercased()
    var amt: Double = 0
    var note: String = ""
    var date: String = ""                 // yyyy-MM-dd
    var tx: String? = nil                 // bank transaction id if it came from an import

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id) ?? "b" + UUID().uuidString.prefix(7).lowercased()
        amt = c.dbl(.amt) ?? 0
        note = c.str(.note) ?? ""
        date = c.str(.date) ?? ""
        tx = c.str(.tx)
    }
}

/// Money coming in on top of a paycheck, like a side job or a reimbursement.
/// Added to that paycheck's income in `Engine.totals`. The web app doesn't know about
/// this field yet; it keeps it in the file but doesn't count it.
struct IncomeItem: Codable, Identifiable, Equatable {
    var id: String = "i" + UUID().uuidString.prefix(7).lowercased()
    var name: String = ""
    var amount: Double = 0

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id) ?? "i" + UUID().uuidString.prefix(7).lowercased()
        name = c.str(.name) ?? ""
        amount = c.dbl(.amount) ?? 0
    }
}

/// Everything specific to one paycheck. Stored at `BudgetState.months["yyyy-MM"]["1"]`
/// (the paycheck number as text). Most paychecks have no Cell until you change something.
struct Cell: Codable, Equatable {
    var income: Double? = nil             // take-home for this check; nil uses the default pay
    var ov: [String: Override] = [:]      // keyed by Recurring id
    var extras: [OneTime] = []
    var buys: [String: [Buy]] = [:]       // purchases, keyed by spending category (Recurring id)
    var addIncome: [IncomeItem] = []

    enum CodingKeys: String, CodingKey { case income, ov, extras, buys, addIncome }

    init() {}

    // Written by hand so `addIncome` is left out when empty, keeping files tidy for the web app.
    func encode(to en: Encoder) throws {
        var c = en.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(income, forKey: .income)
        try c.encode(ov, forKey: .ov)
        try c.encode(extras, forKey: .extras)
        try c.encode(buys, forKey: .buys)
        if !addIncome.isEmpty { try c.encode(addIncome, forKey: .addIncome) }
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        income = c.dbl(.income)
        ov = (try? c.decodeIfPresent([String: Override].self, forKey: .ov)) ?? [:]
        extras = (try? c.decodeIfPresent([OneTime].self, forKey: .extras)) ?? []
        buys = (try? c.decodeIfPresent([String: [Buy]].self, forKey: .buys)) ?? [:]
        addIncome = (try? c.decodeIfPresent([IncomeItem].self, forKey: .addIncome)) ?? []
    }
}

// MARK: - Debts, goals, student loans

/// A credit card or personal loan. The balance is a snapshot: the current balance is
/// `balance` minus debt payments marked paid after `asOf` (see `Engine.curBal`).
struct Debt: Codable, Identifiable, Equatable {
    var id: String = "d" + UUID().uuidString.prefix(7).lowercased()
    var name: String = "New debt"
    var balance: Double = 0               // balance on the `asOf` date
    var original: Double = 0              // starting balance, for the progress bar
    var apr: Double = 0                   // percent, e.g. 24.99
    var min: Double = 0                   // monthly minimum payment
    var asOf: String = DU.iso(Date())     // yyyy-MM-dd
    var limit: Double? = nil              // credit limit, for utilization

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id) ?? "d" + UUID().uuidString.prefix(7).lowercased()
        name = c.str(.name) ?? "Debt"
        balance = c.dbl(.balance) ?? 0
        original = c.dbl(.original) ?? 0
        apr = c.dbl(.apr) ?? 0
        min = c.dbl(.min) ?? 0
        asOf = c.str(.asOf) ?? DU.iso(Date())
        limit = c.dbl(.limit)
    }
}

/// A savings goal. Like Debt, `balance` is a snapshot on `asOf`; savings lines linked to
/// the goal and marked paid after that date are added on top (see Engine+Goals.swift).
struct Goal: Codable, Identifiable, Equatable {
    var id: String = "g" + UUID().uuidString.prefix(7).lowercased()
    var name: String = "New goal"
    var kind: String = "savings"          // web app only; kept so it survives a round trip
    var target: Double = 0
    var balance: Double = 0
    var asOf: String = DU.iso(Date())
    var due: String = ""                  // optional target date, yyyy-MM-dd

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id) ?? "g" + UUID().uuidString.prefix(7).lowercased()
        name = c.str(.name) ?? "Goal"
        kind = c.str(.kind) ?? "savings"
        target = c.dbl(.target) ?? 0
        balance = c.dbl(.balance) ?? 0
        asOf = c.str(.asOf) ?? DU.iso(Date())
        due = c.str(.due) ?? ""
    }
}

/// A student loan. Kept apart from `Debt` because interest builds up before repayment
/// starts (unless it's subsidized). Math is in Engine+Loans.swift.
struct Loan: Codable, Identifiable, Equatable {
    var id: String = "l" + UUID().uuidString.prefix(7).lowercased()
    var name: String = "Student loan"
    var kind: String = "unsubsidized"     // one of Engine.loanKinds, e.g. subsidized or unsubsidized
    var balance: Double = 0               // balance on the `asOf` date
    var apr: Double = 0                   // percent
    var asOf: String = DU.iso(Date())     // yyyy-MM-dd
    var repayStart: String = ""           // yyyy-MM-dd
    var term: Int = 10                    // years, for the standard payment
    var payment: Double = 0               // your own monthly payment; 0 uses the standard one

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id) ?? "l" + UUID().uuidString.prefix(7).lowercased()
        name = c.str(.name) ?? "Student loan"
        kind = c.str(.kind) ?? "unsubsidized"
        balance = c.dbl(.balance) ?? 0
        apr = c.dbl(.apr) ?? 0
        asOf = c.str(.asOf) ?? DU.iso(Date())
        repayStart = c.str(.repayStart) ?? ""
        term = c.int(.term) ?? 10
        payment = c.dbl(.payment) ?? 0
    }
}

/// One monthly amount for all student loans together, set on the Student loans screen.
struct LoanPlan: Codable, Equatable {
    var payment: Double = 0               // 0 means no plan; each loan uses its own payment
    var start: String = ""                // yyyy-MM

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        payment = c.dbl(.payment) ?? 0
        start = c.str(.start) ?? ""
    }
}

// MARK: - Whole budget

/// The whole budget: exactly what's saved to disk, synced and backed up.
/// The app holds one of these in `Store.state`; screens read numbers from `Store.engine`.
struct BudgetState: Codable, Equatable {
    var version: Int = 1
    var settings = BudgetSettings()
    var recurring: [Recurring] = []
    var months: [String: [String: Cell]] = [:]   // "yyyy-MM" → paycheck number ("1", "2", "3") → Cell
    var debts: [Debt] = []
    var goals: [Goal] = []
    var loans: [Loan] = []
    var loanPlan = LoanPlan()
    var strategy: String = "avalanche"     // avalanche (highest rate first) | snowball (smallest balance first) | target (targetDebt first)
    var extra: Double = 0                  // extra paid toward debt each month
    var targetDebt: String? = nil          // Debt id for the "target" strategy
    var extraWhen: String? = nil           // which paycheck the extra goes on: "1", "2" or "each"
    var importRules: [String: String] = [:] // bank import: store name → where it goes (see ImportTarget.ruleValue)
    var pocketMap: [String: String] = [:]   // bank import: Crew pocket name → spending category id
    var imported: [String: Double] = [:]    // bank import: transaction id → when it was imported (milliseconds since 1970)
    var savedAt: String? = nil             // ISO time of the last save; sync uses it to pick the newer copy

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        version = c.int(.version) ?? 1
        settings = (try? c.decodeIfPresent(BudgetSettings.self, forKey: .settings)) ?? BudgetSettings()
        recurring = (try? c.decodeIfPresent([Recurring].self, forKey: .recurring)) ?? []
        months = (try? c.decodeIfPresent([String: [String: Cell]].self, forKey: .months)) ?? [:]
        debts = (try? c.decodeIfPresent([Debt].self, forKey: .debts)) ?? []
        goals = (try? c.decodeIfPresent([Goal].self, forKey: .goals)) ?? []
        loans = (try? c.decodeIfPresent([Loan].self, forKey: .loans)) ?? []
        loanPlan = (try? c.decodeIfPresent(LoanPlan.self, forKey: .loanPlan)) ?? LoanPlan()
        strategy = c.str(.strategy) ?? "avalanche"
        extra = c.dbl(.extra) ?? 0
        targetDebt = c.str(.targetDebt)
        extraWhen = c.str(.extraWhen)
        importRules = (try? c.decodeIfPresent([String: String].self, forKey: .importRules)) ?? [:]
        pocketMap = (try? c.decodeIfPresent([String: String].self, forKey: .pocketMap)) ?? [:]
        imported = (try? c.decodeIfPresent([String: Double].self, forKey: .imported)) ?? [:]
        savedAt = c.str(.savedAt)
        // Repair month values a browser may have saved in another format.
        if DU.normMonth(settings.startMonth) == nil || settings.startMonth.isEmpty {
            settings.startMonth = DU.ym(Date())
        } else if let m = DU.normMonth(settings.startMonth), !m.isEmpty {
            settings.startMonth = m
        }
    }

    /// A quick check that a file is a Paycheck Plan backup before importing it.
    static func looksValid(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return obj["recurring"] is [Any]
    }
}
