import Foundation

struct Check: Hashable {
    let key: String       // month "yyyy-MM"
    let n: Int            // 1, 2 or 3 within the month
    let nominal: Date     // payday before weekend adjustment (used for bill windows)
    let date: Date        // actual payday
    let mode: String      // "bw" or "semi"
}

struct PayWindow {
    var from: Date
    var to: Date          // exclusive
    var lead: Int
    var transition: Bool
    var gapFrom: Date?
    var gapTo: Date?
    var catchUp: Bool
}

/// One row on a paycheck.
struct Line: Identifiable {
    var kind: String          // "rec" or "ex" (one-time)
    var id: String
    var name: String
    var type: String
    var budget: Double
    var env: Double           // planned amount for this check
    var amount: Double        // counted amount (for spending: the larger of budget and spent)
    var spent: Double = 0
    var isEnv: Bool = false
    var buys: [Buy] = []
    var paid: Bool
    var auto: Bool = false    // paid automatically by autopay
    var aside: Bool
    var autopay: Bool = false
    var skip: Bool = false
    var debtId: String = ""
    var goalId: String = ""
    var every: Int = 1
    var each: Bool = false
    var meta: String = ""
    var sortKey: Double = 0
    var home: Int             // check the line naturally belongs to
    var homeKey: String       // month of that check
    var dueDate: Date? = nil
    var moved: Bool = false
    var homeDate: Date? = nil
    var isExtraLine: Bool = false

    var status: String { paid ? "paid" : aside ? "aside" : "unpaid" }
    /// Unique per occurrence (the same bill can appear in several paychecks).
    var uid: String { "\(homeKey)|\(home)|\(kind)|\(id)" }
}

struct BuyEntry: Identifiable {
    let check: Check
    let recId: String
    let buy: Buy
    var id: String { buy.id }
}

struct Totals {
    var income: Double, start: Double, budget: Double, actual: Double, paid: Double, aside: Double
    var byType: [String: Double], budgetByType: [String: Double]
    var extraIncome = 0.0                 // part of `income` from extra income items
    var left: Double { start + income - actual }
    var plannedLeft: Double { start + income - budget }
}

struct SimResult {
    var months: Int
    var interest: Double
    var series: [Double]
    var payoff: [String: Int]
    var stuck: Bool
}

/// Pure calculations over a snapshot of the budget. Rebuilt after every change.
final class Engine {
    let s: BudgetState
    private var checkCache: [String: [Check]] = [:]
    private var lineCache: [String: [Line]] = [:]
    private var totalsCache: [String: Totals] = [:]
    private var windowCache: [String: PayWindow] = [:]
    private var balCache: [String: Double] = [:]
    private var inFocus = false
    private var focusCache: String?

    init(_ s: BudgetState) { self.s = s }

    var cfg: BudgetSettings { s.settings }
    var today: Date { DU.today }

    // MARK: Paydays

    func modeFor(_ key: String) -> String {
        if cfg.mode == "biweekly" && !cfg.bwAnchor.isEmpty { return "bw" }
        if cfg.mode == "switch" && !cfg.bwAnchor.isEmpty && (cfg.switchMonth.isEmpty || key < cfg.switchMonth) { return "bw" }
        return "semi"
    }

    private func adjustWeekend(_ d: Date) -> Date {
        let w = DU.weekday(d)
        if cfg.weekend == "friday" { if w == 7 { return DU.addDays(d, -1) }; if w == 1 { return DU.addDays(d, -2) } }
        if cfg.weekend == "monday" { if w == 7 { return DU.addDays(d, 2) }; if w == 1 { return DU.addDays(d, 1) } }
        return d
    }

    private func semiNominal(_ key: String, _ n: Int) -> Date {
        let (y, m) = DU.parseYM(key), ld = DU.lastDay(y, m)
        var day = n == 1 ? cfg.payDay1 : (Int(cfg.payDay2) ?? ld)
        if cfg.payDay2 == "last" && n == 2 { day = ld }
        return DU.date(y, m, min(day, ld))
    }

    private func bwDates(_ key: String) -> [Date] {
        guard let a = DU.parseISO(cfg.bwAnchor) else { return [] }
        let start = DU.firstOfMonth(key)
        let (y, m) = DU.parseYM(key)
        let end = DU.date(y, m, DU.lastDay(y, m))
        let k = Int((Double(DU.days(a, start)) / 14).rounded(.up))
        var d = DU.addDays(a, k * 14)
        var out: [Date] = []
        while d <= end {
            if cfg.mode == "switch", !cfg.bwEnd.isEmpty, DU.iso(d) > cfg.bwEnd { break }
            if d >= start { out.append(d) }
            d = DU.addDays(d, 14)
        }
        return out
    }

