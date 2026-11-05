import SwiftUI

/// Student loans section of the Payoff tab.
struct StudentLoansSection: View {
    @EnvironmentObject var store: Store
    @State private var editing: Loan?
    @State private var payText = ""
    @State private var planStart = Date()

    var body: some View {
        let e = store.engine
        let sim = e.simulateLoans()
        let loans = store.state.loans
        let total = sim.items.values.reduce(0) { $0 + $1.balanceNow }
        // Payoff dates come from the same plan as the Payoff tab, so both tabs agree.
        let roll = store.state.settings.rollLoans
        let all = e.simulateAll(extra: store.state.extra, strategy: store.state.strategy, roll: roll)
        let now = DU.ym(Date())
        let cardsLeft = store.state.debts.contains { e.curBal($0) > 0.005 }
        VStack(spacing: 16) {
            if loans.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "graduationcap").font(.ui(.largeTitle)).foregroundStyle(Theme.accent)
                    Text("Add your student loans").font(.ui(.title3).bold())
                    Text("See what you'll owe when repayment starts, your monthly payment, and when you'll be done.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).card()
            } else {
                // Headline
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(money(total)) across \(loans.count) \(loans.count == 1 ? "loan" : "loans")").font(.ui(.caption)).foregroundStyle(.secondary)
                    Text(all.stuck ? "Payment doesn’t cover interest" : all.loanMonths > 0 ? "Paid off by \(DU.monthLabel(all.loansDone(now)))" : "Paid off")
                        .font(.display(.title, weight: .heavy)).minimumScaleFactor(0.6)
                    if !all.stuck {
                        Text("About \(money0(all.loanInterest)) in interest from today.").font(.ui(.subheadline)).foregroundStyle(.secondary)
                        if cardsLeft {
                            Text(roll ? "Includes your card and personal loan payments rolling into student loans after they're paid off in \(DU.monthLabel(all.debtsDone(now))). You can change this in the Debts section."
                                      : "Card and personal loan payments don't roll into student loans. Turn that on in the Debts section to finish sooner.")
                                .font(.ui(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()

                planCard(sim)

                ForEach(loans) { l in
                    Button { editing = l } label: { LoanCard(loan: l, item: sim.items[l.id], payoff: all.loanPayoff[l.id].map { DU.addMonths(now, $0) }) }.buttonStyle(.plain)
                }
            }
            Button { editing = Loan() } label: { Label("Add a student loan", systemImage: "plus") }
        }
        .sheet(item: $editing) { l in LoanEditSheet(loan: l).macSheet() }
        .onAppear {
            payText = store.state.loanPlan.payment > 0 ? String(format: "%.2f", store.state.loanPlan.payment) : ""
            planStart = DU.firstOfMonth(store.state.loanPlan.start.count >= 7 ? String(store.state.loanPlan.start.prefix(7))
                                         : (loans.map { e.repayMonth($0) }.min() ?? DU.ym(Date())))
        }
    }

    func planCard(_ sim: LoanSim) -> some View {
        let onPaychecks = store.engine.loanPlanRec != nil
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader("Your payment plan")
            HStack {
                Text("Monthly payment")
                Spacer()
                TextField(String(format: "%.2f", sim.standardTotal), text: $payText, onCommit: commitPlan)
                    .decimalPad().multilineTextAlignment(.trailing).frame(maxWidth: 110)
                    .textFieldStyle(.roundedBorder)
            }
            Text(store.state.loanPlan.payment > 0
                 ? "Standard plan would be \(money(sim.standardTotal))/month. Anything over each loan’s payment goes to the highest rate first."
                 : "Leave blank to use the standard plan, \(money(sim.standardTotal))/month.")
                .font(.ui(.caption)).foregroundStyle(.secondary)
            DatePicker("Start paying", selection: $planStart, displayedComponents: .date)
                .onChange(of: planStart) { _, _ in commitPlan() }
            Button(onPaychecks ? "Remove from paychecks" : "Add to paychecks") { commitPlan(); store.setLoanPlanLine(on: !onPaychecks) }
                .buttonStyle(.borderedProminent)
                .tint(onPaychecks ? .gray : Theme.accent)
            Text(onPaychecks ? "Shows up as “Student loans” on your first paycheck each month starting \(DU.monthLabel(store.engine.loanPlanRec?.start ?? DU.ym(planStart))). Marking it paid lowers your balances."
                             : "Puts \(money(sim.monthly)) on your first paycheck each month so you can tick it off.")
                .font(.ui(.caption)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
        .keyboardDoneButton { commitPlan() }
    }

    func commitPlan() {
        store.setLoanPlan(payment: Double(payText) ?? 0, start: DU.ym(planStart))
    }
}

/// One student loan: balance now and at repayment, standard payment, payoff month.
struct LoanCard: View {
    @EnvironmentObject var store: Store
    let loan: Loan
    let item: LoanSim.Item?
    let payoff: String?

    var body: some View {
        let e = store.engine
        let repay = e.repayMonth(loan)
        let inRepay = repay <= DU.ym(Date())
        let bal = item?.balanceNow ?? loan.balance
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(loan.name).font(.ui(.headline))
                Spacer()
                Tag(text: inRepay ? "In repayment" : "Starts \(DU.monthLabel(repay, short: true))", color: inRepay ? Theme.accent : Theme.midnight)
            }
            Text(money(bal)).font(.display(.title2, weight: .bold)).monospacedDigit().rollingNumber(bal)
            HStack {
                Text("\(Engine.loanKindLabel(loan.kind)), \(String(format: "%.2f", loan.apr))%")
                Spacer()
                if let p = payoff { Text("Paid off \(DU.monthLabel(p, short: true))") }
            }
            .font(.ui(.caption)).foregroundStyle(.secondary)
            if let it = item, !inRepay, it.atRepay > bal + 0.5 {
                Text("About \(money(it.atRepay)) when repayment starts. \(money(it.atRepay - bal)) of interest builds up before then.")
                    .font(.ui(.caption)).foregroundStyle(Theme.over)
            }
            if let it = item {
                Text("Standard payment: \(money(it.standard))/month over \(loan.term) years").font(.ui(.caption)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

/// Add or edit a student loan.
struct LoanEditSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var loan: Loan
    @State private var balance = ""
    @State private var apr = ""
    @State private var payment = ""
    @State private var repay = Date()
    @State private var confirmDelete = false

    var isNew: Bool { !store.state.loans.contains { $0.id == loan.id } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (like Direct Unsub 2024)", text: $loan.name)
                Picker("Type", selection: $loan.kind) {
                    ForEach(Engine.loanKinds, id: \.id) { Text($0.label).tag($0.id) }
                }
                Section {
                    field("Balance today", $balance)
                    field("Interest rate %", $apr)
                    DatePicker("Repayment starts", selection: $repay, displayedComponents: .date)
                    Picker("Repay over", selection: $loan.term) {
                        ForEach([5, 10, 15, 20, 25], id: \.self) { Text("\($0) years").tag($0) }
                    }
                    field("Your payment (optional)", $payment)
                } footer: {
                    Text(loan.kind == "subsidized"
                         ? "Subsidized loans don’t build interest before repayment starts."
                         : "Interest builds up before repayment starts and is added to the balance when it does. Leave the payment blank to use the standard amount.")
                }
                if !isNew {
                    Button("Delete this loan", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(isNew ? "New loan" : loan.name)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }.disabled(loan.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(loan.name)?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { store.deleteLoan(loan.id); dismiss() }
            }
            .onAppear {
                if isNew { loan.name = "" }
                balance = loan.balance > 0 ? String(format: "%.2f", loan.balance) : ""
                apr = loan.apr > 0 ? String(format: "%.2f", loan.apr) : ""
                payment = loan.payment > 0 ? String(format: "%.2f", loan.payment) : ""
                repay = DU.firstOfMonth(store.engine.repayMonth(loan))
            }
        }
    }

    func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack { Text(label); Spacer(); TextField("0.00", text: text).decimalPad().multilineTextAlignment(.trailing).frame(maxWidth: 120) }
    }

    func save() {
        var l = loan
        let nb = r2(Double(balance) ?? l.balance)
        // A new balance resets tracking to today, like debts.
        if isNew || abs(nb - l.balance) > 0.004 { l.balance = nb; l.asOf = DU.iso(DU.today) }
        l.apr = Double(apr) ?? l.apr
        l.payment = r2(Double(payment) ?? 0)
        l.repayStart = DU.ym(repay)
        store.saveLoan(l)
    }
}
