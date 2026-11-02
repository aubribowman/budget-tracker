import Foundation

/// Projection for all student loans together.
struct LoanSim {
    struct Item { var id: String; var balanceNow: Double; var atRepay: Double; var standard: Double; var payoff: String? }
    var items: [String: Item] = [:]
    var monthly: Double = 0          // what the plan pays each month once repayment starts
    var standardTotal: Double = 0    // sum of each loan's standard payment
    var interest: Double = 0         // interest from now until paid off
    var payoff: String?              // month the last loan is paid off, "yyyy-MM"
    var stuck = false                // payment doesn't cover interest
}

extension Engine {
    static let loanKinds: [(id: String, label: String)] = [
        ("subsidized", "Federal subsidized"), ("unsubsidized", "Federal unsubsidized"), ("private", "Private")
    ]
    static func loanKindLabel(_ k: String) -> String { loanKinds.first { $0.id == k }?.label ?? k.capitalized }

    /// Subsidized loans don't build interest before repayment; the others do.
    func accruesInSchool(_ l: Loan) -> Bool { l.kind != "subsidized" }

    func repayMonth(_ l: Loan) -> String { l.repayStart.count >= 7 ? String(l.repayStart.prefix(7)) : DU.ym(Date()) }

    /// Monthly payment that pays off `bal` over `years` at `apr`.
    static func standardPayment(_ bal: Double, apr: Double, years: Int) -> Double {
        let n = Double(max(1, years) * 12), r = apr / 1200
        guard bal > 0 else { return 0 }
        return r2(r == 0 ? bal / n : bal * r / (1 - pow(1 + r, -n)))
    }

    /// Student loan payments marked paid on your paychecks, oldest first.
    func loanPayments() -> [(date: Date, amount: Double)] {
        let planIds = Set(s.recurring.filter { $0.loanPlan }.map(\.id))
        guard !planIds.isEmpty else { return [] }
        var out: [(Date, Double)] = []
        let earliest = s.loans.map(\.asOf).min() ?? DU.iso(Date())
        for key in Set(s.months.keys) where key >= String(earliest.prefix(7)) {
            for c in checksIn(key) {
                for l in lines(key, c.n) where l.paid && !l.skip && planIds.contains(l.id) { out.append((c.date, l.amount)) }
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    /// Today's balance for each loan: what you entered, plus interest built up before
    /// repayment, minus payments marked paid since (highest rate first).
    func loanBalances() -> [String: Double] {
        var bal: [String: Double] = [:]
        for l in s.loans {
            var b = l.balance
            if accruesInSchool(l), let since = DU.parseISO(l.asOf) {
                let repay = DU.firstOfMonth(repayMonth(l))
                let end = min(DU.today, repay)
                let days = max(0, DU.days(since, end))
                b += l.balance * l.apr / 100 / 365 * Double(days)
            }
            bal[l.id] = b
        }
        for p in loanPayments() {
            var left = p.amount
            let eligible = s.loans.filter { (bal[$0.id] ?? 0) > 0.005 && (DU.parseISO($0.asOf) ?? .distantPast) < p.date }
                .sorted { $0.apr > $1.apr }
            for l in eligible where left > 0.005 {
                let pay = min(left, bal[l.id] ?? 0)
                bal[l.id, default: 0] -= pay; left -= pay
            }
        }
        return bal.mapValues { max(0, r2($0)) }
    }

    func simulateLoans() -> LoanSim {
        var sim = LoanSim()
        guard !s.loans.isEmpty else { return sim }
        let now = DU.ym(Date())
        let start = loanBalances()

        struct L { var id: String; var bal: Double; var apr: Double; var repay: String; var accrues: Bool; var std: Double; var own: Double }
        var ls: [L] = s.loans.map { l in
            let b = start[l.id] ?? l.balance
            let repay = repayMonth(l)
            // Balance when repayment starts: interest keeps building until then.
            let monthsLeft = max(0, DU.monthsDiff(now, repay))
            let atRepay = accruesInSchool(l) ? b * (1 + l.apr / 1200 * Double(monthsLeft)) : b
            let std = Engine.standardPayment(atRepay, apr: l.apr, years: l.term)
            sim.items[l.id] = .init(id: l.id, balanceNow: b, atRepay: r2(atRepay), standard: std, payoff: nil)
            return L(id: l.id, bal: b, apr: l.apr, repay: repay, accrues: accruesInSchool(l), std: std, own: l.payment > 0 ? l.payment : std)
        }
        sim.standardTotal = r2(ls.reduce(0) { $0 + $1.std })
        let planPay = s.loanPlan.payment > 0 ? s.loanPlan.payment : ls.reduce(0) { $0 + $1.own }
        sim.monthly = r2(planPay)
        let planStart = s.loanPlan.start.count >= 7 ? String(s.loanPlan.start.prefix(7)) : (ls.map(\.repay).min() ?? now)

        var unpaid = [Double](repeating: 0, count: ls.count)  // interest built up before repayment
        var m = 0
        while ls.contains(where: { $0.bal > 0.005 }) && m < 600 {
            let key = DU.addMonths(now, m)
            m += 1
            for i in ls.indices where ls[i].bal > 0.005 {
                let x = ls[i].bal * ls[i].apr / 1200
                if key < ls[i].repay {
                    if ls[i].accrues { unpaid[i] += x; sim.interest += x }
                } else {
                    if unpaid[i] > 0 { ls[i].bal += unpaid[i]; unpaid[i] = 0 }   // added to the balance when repayment starts
                    ls[i].bal += x; sim.interest += x
                }
            }
            guard key >= planStart else { continue }
            var avail = planPay
            let active = ls.indices.filter { ls[$0].bal > 0.005 && key >= ls[$0].repay }
            for i in active { let p = min(ls[i].own, ls[i].bal, avail); ls[i].bal -= p; avail -= p }
            for i in active.sorted(by: { ls[$0].apr > ls[$1].apr }) where avail > 0.005 {
                let p = min(avail, ls[i].bal); ls[i].bal -= p; avail -= p
            }
            for i in ls.indices where ls[i].bal <= 0.005 && sim.items[ls[i].id]?.payoff == nil && key >= ls[i].repay {
                ls[i].bal = 0
                sim.items[ls[i].id]?.payoff = key
            }
        }
        sim.stuck = m >= 600
        sim.payoff = sim.stuck ? nil : sim.items.values.compactMap(\.payoff).max()
        sim.interest = r2(sim.interest)
        return sim
    }

    /// The paycheck line for the student loan plan, if it's been added.
    var loanPlanRec: Recurring? { s.recurring.first { $0.loanPlan } }
}
