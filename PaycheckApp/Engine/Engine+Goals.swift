import Foundation

/// Where a savings goal stands and where it's headed.
struct GoalStatus {
    var saved: Double          // starting balance plus savings marked paid since
    var target: Double
    var perMonth: Double       // planned on this month's paychecks
    var finish: String?        // month you'll reach it at the planned pace, "yyyy-MM"
    var needPerMonth: Double?  // what it takes to hit the due date, if there is one
    var left: Double { max(0, target - saved) }
    var progress: Double { target > 0 ? min(1, saved / target) : 0 }
    var done: Bool { target > 0 && saved >= target - 0.005 }
    /// True when there's a due date and the planned pace reaches it in time.
    var onTrack: Bool? {
        guard let need = needPerMonth else { return nil }
        return done || perMonth >= need - 0.005
    }
}

extension Engine {
    /// Savings lines linked to this goal and marked paid after `asOf`.
    func savedSince(goalId: String, asOf: String) -> Double {
        var sum = 0.0
        for key in Array(Set(s.months.keys).union(recentMonths(from: asOf))) {
            for c in checksIn(key) where DU.iso(c.date) > asOf {
                for l in lines(key, c.n) where !l.skip && l.paid && l.goalId == goalId { sum += l.amount }
            }
        }
        return sum
    }

    /// Planned toward this goal on this month's paychecks.
    func plannedPerMonth(goalId: String) -> Double {
        let key = DU.ym(Date())
        return checksIn(key).reduce(0) { t, c in
            t + lines(key, c.n).filter { !$0.skip && $0.goalId == goalId }.reduce(0) { $0 + $1.amount }
        }
    }

    func goalStatus(_ g: Goal) -> GoalStatus {
        let saved = g.balance + savedSince(goalId: g.id, asOf: g.asOf)
        let per = plannedPerMonth(goalId: g.id)
        var st = GoalStatus(saved: saved, target: g.target, perMonth: per)
        let now = DU.ym(Date())
        if st.left > 0.005, per > 0.005 {
            st.finish = DU.addMonths(now, Int((st.left / per).rounded(.up)))
        }
        if !g.due.isEmpty {
            let dueMonth = String(g.due.prefix(7))
            // Count this month too, so a goal due next month has two months of saving left.
            let months = max(1, DU.monthsDiff(now, dueMonth) + 1)
            st.needPerMonth = st.left / Double(months)
        }
        return st
    }

    private func recentMonths(from asOf: String) -> [String] {
        var out: [String] = []
        var k = asOf.count >= 7 ? String(asOf.prefix(7)) : cfg.startMonth
        let end = DU.addMonths(DU.ym(Date()), 1)
        var i = 0
        while k <= end && i < 60 { out.append(k); k = DU.addMonths(k, 1); i += 1 }
        return out
    }
}
