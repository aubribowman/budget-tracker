import Foundation

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

struct BudgetSettings: Codable, Equatable {
    var payDay1: Int = 15
    var payDay2: String = "last"          // "last" or a day number as text
    var weekend: String = "friday"        // friday | monday | none
    var pay: Double = 0                   // semi-monthly take-home per check
    var rollover: Bool = false
    var startMonth: String = DU.ym(Date())
    var theme: String = "auto"
    var mode: String = "semi"             // semi | biweekly | switch
    var bwAnchor: String = ""             // any biweekly payday, yyyy-MM-dd
    var bwPay: Double = 0
    var switchMonth: String = ""
    var bwEnd: String = ""
    var payAhead: Int = 0
    var payAheadFrom: String = ""
    var payAheadCatchUp: Bool = false
    var upCollapsed: Bool = false
    var rollLoans: Bool = true

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
    }
}

// MARK: - Recurring items (bills, subscriptions, spending categories, debt payments, savings)

struct Recurring: Codable, Identifiable, Equatable {
    var id: String = "r" + UUID().uuidString.prefix(7).lowercased()
    var name: String = "New bill"
    var type: String = "bill"             // bill | subscription | expense | debt | savings
    var amount: Double = 0
    var when: String = "auto"             // auto | 1 | 2 | each
    var due: String = ""                  // day of month as text, "" if none
    var every: Int = 1
    var start: String = ""
    var end: String = ""
    var debtId: String = ""
    var goalId: String = ""
    var autopay: Bool = false
    var bucket: String? = nil
    var loanPlan: Bool = false
    var extraLine: Bool = false
    var rolledInto: String? = nil
    var rollDismissed: Bool? = nil

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
    }

    var dueDay: Int? { Int(due) }
}

// MARK: - Per-paycheck data

struct Override: Codable, Equatable {
    var amount: Double? = nil
    var paid: Bool? = nil
    var aside: Bool? = nil
    var skip: Bool? = nil
    var moveTo: String? = nil
    var debtId: String? = nil
    var debtLocked: Bool? = nil
    var tx: String? = nil

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

struct OneTime: Codable, Identifiable, Equatable {
    var id: String = "x" + UUID().uuidString.prefix(7).lowercased()
    var name: String = ""
    var type: String = "expense"
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

struct Buy: Codable, Identifiable, Equatable {
    var id: String = "b" + UUID().uuidString.prefix(7).lowercased()
    var amt: Double = 0
    var note: String = ""
    var date: String = ""
    var tx: String? = nil

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
/// The web app keeps it in the file but doesn't count it yet.
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

struct Cell: Codable, Equatable {
    var income: Double? = nil
    var ov: [String: Override] = [:]
    var extras: [OneTime] = []
    var buys: [String: [Buy]] = [:]
    var addIncome: [IncomeItem] = []

    enum CodingKeys: String, CodingKey { case income, ov, extras, buys, addIncome }

    init() {}

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

struct Debt: Codable, Identifiable, Equatable {
    var id: String = "d" + UUID().uuidString.prefix(7).lowercased()
    var name: String = "New debt"
    var balance: Double = 0
    var original: Double = 0
    var apr: Double = 0
    var min: Double = 0
    var asOf: String = DU.iso(Date())
    var limit: Double? = nil

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

struct Goal: Codable, Identifiable, Equatable {
    var id: String = "g" + UUID().uuidString.prefix(7).lowercased()
    var name: String = "New goal"
    var kind: String = "savings"
    var target: Double = 0
    var balance: Double = 0
    var asOf: String = DU.iso(Date())
    var due: String = ""

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

struct Loan: Codable, Identifiable, Equatable {
    var id: String = "l" + UUID().uuidString.prefix(7).lowercased()
    var name: String = "Student loan"
    var kind: String = "unsubsidized"
    var balance: Double = 0
    var apr: Double = 0
    var asOf: String = DU.iso(Date())
    var repayStart: String = ""
    var term: Int = 10
    var payment: Double = 0

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

struct LoanPlan: Codable, Equatable {
    var payment: Double = 0
    var start: String = ""

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        payment = c.dbl(.payment) ?? 0
        start = c.str(.start) ?? ""
    }
}

// MARK: - Whole budget

struct BudgetState: Codable, Equatable {
    var version: Int = 1
    var settings = BudgetSettings()
    var recurring: [Recurring] = []
    var months: [String: [String: Cell]] = [:]
    var debts: [Debt] = []
    var goals: [Goal] = []
    var loans: [Loan] = []
    var loanPlan = LoanPlan()
    var strategy: String = "avalanche"     // avalanche | snowball | target
    var extra: Double = 0
    var targetDebt: String? = nil
    var extraWhen: String? = nil
    var importRules: [String: String] = [:]
    var pocketMap: [String: String] = [:]
    var imported: [String: Double] = [:]
    var savedAt: String? = nil

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

    static func looksValid(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return obj["recurring"] is [Any]
    }
}
