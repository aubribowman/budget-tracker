import Foundation

// Student loan math, plus the combined payoff simulation behind the Payoff chart.
//
// There are two simulations here, on purpose:
// - `simulateLoans` looks at student loans alone, for the per-loan numbers on the
//   Student loans screen (balance at repayment, standard payment).
// - `simulateAll` runs cards, personal loans and student loans together and is what
//   every payoff date in the app comes from. It's a port of the web app's
//   `simulateAll`, so if you change it, check the dates still match the web app.

/// Projection for all student loans together.
struct LoanSim {
    /// One loan's numbers: balance today, balance when repayment starts, its standard
    /// monthly payment, and the month it's paid off.
    struct Item { var id: String; var balanceNow: Double; var atRepay: Double; var standard: Double; var payoff: String? }
    var items: [String: Item] = [:]
    var monthly: Double = 0          // what the plan pays each month once repayment starts
    var standardTotal: Double = 0    // sum of each loan's standard payment
    var interest: Double = 0         // interest from now until paid off
    var payoff: String?              // month the last loan is paid off, "yyyy-MM"
    var stuck = false                // payment doesn't cover interest
}

extension Engine {
    /// The loan types the app knows, stored by id ("subsidized") and shown by label.
    static let loanKinds: [(id: String, label: String)] = [
        ("subsidized", "Federal subsidized"), ("unsubsidized", "Federal unsubsidized"), ("private", "Private")
    ]
    /// The display name for a loan type id, like "Federal subsidized".
    static func loanKindLabel(_ k: String) -> String { loanKinds.first { $0.id == k }?.label ?? k.capitalized }

    /// Subsidized loans don't build interest before repayment; the others do.
    func accruesInSchool(_ l: Loan) -> Bool { l.kind != "subsidized" }

    /// The month repayment starts, "yyyy-MM". Treated as this month if it's not set.
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

