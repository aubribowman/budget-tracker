import Foundation

/// Reads the positions file Fidelity gives you on fidelity.com: Accounts & Trade →
/// Portfolio → Positions → Download. It's a CSV with one row per holding in every account.
///
/// Fidelity has used two layouts. Newer files have "Account Number" and "Account Name"
/// columns; older ones have one "Account Name/Number" column. Both are read by column
/// name, so extra or reordered columns don't matter. Also handled:
/// - money market cash ("SPAXX**", "HELD IN MONEY MARKET"), counted as cash
/// - "Pending Activity" rows, counted as cash so the total matches Fidelity's
/// - "--" or "n/a" for numbers Fidelity doesn't have, like the cost of cash
/// - the notes and "Date downloaded" lines at the bottom, which are skipped
enum FidelityCSV {
    /// One account found in the file.
    struct Account: Identifiable, Equatable {
        var number: String
        var name: String
        var holdings: [Holding]
        /// The number if there is one, else the name. Used to match it on the next import.
        var key: String { number.isEmpty ? name : number }
        var id: String { key }
        var total: Double { holdings.reduce(0) { $0 + $1.value } }
    }

    enum ParseError: LocalizedError {
        case notPositions
        case empty
        var errorDescription: String? {
            switch self {
            case .notPositions: return "That doesn’t look like a Fidelity positions file. On fidelity.com, open Positions and choose Download."
            case .empty: return "No holdings were found in that file."
            }
        }
    }

    static func parse(_ text: String) throws -> [Account] {
        let rows = BankCSV.splitRows(text.replacingOccurrences(of: "\u{FEFF}", with: ""))
        // The header is the first row that names both a symbol and a value column.
        guard let hi = rows.firstIndex(where: { r in
            let h = r.map(norm)
            return h.contains("symbol") && h.contains("current value")
        }) else { throw ParseError.notPositions }
        let header = rows[hi].map(norm)
        func col(_ names: String...) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }
        let cNumber = col("account number"), cName = col("account name"), cBoth = col("account name/number")
        let cSymbol = col("symbol"), cDesc = col("description"), cQty = col("quantity")
        let cPrice = col("last price"), cValue = col("current value")
        let cCost = col("cost basis total", "cost basis"), cType = col("type")

        var order: [String] = []
        var byKey: [String: Account] = [:]
        for r in rows[(hi + 1)...] {
            func cell(_ i: Int?) -> String {
                guard let i, i < r.count else { return "" }
                return r[i].trimmingCharacters(in: .whitespaces)
            }
            // Holding rows have an account and a value; the notes at the bottom have neither.
            var number = cell(cNumber), name = cell(cName)
            if cNumber == nil, !cell(cBoth).isEmpty { (name, number) = splitNameNumber(cell(cBoth)) }
            guard !(number.isEmpty && name.isEmpty), let value = num(cell(cValue)) else { continue }

            var h = Holding()
            let rawSymbol = cell(cSymbol)
            let desc = cell(cDesc)
            h.symbol = rawSymbol.replacingOccurrences(of: "*", with: "")
            h.name = desc
            h.value = r2(value)
            h.shares = num(cell(cQty)) ?? 0
            h.price = num(cell(cPrice)) ?? 0
            h.cost = num(cell(cCost)).map(r2)
            let pending = rawSymbol.lowercased().hasPrefix("pending")
            h.cash = pending || rawSymbol.hasSuffix("**") || desc.uppercased().contains("MONEY MARKET")
                || (cell(cType).lowercased() == "cash" && h.shares == 0)
            if pending { h.symbol = ""; h.name = "Pending activity" }
            if h.cash { h.cost = nil }   // cash has no gain or loss

            let key = number.isEmpty ? name : number
            if byKey[key] == nil { order.append(key); byKey[key] = Account(number: number, name: name, holdings: []) }
            byKey[key]?.holdings.append(h)
        }
        let out = order.compactMap { byKey[$0] }
        if out.isEmpty { throw ParseError.empty }
        return out
    }

    /// The day the file was downloaded, from its "Date downloaded Nov-10-2026 ..." line.
    static func downloaded(_ text: String) -> Date? {
        guard let r = text.range(of: "Date downloaded") else { return nil }
        let rest = text[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " \":"))
        let word = rest.prefix { !$0.isWhitespace && $0 != "\"" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["MMM-dd-yyyy", "MM/dd/yyyy"] {
            f.dateFormat = fmt
            if let d = f.date(from: String(word)) { return d }
        }
        return nil
    }

    // MARK: Helpers

    /// Header text, lowercased and trimmed.
    nonisolated private static func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).lowercased() }

    /// A number from "$1,234.56", "+$12.30", "-$5.00", "12.5%". nil for "", "--" or "n/a".
    static func num(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t == "--" || t.lowercased() == "n/a" { return nil }
        t = t.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "+", with: "")
        return BankCSV.parseMoney(t)
    }

    /// Older files write "ROTH IRA Z12345678" or "Z12345678 ROTH IRA" in one column.
    /// The account number is the word with digits in it.
    static func splitNameNumber(_ s: String) -> (name: String, number: String) {
        let words = s.split(separator: " ").map(String.init)
        guard let i = words.lastIndex(where: { w in w.count >= 5 && w.contains(where: \.isNumber) }) else { return (s, "") }
        var rest = words; rest.remove(at: i)
        return (rest.joined(separator: " "), words[i])
    }
}