    func checksIn(_ key: String) -> [Check] {
        if let c = checkCache[key] { return c }
        let out: [Check]
        if modeFor(key) == "bw" {
            out = bwDates(key).enumerated().map { Check(key: key, n: $0.offset + 1, nominal: $0.element, date: $0.element, mode: "bw") }
        } else {
            out = [1, 2].map { n in let nom = semiNominal(key, n); return Check(key: key, n: n, nominal: nom, date: adjustWeekend(nom), mode: "semi") }
        }
        checkCache[key] = out
        return out
    }

    func check(_ key: String, _ n: Int) -> Check? {
        let l = checksIn(key); return n >= 1 && n <= l.count ? l[n - 1] : nil
    }

    func shiftCheck(_ key: String, _ n: Int, _ k: Int) -> Check? {
        var list = checksIn(key), idx = n - 1 + k, kk = key, g = 0
        while idx >= list.count && g < 8 { idx -= list.count; kk = DU.addMonths(kk, 1); list = checksIn(kk); g += 1 }
        while idx < 0 && g < 8 { kk = DU.addMonths(kk, -1); list = checksIn(kk); idx += list.count; g += 1 }
        return idx >= 0 && idx < list.count ? list[idx] : nil
    }

    func defaultPay(_ key: String) -> Double { modeFor(key) == "bw" ? cfg.bwPay : cfg.pay }

    func leadFor(_ key: String, _ n: Int) -> Int {
        guard cfg.payAhead > 0, let c = check(key, n) else { return 0 }
        if !cfg.payAheadFrom.isEmpty && DU.iso(c.date) < cfg.payAheadFrom { return 0 }
        return cfg.payAhead
    }

    func windowFor(_ key: String, _ n: Int) -> PayWindow {
        let ck = "\(key)|\(n)"
        if let w = windowCache[ck] { return w }
        guard let c = check(key, n) else { return PayWindow(from: today, to: today, lead: 0, transition: false, catchUp: false) }
        let L = leadFor(key, n)
        let start = L > 0 ? shiftCheck(key, n, L)?.nominal ?? c.nominal : c.nominal
        let end = shiftCheck(key, n, L + 1)?.nominal ?? DU.addDays(start, 14)
        var w = PayWindow(from: start, to: end, lead: L, transition: false, gapFrom: nil, gapTo: nil, catchUp: false)
        if L > 0 && !cfg.payAheadFrom.isEmpty, let pv = shiftCheck(key, n, -1), leadFor(pv.key, pv.n) == 0 {
            w.transition = true
            w.gapFrom = windowFor(pv.key, pv.n).to
            w.gapTo = start
            if cfg.payAheadCatchUp, let g = w.gapFrom { w.from = g; w.catchUp = true }
        }
        windowCache[ck] = w
        return w
    }

    // MARK: Lines

    func applies(_ r: Recurring, _ key: String) -> Bool {
        if !r.start.isEmpty && key < r.start { return false }
        if !r.end.isEmpty && key > r.end { return false }
        if r.every > 1 {
            let a = r.start.isEmpty ? cfg.startMonth : r.start
            let d = DU.monthsDiff(a, key)
            if d < 0 || d % r.every != 0 { return false }
        }
        return true
    }

    func cell(_ key: String, _ n: Int) -> Cell { s.months[key]?[String(n)] ?? Cell() }

    func perCheckExtra(_ key: String, _ when: String? = nil) -> Double {
        let w = when ?? extraRec?.when ?? s.extraWhen ?? "1"
        if w == "each" { let n = max(1, checksIn(key).count); return r2(s.extra / Double(n)) }
        return r2(s.extra)
    }

    var extraRec: Recurring? { s.recurring.first { $0.extraLine } }

    func debtName(_ id: String) -> String { s.debts.first { $0.id == id }?.name ?? "your next debt" }

