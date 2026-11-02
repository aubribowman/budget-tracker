import Foundation

/// Date helpers. Months are "yyyy-MM" strings and days are "yyyy-MM-dd",
/// the same format the web app uses, so backups move between the two.
enum DU {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    private static let shortFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f }()
    private static let monthFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f }()
    private static let monthShortFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f }()
    private static let monthOnlyFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM"; return f }()

    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
    }
    static func ym(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month], from: d)
        return String(format: "%04d-%02d", c.year ?? 2026, c.month ?? 1)
    }
    static func iso(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }
    static func parseISO(_ s: String) -> Date? {
        let p = s.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return date(p[0], p[1], p[2])
    }
    static func parseYM(_ k: String) -> (y: Int, m: Int) {
        let p = k.split(separator: "-")
        let y = p.count > 0 ? Int(p[0]) ?? 2026 : 2026
        let m = p.count > 1 ? Int(p[1]) ?? 1 : 1
        return (y, m)
    }
    static func addMonths(_ k: String, _ n: Int) -> String {
        let (y, m) = parseYM(k)
        let t = y * 12 + (m - 1) + n
        return String(format: "%04d-%02d", t / 12, t % 12 + 1)
    }
    static func monthsDiff(_ a: String, _ b: String) -> Int {
        let A = parseYM(a), B = parseYM(b)
        return (B.y - A.y) * 12 + (B.m - A.m)
    }
    static func lastDay(_ y: Int, _ m: Int) -> Int {
        cal.range(of: .day, in: .month, for: date(y, m, 1))?.count ?? 30
    }
    static func firstOfMonth(_ k: String) -> Date { let (y, m) = parseYM(k); return date(y, m, 1) }
    static func startOfDay(_ d: Date) -> Date { cal.startOfDay(for: d) }
    static var today: Date { cal.startOfDay(for: Date()) }
    static func addDays(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: d) ?? d }
    static func days(_ a: Date, _ b: Date) -> Int {
        cal.dateComponents([.day], from: startOfDay(a), to: startOfDay(b)).day ?? 0
    }
    static func weekday(_ d: Date) -> Int { cal.component(.weekday, from: d) }   // 1 = Sun, 7 = Sat
    static func day(_ d: Date) -> Int { cal.component(.day, from: d) }
    static func monthOf(_ d: Date) -> (y: Int, m: Int) {
        let c = cal.dateComponents([.year, .month], from: d); return (c.year ?? 2026, c.month ?? 1)
    }

    static func short(_ d: Date) -> String { shortFmt.string(from: d) }
    static func dayLabel(_ d: Date) -> String { dayFmt.string(from: d) }
    static func monthLabel(_ k: String, short: Bool = false) -> String {
        (short ? monthShortFmt : monthFmt).string(from: firstOfMonth(k))
    }
    static func monthName(_ k: String) -> String { monthOnlyFmt.string(from: firstOfMonth(k)) }
    static func range(_ a: Date, _ b: Date) -> String {
        let A = monthOf(a), B = monthOf(b)
        return (A.y == B.y && A.m == B.m) ? "\(short(a))–\(day(b))" : "\(short(a))–\(short(b))"
    }
    static func ordinal(_ n: Int) -> String {
        let s = ["th", "st", "nd", "rd"], v = n % 100
        let i = (v - 20) % 10
        let suf = (i >= 1 && i <= 3) ? s[i] : (v >= 1 && v <= 3 ? s[v] : s[0])
        return "\(n)\(suf)"
    }

    /// Accepts "2026-10", "October 2026", "Oct 2026", "10/2026". Returns nil if unreadable, "" if empty.
    static func normMonth(_ raw: String) -> String? {
        let v = raw.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { return "" }
        let names = ["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"]
        let nums = v.split(whereSeparator: { "-/., ".contains($0) }).map(String.init)
        var y = 0, m = 0
        if nums.count >= 2, let a = Int(nums[0]), let b = Int(nums[1]) {
            if a > 1000 { y = a; m = b } else if nums.count >= 3, let c = Int(nums[2]), c > 1000 { y = c; m = a } else if b > 1000 { y = b; m = a }
        } else {
            let low = v.lowercased()
            if let i = names.firstIndex(where: { low.hasPrefix($0) }), let yy = nums.last.flatMap({ Int($0) }) { m = i + 1; y = yy }
        }
        guard y >= 2000, y <= 2100, m >= 1, m <= 12 else { return nil }
        return String(format: "%04d-%02d", y, m)
    }
}

private let moneyFmt: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.locale = Locale(identifier: "en_US")
    return f
}()
private let money0Fmt: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.locale = Locale(identifier: "en_US")
    f.maximumFractionDigits = 0
    return f
}()

func money(_ v: Double) -> String {
    let s = moneyFmt.string(from: NSNumber(value: (v * 100).rounded() / 100)) ?? "$0.00"
    return s.replacingOccurrences(of: "-", with: "−")
}
func money0(_ v: Double) -> String {
    (money0Fmt.string(from: NSNumber(value: v.rounded())) ?? "$0").replacingOccurrences(of: "-", with: "−")
}
func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

func newId(_ prefix: String) -> String { prefix + UUID().uuidString.prefix(7).lowercased() }
