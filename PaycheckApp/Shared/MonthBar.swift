import SwiftUI

/// Month switcher used at the top of several tabs.
struct MonthBar: View {
    @EnvironmentObject var store: Store
    var body: some View {
        HStack {
            Button { store.month = DU.addMonths(store.month, -1) } label: { Image(systemName: "chevron.left") }
            Text(DU.monthLabel(store.month)).font(.headline).frame(minWidth: 140)
            Button { store.month = DU.addMonths(store.month, 1) } label: { Image(systemName: "chevron.right") }
            if store.month != DU.ym(Date()) {
                Button("Today") { store.month = DU.ym(Date()) }.font(.subheadline)
            }
        }
    }
}