    private func recLine(_ r: Recurring, _ o: Override, meta: String, sortKey: Double, home: Int, homeKey: String, dueDate: Date?, buys: [Buy]) -> Line {
        let env = o.amount ?? r.amount
        let spent = buys.reduce(0) { $0 + $1.amt }
        let isEnv = r.type == "expense"
        var paid = o.paid == true, auto = false
        if r.autopay && o.paid == nil, let d = dueDate, d <= today { paid = true; auto = true }
        return Line(kind: "rec", id: r.id, name: r.name, type: r.type, budget: r.amount, env: env,
                    amount: isEnv ? max(env, spent) : env, spent: spent, isEnv: isEnv, buys: buys,
                    paid: paid, auto: auto, aside: !paid && o.aside == true, autopay: r.autopay,
                    skip: o.skip == true, debtId: r.debtId, goalId: r.goalId, every: r.every,
                    each: r.when == "each", meta: meta, sortKey: sortKey, home: home, homeKey: homeKey,
                    dueDate: dueDate, isExtraLine: r.extraLine)
    }

    private func naturalRec(_ key: String, _ n: Int) -> [Line] {
        guard check(key, n) != nil else { return [] }
        let c = cell(key, n), w = windowFor(key, n)
        var out: [Line] = []
        func push(_ r0: Recurring, _ meta: String, _ sk: Double, _ d: Date?) {
            var r = r0
            let o = c.ov[r.id] ?? Override()
            if r.extraLine {
                let did = o.debtId ?? (inFocus ? "" : focusDebtId())
                r.amount = perCheckExtra(key, r.when)
                r.debtId = did
                r.name = "Extra → " + debtName(did)
            }
            out.append(recLine(r, o, meta: meta, sortKey: sk, home: n, homeKey: key, dueDate: d, buys: c.buys[r.id] ?? []))
        }
        for r in s.recurring {
            if r.extraLine, c.ov[r.id]?.paid == true, r.when != "each", r.when != String(n) { push(r, "", -1, nil); continue }
            if r.when == "each" { if applies(r, key) { push(r, "", -1, nil) }; continue }
            if ["1", "2", "3"].contains(r.when) {
                guard Int(r.when) == n, applies(r, key) else { continue }
                if let dd = r.dueDay {
                    let (y, m) = DU.parseYM(key)
                    let d = DU.date(y, m, min(dd, DU.lastDay(y, m)))
                    push(r, "Due " + DU.short(d), Double(DU.days(w.from, d)), d)
                } else { push(r, "", 0, nil) }
                continue
            }
            guard let dd = r.dueDay else { if n == 1 && applies(r, key) { push(r, "", 0, nil) }; continue }
            var d = w.from
            while d < w.to {
                let (y, m) = DU.monthOf(d)
                if DU.day(d) == min(dd, DU.lastDay(y, m)) && applies(r, DU.ym(d)) {
                    push(r, "Due " + DU.short(d), Double(DU.days(w.from, d)), d); break
                }
                d = DU.addDays(d, 1)
            }
        }
        return out
    }

    func lines(_ key: String, _ n: Int) -> [Line] {
        let ck = "\(key)|\(n)"
        if let l = lineCache[ck] { return l }
        let count = checksIn(key).count
        guard n >= 1 && n <= count else { return [] }
        let me = ck
        var rec: [Line] = []
        func target(_ mv: String?, _ k: String, _ h: Int) -> String {
            guard let mv = mv, !mv.isEmpty else { return "\(k)|\(h)" }
            if Int(mv) != nil { return "\(k)|\(mv)" }
            return mv
        }
        func take(_ k: String, _ h: Int) {
            let ov = cell(k, h).ov
            for var l in naturalRec(k, h) where target(ov[l.id]?.moveTo, k, h) == me {
                l.moved = "\(k)|\(h)" != me
                l.homeDate = check(k, h)?.date
                rec.append(l)
            }
        }
        for h in 1...count { take(key, h) }
        for k in [DU.addMonths(key, -1), DU.addMonths(key, 1)] { for c in checksIn(k) { take(k, c.n) } }
        rec.sort { $0.sortKey < $1.sortKey }
        let ex = cell(key, n).extras.map { e in
            Line(kind: "ex", id: e.id, name: e.name, type: e.type, budget: e.amount, env: e.amount, amount: e.amount,
                 paid: e.paid, aside: !e.paid && e.aside == true, debtId: e.debtId ?? "", goalId: e.goalId ?? "",
                 meta: "One-time", home: n, homeKey: key)
        }
        let out = rec + ex
        if !inFocus { lineCache[ck] = out }
        return out
    }

