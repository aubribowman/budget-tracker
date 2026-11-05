import SwiftUI

/// How and when you're paid: semi-monthly or biweekly, paydays, weekend rule, pay-ahead.
struct ScheduleView: View {
    @EnvironmentObject var store: Store

    func bind<T>(_ kp: WritableKeyPath<BudgetSettings, T>) -> Binding<T> {
        Binding(get: { store.state.settings[keyPath: kp] }, set: { v in store.settings { $0[keyPath: kp] = v } })
    }
    func dateBind(_ kp: WritableKeyPath<BudgetSettings, String>) -> Binding<Date> {
        Binding(get: { DU.parseISO(store.state.settings[keyPath: kp]) ?? Date() },
                set: { v in store.settings { $0[keyPath: kp] = DU.iso(v) } })
    }
    func monthBind(_ kp: WritableKeyPath<BudgetSettings, String>) -> Binding<Date> {
        Binding(get: { DU.firstOfMonth(store.state.settings[keyPath: kp].isEmpty ? DU.ym(Date()) : store.state.settings[keyPath: kp]) },
                set: { v in store.settings { $0[keyPath: kp] = DU.ym(v) } })
    }
    func moneyBind(_ kp: WritableKeyPath<BudgetSettings, Double>) -> Binding<String> {
        Binding(get: { String(format: "%.2f", store.state.settings[keyPath: kp]) },
                set: { v in if let d = Double(v) { store.settings { $0[keyPath: kp] = d } } })
    }

    var body: some View {
        let s = store.state.settings
        Form {
            Section {
                Picker("How you’re paid", selection: bind(\.mode)) {
                    Text("Semi-monthly").tag("semi"); Text("Biweekly").tag("biweekly"); Text("Biweekly, then semi-monthly").tag("switch")
                }
                DatePicker("Budget starts", selection: monthBind(\.startMonth), displayedComponents: .date)
            } footer: { Text("Budget starts uses the month of the date you pick.") }

            if s.mode != "semi" {
                Section("Biweekly") {
                    DatePicker("Any recent payday", selection: dateBind(\.bwAnchor), displayedComponents: .date)
                    HStack { Text("Take-home per check"); Spacer(); TextField("0.00", text: moneyBind(\.bwPay)).decimalPad().multilineTextAlignment(.trailing) }
                    if s.mode == "switch" {
                        DatePicker("Last biweekly payday", selection: dateBind(\.bwEnd), displayedComponents: .date)
                        DatePicker("Semi-monthly starts", selection: monthBind(\.switchMonth), displayedComponents: .date)
                    }
                }
            }
            if s.mode != "biweekly" {
                Section("Semi-monthly") {
                    Picker("First payday", selection: bind(\.payDay1)) { ForEach(1...28, id: \.self) { Text(DU.ordinal($0)).tag($0) } }
                    Picker("Second payday", selection: bind(\.payDay2)) {
                        ForEach(1...28, id: \.self) { Text(DU.ordinal($0)).tag(String($0)) }
                        Text("Last day").tag("last")
                    }
                    Picker("Weekend paydays", selection: bind(\.weekend)) {
                        Text("Friday before").tag("friday"); Text("Monday after").tag("monday"); Text("That day").tag("none")
                    }
                    HStack { Text("Take-home per check"); Spacer(); TextField("0.00", text: moneyBind(\.pay)).decimalPad().multilineTextAlignment(.trailing) }
                }
            }
            Section {
                Picker("Each paycheck pays for", selection: bind(\.payAhead)) {
                    Text("Bills due before next payday").tag(0)
                    Text("One pay period ahead").tag(1)
                    Text("Two pay periods ahead").tag(2)
                }
                Toggle("Carry leftovers to the next check", isOn: bind(\.rollover))
            } header: { Text("Paying ahead") } footer: {
                Text("Bills set to “Every check” or pinned to a check don’t shift.")
            }
        }
        .navigationTitle("Paydays")
        .inlineTitle()
    }
}
