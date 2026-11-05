import Foundation
import WidgetKit

/// Shares a small summary with the home screen widget. The widget runs separately and
/// can't read the app's data, so the app writes this to the shared App Group folder.
/// Keep the fields in step with WidgetSummary in PaycheckWidget/PaycheckWidget.swift.
enum WidgetSync {
    static let groupId = "group.com.aubribowman.PaycheckApp"

    private struct Summary: Codable {
        var updated: Date
        var left: Double
        var paycheckDate: Date?
        var nextPayday: Date?
        var billsDue: Int
        var billsDueAmount: Double
        var pastDue: Int
        var spendingLeft: Double
        var spendingBudget: Double
        var goalName: String?
        var goalSaved: Double
        var goalTarget: Double
    }

    /// Writes the summary for the current paycheck and asks the widget to redraw.
    /// The goal shown is the first one not reached yet.
    static func write(_ e: Engine, goals: [Goal]) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId) else { return }
        let u = e.upcoming()
        var left = 0.0, budget = 0.0, spent = 0.0
        if let c = u.cur {
            left = e.totals(c.key, c.n).left
            for l in e.lines(c.key, c.n) where l.type == "expense" && !l.skip { budget += l.env; spent += l.spent }
        }
        let g = goals.first { e.goalStatus($0).left > 0.005 } ?? goals.first
        let st = g.map { e.goalStatus($0) }
        let s = Summary(updated: Date(), left: left, paycheckDate: u.cur?.date, nextPayday: u.next?.date,
                        billsDue: u.toPay.count, billsDueAmount: u.toPay.reduce(0) { $0 + $1.amount }, pastDue: u.overdue.count,
                        spendingLeft: budget - spent, spendingBudget: budget,
                        goalName: g?.name, goalSaved: st?.saved ?? 0, goalTarget: g?.target ?? 0)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(s) else { return }
        try? data.write(to: dir.appendingPathComponent("widget.json"), options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