    func totals(_ key: String, _ n: Int) -> Totals {
        let ck = "\(key)|\(n)"
        if let t = totalsCache[ck] { return t }
        let c = cell(key, n)
        let extraIncome = c.addIncome.reduce(0) { $0 + $1.amount }
        let income = (c.income ?? defaultPay(key)) + extraIncome
        var by: [String: Double] = [:], bud: [String: Double] = [:]
        var budget = 0.0, actual = 0.0, paid = 0.0, aside = 0.0
        for l in lines(key, n) where !l.skip {
            budget += l.budget; actual += l.amount
            by[l.type, default: 0] += l.amount; bud[l.type, default: 0] += l.budget
            if l.paid { paid += l.amount } else if l.aside { aside += l.amount }
        }
        var start = 0.0
        if cfg.rollover {
            let prev: (String, Int) = n > 1 ? (key, n - 1) : (DU.addMonths(key, -1), checksIn(DU.addMonths(key, -1)).count)
            if prev.0 >= cfg.startMonth && DU.monthsDiff(cfg.startMonth, prev.0) < 60 && prev.1 >= 1 { start = totals(prev.0, prev.1).left }
        }
        let t = Totals(income: income, start: start, budget: budget, actual: actual, paid: paid, aside: aside, byType: by, budgetByType: bud, extraIncome: extraIncome)
        totalsCache[ck] = t
        return t
    }

    func monthTotals(_ key: String) -> (income: Double, actual: Double, budget: Double, paid: Double, byType: [String: Double], count: Int) {
        var inc = 0.0, act = 0.0, bud = 0.0, pd = 0.0, by: [String: Double] = [:]
        let cs = checksIn(key)
        for c in cs {
            let t = totals(key, c.n)
            inc += t.income; act += t.actual; bud += t.budget; pd += t.paid
            for (k, v) in t.byType { by[k, default: 0] += v }
        }
        return (inc, act, bud, pd, by, cs.count)
    }

    // MARK: Debt

    private func monthsToScan(_ asOf: String) -> [String] {
        var keys = Set(s.months.keys)
        let cur = DU.ym(Date())
        var k = asOf.count >= 7 ? String(asOf.prefix(7)) : self.cfg.startMonth
        if k < self.cfg.startMonth { k = DU.addMonths(self.cfg.startMonth, -1) }
        var i = 0
        while i < 48 && k <= DU.addMonths(cur, 1) { keys.insert(k); k = DU.addMonths(k, 1); i += 1 }
        return Array(keys)
    }

    func paidSince(debtId: String, asOf: String) -> Double {
        var sum = 0.0
        for key in monthsToScan(asOf) {
            for c in checksIn(key) where DU.iso(c.date) > asOf {
                for l in lines(key, c.n) where !l.skip && l.paid && l.type == "debt" && l.debtId == debtId { sum += l.amount }
            }
        }
        return sum
    }

    func curBal(_ d: Debt) -> Double {
        if !inFocus, let v = balCache[d.id] { return v }
        let v = max(0, d.balance - paidSince(debtId: d.id, asOf: d.asOf))
        if !inFocus { balCache[d.id] = v }
        return v
    }

    func order(_ strategy: String) -> ((id: String, bal: Double, apr: Double), (id: String, bal: Double, apr: Double)) -> Bool {
        if strategy == "snowball" { return { $0.bal < $1.bal } }
        if strategy == "target", let t = s.targetDebt {
            return { a, b in
                if (a.id == t) != (b.id == t) { return a.id == t }
                return a.apr > b.apr
            }
        }
        return { $0.apr > $1.apr }
    }

    func focusDebtId() -> String {
        if let f = focusCache { return f }
        inFocus = true
        let act = s.debts.map { (id: $0.id, bal: curBal($0), apr: $0.apr) }.filter { $0.bal > 0.005 }
        inFocus = false
        var res = ""
        if s.strategy == "target", let t = s.targetDebt, act.contains(where: { $0.id == t }) { res = t }
        else { res = act.sorted(by: order(s.strategy == "target" ? "avalanche" : s.strategy)).first?.id ?? "" }
        focusCache = res
        return res
    }

