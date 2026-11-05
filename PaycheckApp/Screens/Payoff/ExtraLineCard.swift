import SwiftUI

/// Puts the extra payment on paychecks so you can tick it off against a specific debt.
struct ExtraLineCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let e = store.engine
        let on = e.extraRec != nil
        let when = e.extraRec?.when ?? store.state.extraWhen ?? "1"
        let focus = e.focusDebtId()
        VStack(alignment: .leading, spacing: 10) {
            Text("Extra payment on your paychecks").font(.headline)
            Text(on ? "Shows up as “Extra → \(e.debtName(focus))”. When you mark it paid, it’s recorded against that debt."
                    : "Add your \(money(store.state.extra)) extra as its own line so you can tick it off and see which debt it went to.")
                .font(.subheadline).foregroundStyle(.secondary)
            Picker("Which paycheck pays it", selection: Binding(get: { when }, set: { store.setExtraWhen($0) })) {
                Text("First paycheck (\(money(store.state.extra)))").tag("1")
                Text("Second paycheck (\(money(store.state.extra)))").tag("2")
                Text("Split across both").tag("each")
            }
            Button(on ? "Remove from paychecks" : "Add to paychecks") { store.setExtraLine(on: !on) }
                .buttonStyle(.borderedProminent)
                .tint(on ? .gray : Theme.accent)
                .disabled(!on && store.state.extra <= 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