    /// Student loans on their own, month by month: interest builds before repayment, then
    /// each loan gets its own payment, and anything left over in the plan goes to the
    /// highest rate first. Used for per-loan numbers, not the payoff dates (see `simulateAll`).
    func simulateLoans() -> LoanSim {
        var sim = LoanSim()
        guard !s.loans.isEmpty else { return sim }
        let now = DU.ym(Date())
        let start = loanBalances()
        let calc = Dictionary(uniqueKeysWithValues: s.loans.map { ($0.id, loanCalc($0, balances: start)) })

        // A working copy of each loan. `std` is its standard payment and `own` the share
        // of the plan's payment it gets before extra goes to the highest rate.
        struct L { var id: String; var bal: Double; var apr: Double; var repay: String; var accrues: Bool; var std: Double; var own: Double }
        var ls: [L] = s.loans.map { l in
            let b = start[l.id] ?? l.balance
            let repay = repayMonth(l)
            // Balance when repayment starts: interest keeps building until then.
            let monthsLeft = max(0, DU.monthsDiff(now, repay))
            let atRepay = calc[l.id].map { monthsLeft > 0 ? $0.atStart : b } ?? b
            let std = r2(calc[l.id]?.est ?? Engine.standardPayment(atRepay, apr: l.apr, years: l.term))
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

/// Debts and student loans paid off together, month by month, for the Payoff chart.
/// Same math as the web app's Payoff tab, so both show the same dates.
struct PayoffSim {
    var debtSeries: [Double] = []      // index = months from now
    var loanSeries: [Double] = []
    var debtPayoff: [String: Int] = [:]
    var loanPayoff: [String: Int] = [:]
    var interest = 0.0
    var loanInterest = 0.0             // student loans only, including what builds up before repayment
    var months = 0                     // until everything is paid off
    var debtMonths = 0                 // last card or personal loan
    var loanMonths = 0                 // last student loan
    var count = 0                      // debts and loans with a balance
    var stuck = false

    /// Everything owed `m` months from now, cards and loans together (for the chart).
    func total(_ m: Int) -> Double {
        (m < debtSeries.count ? debtSeries[m] : 0) + (m < loanSeries.count ? loanSeries[m] : 0)
    }
    // The month each group is paid off, as "yyyy-MM", counting from `now`.
    func debtsDone(_ now: String) -> String { DU.addMonths(now, debtMonths) }
    func loansDone(_ now: String) -> String { DU.addMonths(now, loanMonths) }
    func finish(_ now: String) -> String { DU.addMonths(now, months) }
}

extension Engine {
    /// A student loan's numbers the way the web app works them out: interest builds
    /// daily (simple interest) until repayment starts, and the standard payment is
    /// figured on the balance at that point.
    func loanCalc(_ l: Loan, balances: [String: Double]) -> (now: Double, atStart: Double, est: Double, start: String) {
        let today = DU.today
        let asOf = DU.parseISO(l.asOf) ?? today
        let rate = l.apr / 100
        let accrues = accruesInSchool(l)
        // Payments marked paid on your paychecks come off both numbers.
        let days = max(0, Double(DU.days(asOf, today)))
        let simpleNow = l.balance + (accrues ? l.balance * rate / 365 * days : 0)
        let paid = max(0, simpleNow - (balances[l.id] ?? simpleNow))
        let start = l.repayStart.count >= 7 ? String(l.repayStart.prefix(7)) : ""
        let daysToStart = start.isEmpty ? 0 : max(0, Double(DU.days(asOf, DU.firstOfMonth(start))))
        let atStart = max(0, l.balance + (accrues ? l.balance * rate / 365 * daysToStart : 0) - paid)
        let n = Double(max(1, l.term * 12)), r = rate / 12
        let est = r > 0 ? atStart * r / (1 - pow(1 + r, -n)) : atStart / n
        return (max(0, simpleNow - paid), atStart, est, start)
    }

    /// Runs your cards, personal loans and student loans together. With `roll`, once the
    /// cards and personal loans are paid off, their payments go to student loans.
    /// `lump` is a one-time payment this month (debt or loan id → amount), for the
    /// windfall planner. A debt it pays off keeps its payment in the plan, like the web app.
    func simulateAll(extra: Double, strategy: String, roll: Bool, lump: [String: Double] = [:]) -> PayoffSim {
        var r = PayoffSim()
        let now = DU.ym(Date())
        // One entry per debt or loan. For loans not in repayment yet: `start` is months until
        // repayment, `startBal` the balance then, and `growth` how much it grows each month until then.
        struct D { var id: String; var bal: Double; var apr: Double; var min: Double; var loan: Bool
                   var start = 0; var startBal = 0.0; var growth = 0.0 }

        var ds = s.debts.map { D(id: $0.id, bal: curBal($0), apr: $0.apr, min: $0.min, loan: false) }.filter { $0.bal > 0.005 }
        let lb = loanBalances()
        let loans = s.loans.map { ($0, loanCalc($0, balances: lb)) }.filter { $0.1.atStart > 0.005 }
        let planPay = s.loanPlan.payment
        let estSum = loans.reduce(0) { $0 + $1.1.est }
        for (l, c) in loans {
            let pay = l.payment > 0 ? l.payment : planPay > 0 && estSum > 0 ? planPay * c.est / estSum : c.est
            let st = c.start.isEmpty ? 0 : max(0, DU.monthsDiff(now, c.start))
            ds.append(D(id: l.id, bal: st > 0 ? c.now : c.atStart, apr: l.apr, min: pay, loan: true,
                        start: st, startBal: c.atStart, growth: st > 0 ? (c.atStart - c.now) / Double(st) : 0))
        }
        r.count = ds.count
        // The monthly pool: every card's minimum plus the extra. It stays the same size as
        // debts are paid off, which is how a paid-off card's payment rolls to the next one.
        let poolBase = ds.filter { !$0.loan }.reduce(0) { $0 + $1.min } + extra
        let cmp = order(strategy)
        let target = s.targetDebt
        // With the "Pick a debt" strategy, the one debt that gets all the extra.
        func isTarget(_ d: D) -> Bool { strategy == "target" && d.id == target }

        var m = 0
        // Still owed and being paid (a student loan isn't paid until repayment starts).
        func active(_ d: D) -> Bool { d.bal > 0.005 && (!d.loan || m > d.start) }
        // Saves this month's totals for the chart.
        func record() {
            r.debtSeries.append(ds.filter { !$0.loan }.reduce(0) { $0 + max(0, $1.bal) })
            r.loanSeries.append(ds.filter { $0.loan }.reduce(0) { $0 + max(0, $1.bal) })
        }
        record()

        while ds.contains(where: { $0.bal > 0.005 }) && m < 480 {
            m += 1
            // Windfall planner: the one-time payment lands in the first month.
            if m == 1 {
                for i in ds.indices {
                    guard let a = lump[ds[i].id], a > 0.005 else { continue }
                    let cap = ds[i].loan && m <= ds[i].start ? min(ds[i].bal, ds[i].startBal > 0 ? ds[i].startBal : ds[i].bal) : ds[i].bal
                    let p = min(a, cap)
                    ds[i].bal -= p
                    if ds[i].startBal > 0 { ds[i].startBal = max(0, ds[i].startBal - p) }
                    if ds[i].loan && ds[i].start >= m {
                        ds[i].growth = max(0, (ds[i].startBal - ds[i].bal) / Double(max(1, ds[i].start - m + 1)))
                    }
                }
            }
            // Before repayment, loans grow toward their balance at repayment.
            for i in ds.indices where ds[i].loan {
                if m <= ds[i].start { ds[i].bal += ds[i].growth; r.loanInterest += ds[i].growth }
                else if m == ds[i].start + 1 && ds[i].startBal > 0 { ds[i].bal = ds[i].startBal }
            }
            for i in ds.indices where active(ds[i]) {
                let x = ds[i].bal * ds[i].apr / 1200; ds[i].bal += x; r.interest += x
                if ds[i].loan { r.loanInterest += x }
            }

            // Minimums first. Card minimums come out of the pool; loan payments are paid on their own.
            var pool = poolBase
            for i in ds.indices where !ds[i].loan && active(ds[i]) { let p = min(ds[i].min, ds[i].bal, pool); ds[i].bal -= p; pool -= p }
            for i in ds.indices where ds[i].loan && active(ds[i]) { let p = min(ds[i].min, ds[i].bal); ds[i].bal -= p }

            let orderIdx = ds.indices.filter { active(ds[$0]) && (!ds[$0].loan || roll || isTarget(ds[$0])) }
                .sorted { cmp((ds[$0].id, ds[$0].bal, ds[$0].apr), (ds[$1].id, ds[$1].bal, ds[$1].apr)) }
            let cardsLeft = ds.contains { !$0.loan && $0.bal > 0.005 }
            let anyCardInOrder = orderIdx.contains { !ds[$0].loan }
            // Extra goes to cards and personal loans first, then (with roll) to student loans.
            for i in orderIdx {
                if pool <= 0.005 { break }
                if ds[i].loan && !roll && !isTarget(ds[i]) { continue }
                if ds[i].loan && !isTarget(ds[i]) && cardsLeft && anyCardInOrder { continue }
                let p = min(pool, ds[i].bal); ds[i].bal -= p; pool -= p
            }
            // Anything still left over (for example, the last card was paid off this month) goes down the same list.
            for i in orderIdx {
                if pool <= 0.005 { break }
                let p = min(pool, ds[i].bal); ds[i].bal -= p; pool -= p
            }

            for i in ds.indices where ds[i].bal <= 0.005 && (!ds[i].loan || m > ds[i].start) {
                if ds[i].loan, r.loanPayoff[ds[i].id] == nil { ds[i].bal = 0; r.loanPayoff[ds[i].id] = m }
                if !ds[i].loan, r.debtPayoff[ds[i].id] == nil { ds[i].bal = 0; r.debtPayoff[ds[i].id] = m }
            }
            record()
        }
        r.months = m
        r.stuck = m >= 480
        r.debtMonths = r.debtPayoff.values.max() ?? 0
        r.loanMonths = r.loanPayoff.values.max() ?? 0
        return r
    }
}
