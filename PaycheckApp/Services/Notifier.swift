import Foundation
import UserNotifications

/// Bill and payday reminders. Rebuilt whenever the budget changes (see Store.scheduleSave):
/// all pending reminders are removed and the next 35 days are scheduled again.
/// The on/off switch and hour live in UserDefaults, not the budget, so they stay per device.
enum Notifier {
    static let enabledKey = "remindersOn"
    static let hourKey = "reminderHour"           // hour of the day reminders go off, 0–23

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
    static var hour: Int { UserDefaults.standard.object(forKey: hourKey) as? Int ?? 9 }

    /// Shows the system's "Allow notifications?" prompt the first time. True if allowed.
    static func requestPermission() async -> Bool {
        let c = UNUserNotificationCenter.current()
        return (try? await c.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    @MainActor
    static func reschedule(_ e: Engine) async {
        // iOS keeps at most 64 pending notifications per app, so this sends the soonest 60.
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }

        let today = DU.today, horizon = DU.addDays(today, 35)
        var items: [(Date, String, String, String)] = []   // fire date, id, title, body

        // Bills: the day before they're due (unpaid, not skipped).
        let cur = DU.ym(Date())
        for k in [DU.addMonths(cur, -1), cur, DU.addMonths(cur, 1)] where k >= e.cfg.startMonth {
            for c in e.checksIn(k) {
                for l in e.lines(k, c.n) where l.kind == "rec" && !l.paid && !l.skip && !l.isEnv {
                    guard let due = l.dueDate, due > today, due <= horizon else { continue }
                    let fire = DU.addDays(due, -1)
                    let title = l.autopay ? "\(l.name) comes out tomorrow" : "\(l.name) is due tomorrow"
                    let body = l.aside ? "\(money(l.amount)) is set aside for it." : "\(money(l.amount)) from your \(DU.short(c.date)) paycheck."
                    items.append((fire, "bill-\(l.id)-\(DU.iso(due))", title, body))
                }
            }
        }
        // Paydays.
        var d = today
        while d <= horizon {
            for c in e.checksIn(DU.ym(d)) where DU.iso(c.date) == DU.iso(d) && c.date > today {
                let toPay = e.lines(c.key, c.n).filter { $0.kind == "rec" && !$0.paid && !$0.aside && !$0.autopay && !$0.skip && !$0.isEnv }
                let total = toPay.reduce(0) { $0 + $1.amount }
                items.append((c.date, "pay-\(DU.iso(c.date))", "Payday",
                              toPay.isEmpty ? "Nothing to pay by hand from this check." : "\(toPay.count) bills to pay from this check, \(money(total))."))
            }
            d = DU.addDays(d, 1)
        }

        for (fire, id, title, body) in items.sorted(by: { $0.0 < $1.0 }).prefix(60) {
            var comps = DU.cal.dateComponents([.year, .month, .day], from: fire)
            comps.hour = hour
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let req = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
    }
}
