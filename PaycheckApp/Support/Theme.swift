import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
    /// Picks a different shade in dark mode.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

/// The lily pond palette, used as accents on a black and white base.
enum Theme {
    static let darkGreen = Color(hex: 0x0A3323)
    static let moss = Color(hex: 0x839958)
    static let beige = Color(hex: 0xF7F4D5)
    static let rosy = Color(hex: 0xD3968C)
    static let midnight = Color(hex: 0x105666)

    static let accent = Color.adaptive(light: 0x0A3323, dark: 0xD3968C)
    static let accentSoft = Color.adaptive(light: 0xF7F4D5, dark: 0x26231C)
    static let card = Color(.secondarySystemGroupedBackground)
    static let bg = Color(.systemGroupedBackground)
    static let good = Color.adaptive(light: 0x5E7A3A, dark: 0xA9BD7E)
    static let bad = Color.adaptive(light: 0xA8473D, dark: 0xE8A598)
    static let over = Color.adaptive(light: 0xB4534A, dark: 0xE8806F)
    static let track = Color(.tertiarySystemFill)
}

struct TypeInfo {
    let label: String
    let color: Color

    static let order = ["bill", "subscription", "expense", "debt", "savings"]

    static func of(_ t: String) -> TypeInfo {
        switch t {
        case "bill": return TypeInfo(label: "Bills", color: .adaptive(light: 0x105666, dark: 0x5AA4B4))
        case "subscription": return TypeInfo(label: "Subscriptions", color: .adaptive(light: 0x6A9FAE, dark: 0x9BCFD8))
        case "expense": return TypeInfo(label: "Spending", color: .adaptive(light: 0x839958, dark: 0xA9BD7E))
        case "debt": return TypeInfo(label: "Debt payments", color: .adaptive(light: 0xD3968C, dark: 0xD3968C))
        case "savings": return TypeInfo(label: "Savings", color: .adaptive(light: 0x0A3323, dark: 0xF7F4D5))
        default: return TypeInfo(label: t.capitalized, color: .gray)
        }
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
extension View {
    func card() -> some View { modifier(CardStyle()) }
}

/// Small rounded label, like "Autopay Nov 9".
struct Tag: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct ProgressBar: View {
    let value: Double          // 0...1
    var color: Color = Theme.moss
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: max(0, min(1, value)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}
