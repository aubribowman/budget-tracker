import SwiftUI

/// How and when you're paid: semi-monthly or biweekly, paydays, weekend rule, pay-ahead.
struct ScheduleView: View {
    @EnvironmentObject var store: Store

    // Bindings straight to a setting, so every change saves right away. The date and
    // money versions convert from the stored text ("yyyy-MM-dd") or number.
    func bind<T>(_ kp: WritableKeyPath<BudgetSettings, T>) -> Binding<T> {
        Binding(get: { store.state.settings[keyPath: kp] }, set: { v in store.settings { $0[keyPath: kp] = v } })
    }
    func dateBind(_ kp: WritableKeyPath<BudgetSettings, String>) -> Binding<Date> {
        Binding(get: { DU.parseISO(store.state.settings[keyPath: kp]) ?? Date() },
                set: { v in store.settings { $0[keyPath: kp] = DU.iso(v) } })
    }
    func moneyBind(_ kp: WritableKeyPath<BudgetSettings, Double>) -> Binding<String> {
        Binding(get: { String(format: "%.2f", store.state.settings[keyPath: kp]) },
                set: { v in if let d = Double(v) { store.settings { $0[keyPath: kp] = d } } })
    }

    var body: some View {
        let s = store.state.settings
        Form {
            // The pay mode decides which sections show below: "semi" (two set days a month),
            // "biweekly" (every 14 days from a known payday), or "switch" (biweekly until a
            // date, then semi-monthly, for a job change).
            Section {
                Picker("How you’re paid", selection: bind(\.mode)) {
                    Text("Semi-monthly").tag("semi"); Text("Biweekly").tag("biweekly"); Text("Biweekly, then semi-monthly").tag("switch")
                }
                MonthMenu(title: "Budget starts", selection: bind(\.startMonth))
            }

            if s.mode != "semi" {
                Section("Biweekly") {
                    // Any one real payday is enough; every other one is a multiple of 14 days away.
                    DatePicker("Any recent payday", selection: dateBind(\.bwAnchor), displayedComponents: .date)
                    HStack { Text("Take-home per check"); Spacer(); TextField("0.00", text: moneyBind(\.bwPay)).decimalPad().multilineTextAlignment(.trailing) }
                    if s.mode == "switch" {
                        DatePicker("Last biweekly payday", selection: dateBind(\.bwEnd), displayedComponents: .date)
                        MonthMenu(title: "Semi-monthly starts", selection: bind(\.switchMonth), allowNone: true)
                    }
                }
            }
            if s.mode != "biweekly" {
                Section("Semi-monthly") {
                    // Days stop at 28 so every month has them; "Last day" covers month-end paydays.
                    Picker("First payday", selection: bind(\.payDay1)) { ForEach(1...28, id: \.self) { Text(DU.ordinal($0)).tag($0) } }
                    Picker("Second payday", selection: bind(\.payDay2)) {
                        ForEach(1...28, id: \.self) { Text(DU.ordinal($0)).tag(String($0)) }
                        Text("Last day").tag("last")
                    }
                    // When a payday falls on a weekend, most employers pay the Friday before.
                    Picker("Weekend paydays", selection: bind(\.weekend)) {
                        Text("Friday before").tag("friday"); Text("Monday after").tag("monday"); Text("That day").tag("none")
                    }
                    HStack { Text("Take-home per check"); Spacer(); TextField("0.00", text: moneyBind(\.pay)).decimalPad().multilineTextAlignment(.trailing) }
                }
            }
            // Paying ahead: each paycheck covers bills further out, to build a cushion.
            // "Carry leftovers" adds what's left on one paycheck to the next.
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

/// Picks a month ("yyyy-MM") from a menu. These settings only keep the month, so a full
/// date picker would snap back to the 1st whenever you changed the day, which looked
/// like it hadn't saved.
private struct MonthMenu: View {
    let title: String
    @Binding var selection: String
    /// Adds "Not set" for an empty value (the switch month starts out empty).
    var allowNone = false

    /// A year back to two years ahead of today, plus the saved month if it's outside that.
    private var months: [String] {
        let now = DU.ym(Date())
        var list = (-12...24).map { DU.addMonths(now, $0) }
        if !selection.isEmpty && !list.contains(selection) { list.append(selection); list.sort() }
        return list
    }

    var body: some View {
        Picker(title, selection: $selection) {
            if allowNone || selection.isEmpty { Text("Not set").tag("") }
            ForEach(months, id: \.self) { Text(DU.monthLabel($0)).tag($0) }
        }
    }
}
