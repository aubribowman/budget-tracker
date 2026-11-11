import Foundation
import Security

/// Daily prices for investment holdings, from Tiingo's end-of-day API (tiingo.com).
///
/// You get a free key at tiingo.com and paste it into Setup → Investment prices. Once a day,
/// the app asks Tiingo for the latest closing price of each symbol you hold (FXAIX, VTI…)
/// and sets each holding's value to shares × price. Only the symbols are sent: no account
/// numbers, balances or anything else from your budget. Mutual fund prices (NAVs) come out
/// after midnight Eastern, so they're the previous trading day's.
///
/// Share counts still come from your last Fidelity import or edit, so import again after
/// you buy or sell. Free plan limits: 50 requests an hour, 1,000 a day, 500 symbols a month.
enum PriceService {
    /// Turns daily updates on or off (Setup → Investment prices). Off until a key is added.
    static let enabledKey = "priceUpdatesOn"
    /// When this device last asked for prices, so it asks at most every few hours.
    static let lastTryKey = "priceLastTry"
    /// What happened last time, shown in Setup.
    static let statusKey = "priceStatus"
    /// Hours between automatic updates on one device.
    static let everyHours = 6.0

    /// One closing price.
    struct Quote: Equatable {
        var close: Double
        var date: String        // yyyy-MM-dd, the trading day it's from
    }

    enum PriceError: LocalizedError, Equatable {
        case noKey
        case badKey
        case tooMany
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add your Tiingo key to update prices."
            case .badKey: return "Tiingo didn’t accept the key. Check it on tiingo.com under Account → API → Token."
            case .tooMany: return "Tiingo’s free limit was reached. Prices will update later."
            case .failed(let why): return "Couldn’t get prices: \(why)"
            }
        }
    }

    /// The result of asking for a list of symbols.
    struct Result: Equatable {
        var quotes: [String: Quote] = [:]   // by the symbol as you hold it (FXAIX, BRK.B)
        var missing: [String] = []          // symbols Tiingo doesn't know
        var error: PriceError? = nil        // stops the whole update (bad key, limit, offline)
    }

    /// Sends a request and returns the response. Tests pass a fake one.
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Tiingo writes share classes with a hyphen: BRK.B and BRK/B are "BRK-B".
    nonisolated static func tiingoSymbol(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).uppercased()
            .replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "/", with: "-")
    }

    /// GET https://api.tiingo.com/tiingo/daily/<symbol>/prices with the key in the
    /// Authorization header (so it doesn't end up in a URL or log).
    nonisolated static func request(symbol: String, key: String) -> URLRequest? {
        let sym = tiingoSymbol(symbol)
        guard !sym.isEmpty, let enc = sym.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.tiingo.com/tiingo/daily/\(enc)/prices") else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return r
    }

    /// Reads Tiingo's answer: a list of daily prices, newest last. Uses the last `close`.
    nonisolated static func parse(_ data: Data) -> Quote? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let last = list.last,
              let close = (last["close"] as? NSNumber)?.doubleValue, close > 0,
              let date = last["date"] as? String, date.count >= 10 else { return nil }
        return Quote(close: close, date: String(date.prefix(10)))
    }

    /// Asks for each symbol in turn. A bad key, the rate limit or no connection stops early;
    /// an unknown symbol is noted in `missing` and the rest carry on.
    static func fetch(symbols: [String], key: String,
                      using send: Fetch = { try await URLSession.shared.data(for: $0) }) async -> Result {
        var out = Result()
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { out.error = .noKey; return out }
        for sym in Array(Set(symbols)).sorted() {
            guard let req = request(symbol: sym, key: key) else { continue }
            do {
                let (data, resp) = try await send(req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
                switch code {
                case 200..<300:
                    if let q = parse(data) { out.quotes[sym] = q }
                    else if detail(data)?.lowercased().contains("token") == true { out.error = .badKey; return out }
                    else { out.missing.append(sym) }
                case 401, 403: out.error = .badKey; return out
                case 404: out.missing.append(sym)
                case 429: out.error = .tooMany; return out
                default: out.error = .failed(detail(data) ?? "Tiingo answered with error \(code)."); return out
                }
            } catch {
                out.error = .failed(error.localizedDescription)
                return out
            }
        }
        return out
    }

    /// Tiingo's error text, from a body like {"detail": "…"}.
    nonisolated private static func detail(_ data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
    }

    // MARK: The key

    /// The Tiingo key, kept in this device's keychain (not in the budget file, so it isn't
    /// synced or backed up). Enter it on each device that should update prices.
    enum Key {
        private static let service = "PaycheckApp.tiingo"
        private static let account = "apiKey"

        static func get() -> String? {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
            var item: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let d = item as? Data else { return nil }
            return String(data: d, encoding: .utf8)
        }

        /// Saves the key, or removes it when empty. Returns false if the keychain refused.
        @discardableResult
        static func set(_ key: String) -> Bool {
            let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                       kSecAttrAccount as String: account]
            SecItemDelete(base as CFDictionary)
            let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty else { return true }
            var add = base
            add[kSecValueData as String] = Data(k.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
    }
}

// MARK: - Applying prices

extension BudgetState {
    /// Symbols worth asking about: holdings that aren't cash and have shares.
    var priceSymbols: [String] {
        Array(Set(accounts.flatMap { $0.holdings }.filter { !$0.cash && $0.shares > 0 && !$0.symbol.isEmpty }.map(\.symbol))).sorted()
    }

    /// Sets each matching holding's price and value (shares × price). Share counts, cash
    /// and the snapshot time stay as they are, so paycheck contributions keep counting.
    /// Returns true if anything changed, and then records today's values for the chart.
    @discardableResult
    mutating func applyPrices(_ quotes: [String: PriceService.Quote]) -> Bool {
        var changed = false
        for a in accounts.indices {
            for h in accounts[a].holdings.indices {
                let old = accounts[a].holdings[h]
                guard !old.cash, old.shares > 0, let q = quotes[old.symbol] else { continue }
                var new = old
                new.price = q.close
                new.value = r2(old.shares * q.close)
                new.priceAt = q.date
                if new != old { accounts[a].holdings[h] = new; changed = true }
            }
        }
        if changed { recordValues() }
        return changed
    }
}
