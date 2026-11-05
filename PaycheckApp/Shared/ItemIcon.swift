import SwiftUI

/// Icons for bills, categories and other items: a colored circle with an SF Symbol,
/// like most budgeting apps use. An item shows the icon picked in its editor
/// (Recurring.icon), or one guessed from its name, or one for its type.
enum ItemIcon {
    /// The icon for a recurring item.
    static func of(_ r: Recurring) -> String { r.icon ?? guess(r.name, type: r.type) }

    /// The icon for a paycheck line. One-time items have no Recurring, so they're guessed.
    static func of(_ l: Line, in state: BudgetState) -> String {
        if l.kind == "rec", let r = state.recurring.first(where: { $0.id == l.id }) { return of(r) }
        return guess(l.name, type: l.type)
    }

    /// Picks an icon from words in the name, falling back to one for the type.
    static func guess(_ name: String, type: String) -> String {
        // Match the start of each word, so "vacation" isn't a pet ("cat") and "groceries" is groceries ("grocer").
        let words = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        for (keys, icon) in keywords where keys.contains(where: { k in words.contains { $0.hasPrefix(k) } }) { return icon }
        switch type {
        case "bill": return "doc.text"
        case "subscription": return "arrow.triangle.2.circlepath"
        case "expense": return "bag"
        case "debt": return "creditcard"
        case "savings": return "banknote"
        default: return "star"
        }
    }

    /// Checked in order, so more specific words come first ("car insurance" → shield, and
    /// "credit card" → card before "car" can match it).
    private static let keywords: [([String], String)] = [
        (["insurance"], "shield"),
        (["student", "tuition", "school"], "graduationcap"),
        (["grocer", "food", "kroger", "walmart", "aldi"], "cart"),
        (["gas", "fuel"], "fuelpump"),
        (["rent", "mortgage", "hoa"], "house"),
        (["electric", "power", "energy"], "bolt"),
        (["water", "sewer"], "drop"),
        (["internet", "wifi", "wi-fi", "broadband"], "wifi"),
        (["phone", "iphone", "cell", "mobile", "verizon", "tmobile", "att"], "iphone"),
        (["credit", "card"], "creditcard"),
        (["car", "auto", "vehicle"], "car"),
        (["netflix", "hulu", "disney", "max", "stream", "tv"], "play.tv"),
        (["spotify", "music", "apple music"], "music.note"),
        (["gym", "fitness"], "dumbbell"),
        (["fun", "entertain"], "sparkles"),
        (["dining", "restaurant", "takeout", "eat"], "fork.knife"),
        (["coffee"], "cup.and.saucer"),
        (["pet", "dog", "cat", "vet"], "pawprint"),
        (["medical", "health", "doctor", "dental", "pharmacy"], "cross.case"),
        (["child", "kid", "daycare", "baby"], "figure.and.child.holdinghands"),
        (["gift", "birthday", "christmas", "holiday"], "gift"),
        (["travel", "vacation", "trip", "flight"], "airplane"),
        (["cloth", "shopping"], "tshirt"),
        (["hair", "beauty", "salon"], "scissors"),
        (["emergency"], "lifepreserver"),
        (["invest", "retire", "401k", "ira"], "chart.line.uptrend.xyaxis"),
        (["loan"], "building.columns"),
        (["saving"], "banknote"),
        (["trash", "garbage"], "trash"),
        (["cloud", "icloud", "storage"], "cloud"),
        (["game", "xbox", "playstation"], "gamecontroller"),
        (["book", "audible", "kindle"], "book"),
        (["church", "tithe", "donat", "charity"], "heart"),
    ]

    /// The choices in the editor's icon picker.
    static let choices = [
        "cart", "bag", "fuelpump", "car", "house", "bolt", "drop", "flame", "wifi", "iphone",
        "play.tv", "music.note", "gamecontroller", "book", "dumbbell", "fork.knife", "cup.and.saucer",
        "sparkles", "pawprint", "cross.case", "figure.and.child.holdinghands", "gift", "airplane",
        "tshirt", "scissors", "shield", "graduationcap", "building.columns", "creditcard", "banknote",
        "lifepreserver", "chart.line.uptrend.xyaxis", "heart", "cloud", "trash", "wrench.and.screwdriver",
        "doc.text", "arrow.triangle.2.circlepath", "star",
    ]
}

/// The colored circle with an item's icon, shown at the start of a row.
struct IconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: Circle())
            .accessibilityHidden(true)   // the row's name already says what it is
    }
}

/// A grid of icons to pick from, with "Automatic" to go back to the guess.
struct IconPicker: View {
    @Binding var icon: String?
    let name: String
    let type: String
    var body: some View {
        let color = TypeInfo.of(type).color
        let current = icon ?? ItemIcon.guess(name, type: type)
        VStack(alignment: .leading, spacing: Space.m) {
            Toggle("Automatic", isOn: Binding(get: { icon == nil }, set: { icon = $0 ? nil : current }))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: Space.s)], spacing: Space.s) {
                ForEach(ItemIcon.choices, id: \.self) { s in
                    Button { icon = s } label: {
                        IconBadge(icon: s, color: color, size: 40)
                            .overlay(Circle().strokeBorder(s == current ? color : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(s.replacingOccurrences(of: ".", with: " "))
                    .accessibilityAddTraits(s == current ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, Space.xs)
    }
}
