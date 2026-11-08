import Foundation

/// One row from a bank statement. `amount` is negative for money going out.
struct BankTx: Identifiable, Hashable {
    let id: String          // stable key, used to skip rows already imported
    let date: Date
    let desc: String
    let amount: Double
    var pocket: String = ""  // Crew and similar banks: the pocket/sub-account it came from
    var isOutflow: Bool { amount < 0 }
}

/// Why a file couldn't be read, worded for the import screen.
enum BankCSVError: LocalizedError {
    case empty, noColumns(String)
    var errorDescription: String? {
        switch self {
        case .empty: return "That file has no transactions in it."
        case .noColumns(let found):
            return "Couldn’t find date, description and amount columns. The file’s columns are: \(found)"
        }
    }
}

/// Reads the CSV files banks let you download. Finds the date, description and
/// amount columns by their header names, so most banks work without setup.
enum BankCSV {
    /// Turns a CSV file's text into transactions. Works with or without a header row.
    /// `flipSigns` is for banks (mostly credit cards) that list purchases as positive.
    static func parse(_ text: String, flipSigns: Bool = false) throws -> [BankTx] {
        let rows = splitRows(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !rows.isEmpty else { throw BankCSVError.empty }

        // Some banks put account info above the header, so look for the first row that names the columns.
        var dateCol: Int?, descCol: Int?, amtCol: Int?, debitCol: Int?, creditCol: Int?
        var pocketCol: Int?, typeCol: Int?, statusCol: Int?
        var firstData = 0

        if let h = rows.prefix(15).firstIndex(where: { r in
            let low = r.map { $0.lowercased() }
            return low.contains { $0.contains("date") || $0.contains("timestamp") || $0 == "time" }
                && low.contains { isAmountHeader($0) || $0.contains("debit") || $0.contains("withdraw") }
        }) {
            let head = rows[h].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            // The first column whose header contains one of `preferred` (checked in order),
            // skipping headers that contain any of `avoiding`.
            func col(_ preferred: [String], avoiding: [String] = []) -> Int? {
                for p in preferred {
                    if let i = head.firstIndex(where: { $0.contains(p) && !avoiding.contains(where: $0.contains) }) { return i }
                }
                return nil
            }
            dateCol = col(["transaction date", "trans. date", "trans date", "posted date", "posting date", "post date", "date", "timestamp", "time"])
            // "Title" is Crew's clean merchant name; "Account Name" is the account holder, so avoid it.
            descCol = col(["description", "payee", "merchant", "title", "name", "details", "memo", "transaction"],
                          avoiding: ["date", "type", "amount", "account", "card", "pocket"])
            amtCol = head.firstIndex(where: isAmountHeader)
            debitCol = col(["debit", "withdrawal", "withdraw", "money out"], avoiding: ["card"])
            creditCol = col(["credit", "deposit", "money in"], avoiding: ["card"])
            pocketCol = head.firstIndex { $0 == "pocket" || $0 == "sub-account" || $0 == "subaccount" }
            typeCol = head.firstIndex { $0 == "type" }
            statusCol = head.firstIndex { $0 == "status" }
            firstData = h + 1
        } else if let r = rows.first(where: { r in r.contains { parseDate($0) != nil } }) {
            // No header row (Wells Fargo and others): first date column, first money
            // column after it, and the longest text column as the description.
            dateCol = r.firstIndex { parseDate($0) != nil }
            // Prefer a value with cents, so an account number like "6599" isn't taken for the amount.
            amtCol = r.indices.first { $0 != dateCol && parseMoney(r[$0]) != nil && r[$0].contains(".") }
                ?? r.indices.first { $0 != dateCol && parseMoney(r[$0]) != nil }
            descCol = r.indices.filter { $0 != dateCol && $0 != amtCol && parseMoney(r[$0]) == nil }
                .max { r[$0].count < r[$1].count }
        }

        guard let dc = dateCol, let ds = descCol, amtCol != nil || debitCol != nil else {
            throw BankCSVError.noColumns(rows.first(where: { $0.count > 1 })?.joined(separator: ", ") ?? "none")
        }

        var out: [BankTx] = []
        var seen: [String: Int] = [:]
        for r in rows[firstData...] {
            // The text in column `i` of this row, or "" if the row is short or the column wasn't found.
            func cell(_ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0] : nil }?.trimmingCharacters(in: .whitespaces) ?? "" }
            guard let date = parseDate(cell(dc)) else { continue }
            // Money moved between your own pockets (Crew "subaccount") isn't spending.
            let type = cell(typeCol).lowercased()
            if type == "subaccount" || type == "internal transfer" { continue }
            // Pending card holds change or drop off once they clear, so wait for the cleared row.
            if cell(statusCol).lowercased() == "pending" { continue }
            let desc = cell(ds).replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            var amt: Double
            if let a = amtCol, let v = parseMoney(cell(a)) {
                amt = v
            } else {
                let out = parseMoney(cell(debitCol)).map { -abs($0) } ?? 0
                let inn = parseMoney(cell(creditCol)).map { abs($0) } ?? 0
                if out == 0 && inn == 0 { continue }
                amt = out + inn
            }
            if flipSigns { amt = -amt }
            // Same date, text and amount can happen twice in a day, so count repeats.
            let base = "\(DU.iso(date))|\(r2(amt))|\(desc.lowercased())"
            let k = seen[base, default: 0]; seen[base] = k + 1
            out.append(BankTx(id: "csv:" + base + (k > 0 ? "|\(k)" : ""), date: date, desc: desc, amount: r2(amt), pocket: cell(pocketCol)))
        }
        guard !out.isEmpty else { throw BankCSVError.empty }

