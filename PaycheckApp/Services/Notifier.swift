import Foundation
import UserNotifications

/// Bill, payday and card statement reminders, plus the reminder to reinstall before the app expires
/// (AppExpiry.swift). Rebuilt whenever the budget changes (see Store.scheduleSave):
/// all pending reminders are removed and the next 35 days are scheduled again.
/// The on/off switches and hour live in UserDefaults, not the budget, so they stay per device.
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
        await scheduleExpiry(center)
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
        // Card statements: the day before each one closes, while there's a balance. The
        // balance on that day is what gets reported to credit bureaus, so this is the time
        // to pay it down. Up to two per card fit in the 35 days.
        for debt in e.s.debts {
            let bal = e.curBal(debt)
            guard bal > 0.005, var close = debt.nextStatement(from: DU.addDays(today, 1)) else { continue }
            while close <= horizon {
                var body = "Balance today: \(money(bal))."
                if let lim = debt.limit, lim > 0 {
                    let pct = Int((bal / lim * 100).rounded())
                    let to30 = max(0, bal - lim * 0.3)
                    body += " That's \(pct)% of your limit" + (to30 > 0.005 ? "; pay \(money(to30)) to report under 30%." : ".")
                } else {
                    body += " Paying before it closes lowers what's reported."
                }
                items.append((DU.addDays(close, -1), "stmt-\(debt.id)-\(DU.iso(close))", "\(debt.name) statement closes tomorrow", body))
                guard let next = debt.nextStatement(from: DU.addDays(close, 1)) else { break }
                close = next
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

        // 60 plus up to 2 reinstall reminders stays under the limit.
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

    /// Called at launch. A reinstall doesn't change the budget, so nothing else would set
    /// the reinstall reminders up again. Asks for permission first (iOS only shows the
    /// prompt once). Does nothing on builds that don't expire.
    @MainActor
    static func setUpExpiryReminder(_ e: Engine) async {
        guard AppExpiry.date != nil, AppExpiry.reminderOn else { return }
        guard await requestPermission() else { return }
        await reschedule(e)
    }

    /// Two reminders to reinstall before the app expires: at the reminder hour on two of the
    /// last three days (the expiry day counts if it's still more than an hour before expiry).
    /// Runs even with bill reminders off, since it has its own switch.
    @MainActor
    private static func scheduleExpiry(_ center: UNUserNotificationCenter) async {
        guard AppExpiry.reminderOn, let expires = AppExpiry.date else { return }
        let now = Date()
        let day = DU.startOfDay(expires)
        let times = [-2, -1, 0].compactMap { DU.cal.date(bySettingHour: hour, minute: 0, second: 0, of: DU.addDays(day, $0)) }
            .filter { $0 > now && $0 < expires.addingTimeInterval(-3600) }
        for t in times.suffix(2) {
            let content = UNMutableNotificationContent()
            content.title = "Reinstall Paycheck Plan"
            content.body = "This copy stops opening \(AppExpiry.label(expires, now: t)). Run it from Xcode again before then. Your budget stays."
            content.sound = .default
            let comps = DU.cal.dateComponents([.year, .month, .day, .hour, .minute], from: t)
            let req = UNNotificationRequest(identifier: "expiry-\(DU.iso(t))", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
    }
}
