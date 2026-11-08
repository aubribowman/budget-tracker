import SwiftUI

// Colors and small shared pieces of UI. Use these instead of hard-coded colors so
// light mode, dark mode and the Mac all stay consistent.

extension Color {
    /// A color from a hex value like 0x0A3323.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
    /// Picks a different shade in dark mode.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        SystemColor.adaptive(light: Color(hex: light), dark: Color(hex: dark))
    }
}

/// The lily pond palette, used as accents on a black and white base.
enum Theme {
    static let darkGreen = Color(hex: 0x0A3323)
    static let moss = Color(hex: 0x839958)
    static let beige = Color(hex: 0xF7F4D5)
    static let rosy = Color(hex: 0xD3968C)
    static let midnight = Color(hex: 0x105666)

    // Use these in screens; the named colors above are the raw palette.
    static let accent = Color.adaptive(light: 0x0A3323, dark: 0xD3968C)
    static let accentSoft = Color.adaptive(light: 0xF7F4D5, dark: 0x26231C)
    static let card = SystemColor.card
    static let leadCard = Color.adaptive(light: 0xE7EDDA, dark: 0x232B1A)   // pale moss; the one card a screen leads with
    static let bg = SystemColor.bg
    static let good = Color.adaptive(light: 0x5E7A3A, dark: 0xA9BD7E)   // money left, on track
    static let bad = Color.adaptive(light: 0xA8473D, dark: 0xE8A598)    // below zero, past due
    static let over = Color.adaptive(light: 0xB4534A, dark: 0xE8806F)   // spending over budget
    static let track = SystemColor.track
}

/// The display name and color for each item type (Recurring.type).
struct TypeInfo {
    let label: String
    let color: Color

    /// The order type groups appear in on a paycheck.
    static let order = ["bill", "subscription", "expense", "debt", "savings"]

    /// The label and color for a type id. An unknown type shows its id capitalized, in gray.
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

/// Spacing steps. Pick from these instead of typing a number, so gaps line up across screens.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16      // card padding, gap between cards
    static let xl: CGFloat = 24
}

/// Corner rounding. `card` for cards, `inner` for boxes inside or beside them.
enum Radius {
    static let card: CGFloat = 20
    static let inner: CGFloat = 14
}

/// The rounded white card most screens are built from. Apply with `.card()`.
/// Pass a tint (like Theme.leadCard) for the one card a screen should lead with.
struct CardStyle: ViewModifier {
    var tint: Color = Theme.card
    func body(content: Content) -> some View {
        content
            .padding(Space.l)
            .background(tint, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            #if os(macOS)
            // A faint edge and shadow so cards read as containers on a big screen.
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            #endif
    }
}
extension View {
    /// Puts the view in a rounded card (see CardStyle).
    func card(tint: Color = Theme.card) -> some View { modifier(CardStyle(tint: tint)) }
}

/// The heading at the top of a card. Every card uses this so headings look the same
/// on every screen. Accent color with an icon; plain text without one.
struct CardHeader: View {
    let title: String
    var icon: String? = nil
    init(_ title: String, icon: String? = nil) { self.title = title; self.icon = icon }
    var body: some View {
        Group {
            if let icon { Label(title, systemImage: icon) } else { Text(title) }
        }
        .font(.display(.headline, weight: .bold))
        .foregroundStyle(Theme.accent)
        // One line normally; at the largest text sizes, wrap rather than cut the heading off.
        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        .accessibilityAddTraits(.isHeader)
    }
    @Environment(\.dynamicTypeSize) private var typeSize
}

/// The big money number a card leads with. Grows with the user's text size, and
/// rolls to the new value when it changes instead of jumping.
struct HeroNumber: ViewModifier {
    let value: Double
    var weight: Font.Weight = .bold
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40
    init(value: Double, size: CGFloat, weight: Font.Weight = .bold) {
        self.value = value; self.weight = weight
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }
    func body(content: Content) -> some View {
        content
            .font(.display(size: size, weight: weight))
            .monospacedDigit()
            // Never break a dollar amount across lines; shrink it to fit instead.
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText(value: value))
            .animation(.snappy, value: value)
    }
}
extension View {
    /// Style for a card's main money figure. `size` is the size at the default text setting.
    func heroNumber(_ value: Double, size: CGFloat = 40, weight: Font.Weight = .bold) -> some View {
        modifier(HeroNumber(value: value, size: size, weight: weight))
    }

    /// For smaller money figures that should still roll to their new value.
    func rollingNumber(_ value: Double) -> some View {
        contentTransition(.numericText(value: value)).animation(.snappy, value: value)
    }
}

/// Lays children out left to right and wraps to a new line when out of room, like words.
struct FlowLayout: Layout {
    var spacing: CGFloat = Space.m
    var lineSpacing: CGFloat = Space.xs

    /// How tall the wrapped rows are at the width offered.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews)
        let h = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: h)
    }

    /// Places each row left to right, centering items vertically within their row.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    // One line of items: their indexes, total width and the tallest item's height.
    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    /// Splits the items into lines, starting a new line when the next item won't fit.
    private func rows(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].items.isEmpty ? 0 : spacing
            rows[rows.count - 1].items.append(i)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

/// Small rounded label, like "Autopay Nov 9".
struct Tag: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text)
            .font(.ui(.caption2).weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Remembers which sections are folded, across launches. Stored as a comma list in
/// @AppStorage("folded"), so every screen shares one setting.
enum Fold {
    static let key = "folded"
    /// True if section `id` is in the saved list (that is, it's folded).
    static func has(_ raw: String, _ id: String) -> Bool { raw.split(separator: ",").contains { $0 == id } }
    /// The saved list with `id` added if it wasn't there, or removed if it was.
    static func toggled(_ raw: String, _ id: String) -> String {
        var ids = raw.split(separator: ",").map(String.init)
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
        return ids.joined(separator: ",")
    }
}

/// Points down when open, right when folded.
struct FoldChevron: View {
    let folded: Bool
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.ui(.caption).weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(folded ? -90 : 0))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel(folded ? "Expand" : "Collapse")
    }
}

/// A ring that fills clockwise, with the percent in the middle.
struct ProgressRing: View {
    let value: Double          // 0...1
    var color: Color = Theme.moss
    var lineWidth: CGFloat = 8
    var body: some View {
        let v = max(0, min(1, value))
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle().trim(from: 0, to: v)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(Int((v * 100).rounded()))%").font(.display(.subheadline, weight: .bold)).monospacedDigit()
                Text("paid").font(.ui(.caption2)).foregroundStyle(.secondary)
            }
            .dynamicTypeSize(...DynamicTypeSize.large)   // the ring is a fixed size, so its label can't grow
            .minimumScaleFactor(0.7)
        }
        .animation(.snappy, value: v)
    }
}

/// A thin rounded progress bar.
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
        .animation(.snappy, value: value)   // slide to the new amount instead of jumping
        .accessibilityElement()
        .accessibilityValue("\(Int((max(0, min(1, value)) * 100).rounded())) percent")
    }
}