    func simulate(extra: Double, strategy: String) -> SimResult {
        struct D { var id: String; var bal: Double; var apr: Double; var min: Double }
        var ds = s.debts.map { D(id: $0.id, bal: curBal($0), apr: $0.apr, min: $0.min) }.filter { $0.bal > 0.005 }
        let budget = ds.reduce(0) { $0 + $1.min } + extra
        var m = 0, interest = 0.0, series = [ds.reduce(0) { $0 + $1.bal }], payoff: [String: Int] = [:]
        let cmp = order(strategy)
        while ds.contains(where: { $0.bal > 0.005 }) && m < 600 {
            m += 1
            for i in ds.indices where ds[i].bal > 0.005 { let x = ds[i].bal * ds[i].apr / 1200; ds[i].bal += x; interest += x }
            var avail = budget
            for i in ds.indices where ds[i].bal > 0.005 { let p = min(ds[i].min, ds[i].bal, avail); ds[i].bal -= p; avail -= p }
            let idx = ds.indices.filter { ds[$0].bal > 0.005 }.sorted { cmp((ds[$0].id, ds[$0].bal, ds[$0].apr), (ds[$1].id, ds[$1].bal, ds[$1].apr)) }
            for i in idx { if avail <= 0.005 { break }; let p = min(avail, ds[i].bal); ds[i].bal -= p; avail -= p }
            for i in ds.indices where ds[i].bal <= 0.005 && payoff[ds[i].id] == nil { ds[i].bal = 0; payoff[ds[i].id] = m }
            series.append(ds.reduce(0) { $0 + $1.bal })
        }
        return SimResult(months: m, interest: interest, series: series, payoff: payoff, stuck: m >= 600)
    }

    func plannedDebtPerMonth(_ key: String) -> Double {
        let per = modeFor(key) == "bw" ? 26.0 / 12 : 2
        return r2(s.recurring.filter { $0.type == "debt" && !$0.loanPlan && !$0.extraLine && applies($0, key) }
            .reduce(0) { $0 + ($1.when == "each" ? $1.amount * per : $1.amount / Double($1.every)) })
    }

    // MARK: Today

    func currentCheck() -> Check? {
        let cur = DU.ym(Date())
        var best: Check?
        for k in [DU.addMonths(cur, -1), cur] { for c in checksIn(k) where c.date <= today { best = c } }
        return best
    }

    /// The paycheck a purchase on this day counts toward.
    func periodCheck(_ d: Date) -> Check? {
        for k in [DU.addMonths(DU.ym(d), -1), DU.ym(d)] {
            for c in checksIn(k).reversed() where c.date <= d {
                if let nx = shiftCheck(k, c.n, 1), nx.date <= d { continue }
                return k >= cfg.startMonth ? c : nil
            }
        }
        return nil
    }

    struct Upcoming { var toPay: [Line]; var pending: [Line]; var overdue: [Line]; var cur: Check?; var next: Check?; var nextTotal: Double; var nextCount: Int }

    func upcoming() -> Upcoming {
        let cur = DU.ym(Date()), start = cfg.startMonth
        let keys = [DU.addMonths(cur, -2), DU.addMonths(cur, -1), cur, DU.addMonths(cur, 1)].filter { $0 >= start }
        var overdue: [Line] = [], pending: [Line] = []
        let soon = DU.addDays(today, 21)
        for k in keys {
            for c in checksIn(k) {
                for l in lines(k, c.n) where l.kind == "rec" && !l.skip && !l.isEnv && !l.paid {
                    if l.aside || (l.autopay && (l.dueDate.map { $0 <= soon } ?? false)) { pending.append(l) }
                    else if let d = l.dueDate, d < today, DU.iso(d) >= start + "-01" { overdue.append(l) }
                }
            }
        }
        let cc = currentCheck()
        let toPay = cc.map { c in lines(c.key, c.n).filter { $0.kind == "rec" && !$0.paid && !$0.aside && !$0.autopay && !$0.skip && !$0.isEnv && !($0.dueDate.map { $0 < today } ?? false) } } ?? []
        let nx = cc.flatMap { shiftCheck($0.key, $0.n, 1) }
        let nxLines = nx.map { lines($0.key, $0.n).filter { !$0.skip && !$0.isEnv && $0.type != "savings" } } ?? []
        return Upcoming(toPay: toPay, pending: pending.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) },
                        overdue: overdue.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) },
                        cur: cc, next: nx, nextTotal: nxLines.reduce(0) { $0 + $1.amount }, nextCount: nxLines.count)
    }

    /// Paychecks around a month, for "move to another paycheck".
    func moveOptions(homeKey: String) -> [Check] {
        [DU.addMonths(homeKey, -1), homeKey, DU.addMonths(homeKey, 1)].flatMap { checksIn($0) }
    }

    /// All logged purchases in a month.
    func monthBuys(_ key: String) -> [BuyEntry] {
        var out: [BuyEntry] = []
        for c in checksIn(key) { for (rid, list) in cell(key, c.n).buys { for b in list { out.append(BuyEntry(check: c, recId: rid, buy: b)) } } }
        return out.sorted { $0.buy.date == $1.buy.date ? $0.buy.amt > $1.buy.amt : $0.buy.date > $1.buy.date }
    }
}
