import SwiftUI

/// A purchase's badge: the store's first letter in a colored circle ("K" for Kroger),
/// like a card statement. The color comes from the store's name, so the same store
/// always looks the same and different stores are easy to tell apart.
/// Purchases with no name show the category's icon instead.
struct MerchantBadge: View {
    let note: String
    let fallbackIcon: String
    let color: Color
    var size: CGFloat = 32

    var body: some View {
        if let m = Merchant(note) {
            Text(m.letter)
                .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(m.color, in: Circle())
                .accessibilityHidden(true)   // the row's name already says what it is
        } else {
            IconBadge(icon: fallbackIcon, color: color, size: size)
        }
    }
}

/// The store behind a purchase name, for its letter and color.
struct Merchant {
    let key: String       // "kroger", from "KROGER #456 DUBLIN OH" or "Kroger"
    let letter: String    // "K"

    init?(_ note: String) {
        let name = Merchant.clean(note)
        guard let first = name.split(separator: " ").first, let ch = first.first else { return nil }
        key = String(first)
        letter = String(ch).uppercased()
    }

    /// One of a set of colors that read well with white text in light and dark mode.
    /// Picked by a fixed sum of the name's letters (not Swift's hashValue, which changes
    /// every launch), so a store keeps its color.
    var color: Color {
        let sum = key.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return Merchant.palette[abs(sum) % Merchant.palette.count]
    }

    static let palette: [Color] = [
        Color(hex: 0x105666),   // teal
        Color(hex: 0x5E7A3A),   // olive
        Color(hex: 0xB4534A),   // brick
        Color(hex: 0x6B4E8A),   // plum
        Color(hex: 0xB07A22),   // ochre
        Color(hex: 0x2F6E8E),   // blue
        Color(hex: 0x8A5A44),   // brown
        Color(hex: 0x4E7D6B),   // sage
        Color(hex: 0xA0577A),   // berry
        Color(hex: 0x50606E),   // slate
    ]

    /// "SQ *KROGER #456 DUBLIN OH" → "kroger dublin oh": lowercased, without
    /// payment-processor prefixes, store numbers, or anything after a "#" or "*".
    static func clean(_ note: String) -> String {
        var s = note.lowercased().trimmingCharacters(in: .whitespaces)
        for p in ["sq *", "sq*", "tst* ", "tst*", "dd *", "dd*", "pp*", "paypal *", "pos ", "debit ", "purchase ", "checkcard "] where s.hasPrefix(p) {
            s.removeFirst(p.count)
        }
        if let i = s.firstIndex(where: { $0 == "#" || $0 == "*" }) { s = String(s[..<i]) }
        s = s.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        let words = s.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "&" })
            .map(String.init)
            .filter { !$0.allSatisfy(\.isNumber) }   // store numbers
        return words.joined(separator: " ")
    }
}
