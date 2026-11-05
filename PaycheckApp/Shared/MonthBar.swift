import SwiftUI

/// Month switcher used at the top of the Paychecks, Purchases and Month tabs.
/// On iPhone it sits under the tab's big title (MonthPill); on Mac it's in the toolbar.
struct MonthBar: View {
    @EnvironmentObject var store: Store
    var body: some View {
        HStack {
            Button { store.month = DU.addMonths(store.month, -1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
            Text(DU.monthLabel(store.month)).font(.ui(.headline)).frame(minWidth: 140)
                .contentTransition(.numericText())
            Button { store.month = DU.addMonths(store.month, 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next month")
            if store.month != DU.ym(Date()) {
                Button("Today") { store.month = DU.ym(Date()) }.font(.ui(.subheadline))
            }
        }
        .animation(.snappy, value: store.month)
        .sensoryFeedback(.selection, trigger: store.month)
    }
}

/// iPhone: the month switcher as a rounded pill at the top of the page, under the big title.
/// Mac: nothing, since the switcher is in the toolbar there (see `monthScreen`).
struct MonthPill: View {
    var body: some View {
        #if os(iOS)
        MonthBar()
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background(Theme.card, in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

extension View {
    /// The top of a tab that has a month switcher: a big title like every other tab,
    /// with the switcher under it on iPhone (put MonthPill first in the page) and in
    /// the toolbar on Mac.
    func monthScreen(_ title: String) -> some View {
        #if os(macOS)
        navigationTitle(title).toolbar { ToolbarItem(placement: .principal) { MonthBar() } }
        #else
        pageTitle(title)
        #endif
    }
}
