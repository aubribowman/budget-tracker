import Foundation

/// Where an imported bank transaction goes.
enum ImportTarget: Hashable {
    case skip
    case spend(String)   // log as a purchase in this spending category
    case bill(String)    // mark this recurring bill, subscription or debt payment paid

    /// How it's saved in `importRules`, matching the web app's rule format.
    var ruleValue: String {
        switch self {
        case .skip: return "skip"
        case .spend(let id), .bill(let id): return id
        }
    }
}

extension Store {
    /// True if this transaction came in on an earlier import.
    func alreadyImported(_ t: BankTx) -> Bool { state.imported[t.id] != nil }

    /// Best guess for a transaction: a saved rule first, then a bill whose name
    /// or amount matches, otherwise nothing (the person picks).
    func suggestTarget(_ t: BankTx) -> (target: ImportTarget, fromRule: Bool) {
        let key = BankCSV.merchantKey(t.desc)
        if !key.isEmpty, let v = state.importRules[key] {
            if v == "skip" { return (.skip, true) }
            if let r = state.recurring.first(where: { $0.id == v }) {
                return (r.type == "expense" ? .spend(r.id) : .bill(r.id), true)
            }
        }
        // Money coming in (paychecks, refunds) is skipped unless a rule says otherwise.
        guard t.isOutflow else { return (.skip, false) }

        // A pocket matched to a category in the web app (Crew and similar banks).
        if !t.pocket.isEmpty, let v = state.pocketMap[t.pocket] ?? state.pocketMap[t.pocket.lowercased()],
           let r = state.recurring.first(where: { $0.id == v || $0.name.caseInsensitiveCompare(v) == .orderedSame }) {
            return (r.type == "expense" ? .spend(r.id) : .bill(r.id), false)
        }

        let desc = t.desc.lowercased()
        let bills = state.recurring.filter { $0.type != "expense" && !$0.extraLine }
        // Name match: any word of 4+ letters from the bill's name shows up in the bank text.
        if let r = bills.first(where: { r in
            r.name.lowercased().split { !$0.isLetter }.contains { $0.count >= 4 && desc.contains($0) }
        }) { return (.bill(r.id), false) }
        // A pocket with the same name as a spending category, like "Food" or "Transportation".
        let pocket = t.pocket.lowercased()
        if !pocket.isEmpty, !["checking", "savings"].contains(pocket),
           let r = state.recurring.first(where: { r in
               let n = r.name.lowercased()
               return r.type == "expense" && (n == pocket || n.contains(pocket) || pocket.contains(n))
           }) { return (.spend(r.id), false) }
        // Amount match: an unpaid bill for the same amount due within a week.
        if let l = openBillLines(near: t.date).first(where: { l in
            abs(l.amount - abs(t.amount)) < 0.01 && (l.dueDate.map { abs(DU.days($0, t.date)) <= 7 } ?? false)
        }) { return (.bill(l.id), false) }
        return (.skip, false)
    }

    /// Unpaid bill lines on paychecks around a date.
    private func openBillLines(near d: Date) -> [Line] {
        let k = DU.ym(d)
        var out: [Line] = []
        for key in [DU.addMonths(k, -1), k, DU.addMonths(k, 1)] where key >= state.settings.startMonth {
            for c in engine.checksIn(key) {
                out += engine.lines(key, c.n).filter { $0.kind == "rec" && !$0.isEnv && !$0.paid && !$0.skip && $0.type != "expense" }
            }
        }
        return out
    }

    /// Saves the picked transactions in one change. Returns how many were added
    /// and the ones that couldn't be placed, with the reason.
    @discardableResult
    func applyImport(_ picks: [(tx: BankTx, target: ImportTarget, remember: Bool)]) -> (added: Int, problems: [String]) {
        var added = 0
        var problems: [String] = []
        let e = engine
        let stamp = Date().timeIntervalSince1970 * 1000
        var usedLines = Set<String>()

        update { s in
            func edit(_ key: String, _ n: Int, _ f: (inout Cell) -> Void) {
                var m = s.months[key] ?? [:]
                var c = m[String(n)] ?? Cell()
                f(&c)
                m[String(n)] = c
                s.months[key] = m
            }

            for p in picks {
                let t = p.tx
                if p.remember {
                    let key = BankCSV.merchantKey(t.desc)
                    if !key.isEmpty { s.importRules[key] = p.target.ruleValue }
                }
                switch p.target {
                case .skip:
                    // Remember skipped rows too, so they don't show up again next time.
                    s.imported[t.id] = stamp

                case .spend(let recId):
                    guard let pc = e.periodCheck(t.date) else {
                        problems.append("\(t.desc): \(DU.short(t.date)) is before your budget starts.")
                        continue
                    }
                    edit(pc.key, pc.n) { c in
                        var b = Buy()
                        b.amt = r2(-t.amount)        // spending is positive, refunds negative
                        b.note = t.desc
                        b.date = DU.iso(t.date)
                        b.tx = t.id
                        c.buys[recId, default: []].append(b)
                    }
                    s.imported[t.id] = stamp
                    added += 1

                case .bill(let recId):
                    // The unpaid copy of this bill whose due date (or payday) is closest to the bank date.
                    let k = DU.ym(t.date)
                    var best: Line?
                    var bestGap = Int.max
                    for key in [DU.addMonths(k, -1), k, DU.addMonths(k, 1)] where key >= s.settings.startMonth {
                        for c in e.checksIn(key) {
                            for l in e.lines(key, c.n) where l.kind == "rec" && l.id == recId && !l.paid && !l.skip && !usedLines.contains(l.uid) {
                                let gap = abs(DU.days(l.dueDate ?? c.date, t.date))
                                if gap < bestGap { best = l; bestGap = gap }
                            }
                        }
                    }
                    guard let l = best else {
                        let name = s.recurring.first { $0.id == recId }?.name ?? "that bill"
                        problems.append("\(t.desc): no unpaid \(name) near \(DU.short(t.date)).")
                        continue
                    }
                    usedLines.insert(l.uid)
                    let base = s.recurring.first { $0.id == recId }?.amount ?? 0
                    let paid = r2(abs(t.amount))
                    edit(l.homeKey, l.home) { c in
                        var o = c.ov[l.id] ?? Override()
                        o.paid = true
                        o.aside = false
                        o.tx = t.id
                        // Keep the real amount when it differs from the usual one (like a utility bill).
                        if abs(paid - base) >= 0.005 { o.amount = paid }
                        c.ov[l.id] = o
                    }
                    s.imported[t.id] = stamp
                    added += 1
                }
            }
        }
        return (added, problems)
    }
}
