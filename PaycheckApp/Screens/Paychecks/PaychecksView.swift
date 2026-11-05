import SwiftUI

/// The Paychecks tab: each paycheck in the month as a card (CheckCard), with its
/// lines grouped by type. Most edits happen in LineSheet, opened by tapping a line.
struct PaychecksView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PageTitle("Paychecks")
                    MonthPill()
                    if store.isEmpty {
                        EmptyStart()
                    } else {
                        UpcomingCard()
                        ForEach(store.engine.checksIn(store.month), id: \.self) { c in
                            CheckCard(check: c)
                        }
                        StatusLegend()
                    }
                }
                .padding()
                .readableWidth()
            }
            .background(Theme.bg)
            .monthScreen("Paychecks")
        }
    }
}