        // With a single Amount column, most banks show spending as negative. If this
        // file is mostly positive, it uses the other convention, so flip it.
        if amtCol != nil, debitCol == nil, !flipSigns {
            let neg = out.filter { $0.amount < 0 }.count
            if neg * 2 < out.count {
                out = out.map { BankTx(id: $0.id, date: $0.date, desc: $0.desc, amount: -$0.amount, pocket: $0.pocket) }
            }
        }
        return out.sorted { $0.date > $1.date }
    }

    /// Headers like "Amount", "Amount (USD)" or "Transaction Amount".
    nonisolated private static func isAmountHeader(_ h: String) -> Bool {
        h == "amount" || h.hasPrefix("amount") || h.hasSuffix(" amount") || h.hasSuffix("amount")
    }

    /// "Kroger #123 Columbus OH" and "KROGER #456" both become "kroger", so one rule covers every store.
    static func merchantKey(_ desc: String) -> String {
        var s = desc.lowercased().trimmingCharacters(in: .whitespaces)
        for p in ["pos ", "debit card purchase ", "debit purchase ", "card purchase ", "purchase ", "recurring ", "ach ", "sq *", "sq*", "tst* ", "tst*", "pp*", "paypal *"] where s.hasPrefix(p) {
            s.removeFirst(p.count)
        }
        // Keep the name up to the first store number, so every location shares one rule.
        var words: [String] = []
        for token in s.split(separator: " ") {
            if token.contains(where: { $0.isNumber || $0 == "#" }) { break }
            let w = token.filter { $0.isLetter || $0 == "&" || $0 == "'" }
            if w.count > 1 { words.append(String(w)) }
            if words.count == 2 { break }
        }
        return words.joined(separator: " ")
    }

    // MARK: Low-level parsing

    static func splitRows(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false
        var it = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let n = it.next() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// Reads an amount the many ways banks write it: "$1,234.56", "-12.00",
    /// "(12.00)" or "12.00-" for negative, and "12.00 CR" / "12.00 DR".
    static func parseMoney(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        var neg = false
        if t.hasPrefix("(") && t.hasSuffix(")") { neg = true; t = String(t.dropFirst().dropLast()) }
        if t.hasSuffix("-") { neg = true; t.removeLast() }
        if t.hasPrefix("-") { neg = true; t.removeFirst() }
        if t.hasSuffix(" CR") { t.removeLast(3) }
        if t.hasSuffix(" DR") { neg = true; t.removeLast(3) }
        t = t.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let v = Double(t) else { return nil }
        return neg ? -v : v
    }

    private static let dateFormats = ["MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy", "yyyy-MM-dd", "yyyy/MM/dd", "MM-dd-yyyy", "dd MMM yyyy", "MMM d, yyyy"]
    private static let formatters: [DateFormatter] = dateFormats.map { f in
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.calendar = Calendar(identifier: .gregorian)
        d.dateFormat = f
        d.isLenient = false
        return d
    }

    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    /// Reads a date in any of `dateFormats` or as a full timestamp, and returns
    /// midnight local time on that day.
    static func parseDate(_ s: String) -> Date? {
        let full = s.trimmingCharacters(in: .whitespaces)
        // A full timestamp in UTC, like Crew's "2026-10-30 01:04:47.907000Z", is a
        // different day here in the evening, so convert it to your local date.
        if full.count > 16, full.hasSuffix("Z") || full.range(of: #"[+-]\d\d:?\d\d$"#, options: .regularExpression) != nil {
            let iso = full.replacingOccurrences(of: " ", with: "T")
                .replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
            if let d = isoFmt.date(from: iso) {
                return DU.date(DU.monthOf(d).y, DU.monthOf(d).m, DU.day(d))
            }
        }
        // Drop a time part like "10/31/2026 14:02" or "2026-10-31T00:00:00".
        let first = String(full.split(whereSeparator: { $0 == "T" || $0 == " " }).first ?? "")
        for f in formatters {
            if let d = f.date(from: full) ?? f.date(from: first) {
                let mo = DU.monthOf(d)
                let y = mo.y < 100 ? mo.y + 2000 : mo.y   // "10/31/26"
                return DU.date(y, mo.m, DU.day(d))
            }
        }
        return nil
    }
}
