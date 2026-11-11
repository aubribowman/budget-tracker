import Foundation

// Investment accounts (401(k), IRA, brokerage) and what's in them. App only: the web app
// keeps these fields in the file but doesn't show them.
//
// An account's holdings are a snapshot from the last import or edit (`asOf`). Savings
// lines on your paychecks can be linked to an account the same way they link to a goal
// (`Recurring.goalId` holds the account's id), and ones marked paid after the snapshot are
// added on top as cash until the next import (see Engine+Invest.swift).

/// One position in an account: a fund, a stock, or cash.
struct Holding: Codable, Identifiable, Equatable {
    var id: String = "h" + UUID().uuidString.prefix(7).lowercased()
    var symbol: String = ""               // FXAIX, AAPL; "" for cash with no symbol
    var name: String = ""                 // the fund or company name
    var shares: Double = 0
    var price: Double = 0                 // price per share at the snapshot
    var value: Double = 0                 // what it was worth at the snapshot
    var cost: Double? = nil               // what you paid in total (cost basis), if known
    var cash: Bool = false                // a money market or cash position
    var priceAt: String? = nil            // trading day of `price` when it came from a daily update (PriceService), yyyy-MM-dd

    /// Gain or loss against what you paid, or nil when the cost isn't known.
    var gain: Double? { cost.map { value - $0 } }

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id) ?? "h" + UUID().uuidString.prefix(7).lowercased()
        symbol = c.str(.symbol) ?? ""
        name = c.str(.name) ?? ""
        shares = c.dbl(.shares) ?? 0
        price = c.dbl(.price) ?? 0
        value = c.dbl(.value) ?? 0
        cost = c.dbl(.cost)
        cash = c.bool(.cash) ?? false
        priceAt = c.str(.priceAt)
    }
}

/// An investment account and its holdings.
struct InvestAccount: Codable, Identifiable, Equatable {
    var id: String = "a" + UUID().uuidString.prefix(7).lowercased()
    var name: String = "New account"
    var number: String = ""               // account number from the import, used to match the next one
    var holdings: [Holding] = []
    var asOf: String = DU.iso(Date())     // when the holdings were last imported or edited, yyyy-MM-dd
    var asOfAt: String? = nil             // the same moment as a time stamp (DU.stamp)

    /// Total of the holdings at the snapshot (contributions since are added by the Engine).
    var holdingsValue: Double { holdings.reduce(0) { $0 + $1.value } }
    /// Total cost of the holdings whose cost is known.
    var knownCost: Double { holdings.compactMap(\.cost).reduce(0, +) }
    /// Value of just the holdings whose cost is known, to compare with `knownCost`.
    var valueWithCost: Double { holdings.filter { $0.cost != nil }.reduce(0) { $0 + $1.value } }
    /// "Individual ••5678" style label: the last 4 of the number, if there is one.
    var numberTail: String { number.count > 4 ? "••" + number.suffix(4) : number }

    init() {}

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.str(.id) ?? "a" + UUID().uuidString.prefix(7).lowercased()
        name = c.str(.name) ?? "Account"
        number = c.str(.number) ?? ""
        holdings = (try? c.decodeIfPresent([Holding].self, forKey: .holdings)) ?? []
        asOf = c.str(.asOf) ?? DU.iso(Date())
        asOfAt = c.str(.asOfAt)
    }
}

/// Totals on one day, for the value-over-time chart and "since last time" on Home.
/// Saved whenever investments are imported or edited; one per day (the latest wins).
struct ValuePoint: Codable, Equatable, Identifiable {
    var date: String = DU.iso(Date())     // yyyy-MM-dd
    var invest: Double = 0                // all investment accounts
    var net: Double = 0                   // net worth: savings + investments − debts and loans
    var id: String { date }

    init() {}
    init(date: String, invest: Double, net: Double) { self.date = date; self.invest = invest; self.net = net }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        date = c.str(.date) ?? ""
        invest = c.dbl(.invest) ?? 0
        net = c.dbl(.net) ?? 0
    }
}

// MARK: - Changing investments

extension BudgetState {
    /// Brings in accounts read from a Fidelity positions file. `targets` maps each imported
    /// account's key (`FidelityCSV.Account.key`) to the id of the account it replaces, or
    /// "" to add it as a new account; keys left out are skipped. Each updated account gets
    /// the file's holdings and a new snapshot time, so contributions counted before now
    /// stop being added (the file already includes them).
    mutating func importPositions(_ imported: [FidelityCSV.Account], targets: [String: String]) {
        for a in imported {
            guard let target = targets[a.key] else { continue }
            if let i = accounts.firstIndex(where: { $0.id == target }) {
                accounts[i].holdings = a.holdings
                if accounts[i].number.isEmpty { accounts[i].number = a.number }
                accounts[i].asOf = DU.iso(Date()); accounts[i].asOfAt = DU.stamp()
            } else {
                var n = InvestAccount()
                n.name = a.name.isEmpty ? "Fidelity \(a.number.suffix(4))" : a.name
                n.number = a.number
                n.holdings = a.holdings
                n.asOfAt = DU.stamp()
                accounts.append(n)
            }
        }
        recordValues()
    }

    /// Saves today's investment total and net worth for the chart, replacing an earlier
    /// point from today.
    mutating func recordValues(on day: String = DU.iso(Date())) {
        let e = Engine(self)
        let p = ValuePoint(date: day, invest: r2(e.investTotal()), net: r2(e.netWorth().total))
        investHistory.removeAll { $0.date == day }
        investHistory.append(p)
        investHistory.sort { $0.date < $1.date }
    }

    /// Adds or updates an account (edited by hand) and records today's values.
    mutating func saveAccount(_ a: InvestAccount) {
        if let i = accounts.firstIndex(where: { $0.id == a.id }) { accounts[i] = a } else { accounts.append(a) }
        recordValues()
    }

    /// Removes an account and unlinks paycheck items that added to it.
    mutating func deleteAccount(_ id: String) {
        accounts.removeAll { $0.id == id }
        for i in recurring.indices where recurring[i].goalId == id { recurring[i].goalId = "" }
        recordValues()
    }
}
