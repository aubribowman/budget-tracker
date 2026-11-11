import SwiftUI
import Charts
import UniformTypeIdentifiers

/// The Investments screen, opened from the Net worth card on Home.
struct InvestmentsView: View {
    var body: some View {
        ScrollView {
            InvestmentsSection()
                .padding()
                .readableWidth()
        }
        .background(Theme.bg)
        .navigationTitle("Investments")
    }
}

/// Investments: the total with a chart of how it's changed, each account with its
/// holdings, and buttons to import from Fidelity or add by hand.
/// The data is in Model/Investments.swift and the math in Engine+Invest.swift.
struct InvestmentsSection: View {
    @EnvironmentObject var store: Store
    @State private var editing: InvestAccount?
    @State private var importing = false

    var body: some View {
        let accounts = store.state.accounts
        VStack(alignment: .leading, spacing: 16) {
            if accounts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.ui(.largeTitle)).foregroundStyle(Theme.accent)
                    Text("Track your investments").font(.ui(.title3).bold())
                    Text("Import your positions from Fidelity, or add an account by hand. Link a savings item on your paychecks to an account, and marking it paid adds to it.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).card()
            } else {
                InvestTotalCard()
                ForEach(accounts) { a in
                    AccountCard(account: a)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = a }
                        .accessibilityAction(named: "Edit account") { editing = a }
                }
            }
            // Side by side when they fit, stacked on a narrow screen or with large text.
            ViewThatFits {
                HStack(spacing: 20) { importButton; addButton }
                VStack(spacing: 12) { importButton; addButton }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            if !accounts.isEmpty {
                Text(UserDefaults.standard.bool(forKey: PriceService.enabledKey)
                     ? "Share counts are from your last import or edit, priced at the latest close, plus paycheck contributions since. Import again after you buy or sell."
                     : "Values are from your last import or edit, plus paycheck contributions since. Turn on daily prices in Setup → Investment prices, or import again to get today's prices.")
                    .font(.ui(.caption)).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { a in AccountEditSheet(account: a).macSheet() }
        .sheet(isPresented: $importing) { FidelityImportSheet().macSheet() }
    }

    private var importButton: some View {
        Button { importing = true } label: {
            Label("Import from Fidelity", systemImage: "square.and.arrow.down").font(.ui(.headline))
        }
    }

    private var addButton: some View {
        Button { editing = InvestAccount() } label: {
            Label("Add by hand", systemImage: "plus").font(.ui(.headline))
        }
    }
}

/// Shares without extra zeros: "5", "18.2", "10.125".
func sharesText(_ v: Double) -> String {
    v.formatted(.number.precision(.fractionLength(0...4)))
}

/// All accounts together, with gain or loss and the value over time.
private struct InvestTotalCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let e = store.engine
        let accounts = store.state.accounts
        let total = e.investTotal()
        let cost = accounts.reduce(0) { $0 + $1.knownCost }
        let withCost = accounts.reduce(0) { $0 + $1.valueWithCost }
        let points = store.state.investHistory.filter { $0.invest > 0 }
        VStack(alignment: .leading, spacing: 8) {
            Text("Invested across \(accounts.count) \(accounts.count == 1 ? "account" : "accounts")")
                .font(.ui(.caption)).foregroundStyle(.secondary)
            Text(money(total)).font(.display(size: 34, weight: .heavy)).monospacedDigit()
            if cost > 0.005 {
                GainText(gain: withCost - cost, cost: cost, label: "total gain")
            }
            if points.count >= 2 {
                InvestChart(points: points).frame(height: 150).padding(.top, 6)
            } else {
                Text("Import again later and a chart of your total shows up here.")
                    .font(.ui(.caption)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.leadCard)
    }
}

/// "+$1,234.00 (12.3%) total gain", green for up and red for down.
struct GainText: View {
    let gain: Double
    let cost: Double
    var label: String = "gain"

    var body: some View {
        let pct = cost > 0 ? gain / cost * 100 : 0
        let up = gain >= 0
        Text("\(up ? "+" : "−")\(money(abs(gain))) (\(String(format: "%.1f", abs(pct)))%) \(up ? label : label.replacingOccurrences(of: "gain", with: "loss"))")
            .font(.ui(.subheadline).weight(.semibold)).monospacedDigit()
            .foregroundStyle(up ? Theme.good : Theme.over)
    }
}

/// Total invested by day, from each import or edit.
struct InvestChart: View {
    let points: [ValuePoint]

    var body: some View {
        Chart(points) { p in
            if let d = DU.parseISO(p.date) {
                LineMark(x: .value("Day", d), y: .value("Value", p.invest))
                    .foregroundStyle(Theme.moss)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Day", d), y: .value("Value", p.invest))
                    .foregroundStyle(Theme.moss).symbolSize(20)
            }
        }
        // Start the scale near the values instead of at $0, so changes are easy to see.
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(money0(n)) } } } }
        .accessibilityLabel("Investments over time")
    }
}

/// One account: value, gain, holdings, and paycheck contributions.
struct AccountCard: View {
    @EnvironmentObject var store: Store
    let account: InvestAccount

    var body: some View {
        let e = store.engine
        let value = e.accountValue(account)
        let added = e.contributedSince(account)
        let planned = e.plannedInto(account)
        let linked = store.state.recurring.filter { $0.goalId == account.id }
        VStack(alignment: .leading, spacing: 10) {
            ValueRow(alignment: .firstTextBaseline) {
                Text(account.name).font(.ui(.headline))
            } value: {
                if !account.numberTail.isEmpty {
                    Text(account.numberTail).font(.ui(.caption)).foregroundStyle(.secondary)
                }
            }
            Text(money(value)).font(.display(.title2, weight: .bold)).monospacedDigit().rollingNumber(value)
            if account.knownCost > 0.005 {
                GainText(gain: account.valueWithCost - account.knownCost, cost: account.knownCost)
            }
            // Biggest holdings first.
            VStack(spacing: 6) {
                ForEach(account.holdings.sorted { $0.value > $1.value }) { h in
                    HoldingRow(holding: h, total: account.holdingsValue)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Shares as of \(DU.dayLabel(DU.parseISO(account.asOf) ?? DU.today))")
                if let p = account.holdings.compactMap(\.priceAt).max(), let d = DU.parseISO(p) {
                    Text("Prices from \(DU.dayLabel(d)) close")
                }
                if added > 0.005 { Text("Plus \(money(added)) added from paychecks since") }
                if !linked.isEmpty {
                    Text("From " + linked.map(\.name).joined(separator: ", ")
                         + (planned > 0.005 ? ", \(money(planned)) this month" : ""))
                }
            }
            .font(.ui(.caption)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// "FXAIX  Fidelity 500 Index  ·  12.5 shares    $2,375.00  48%"
private struct HoldingRow: View {
    let holding: Holding
    let total: Double

    var body: some View {
        let share = total > 0 ? holding.value / total * 100 : 0
        ValueRow(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(holding.symbol.isEmpty ? (holding.cash ? "Cash" : holding.name) : holding.symbol)
                    .font(.ui(.subheadline).weight(.semibold))
                Text(detail).font(.ui(.caption)).foregroundStyle(.secondary).lineLimit(1)
            }
        } value: {
            VStack(alignment: .trailing, spacing: 1) {
                Text(money(holding.value)).font(.ui(.subheadline)).monospacedDigit()
                Text("\(String(format: "%.0f", share))%").font(.ui(.caption)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    /// Fidelity writes names in capitals ("VANGUARD TOTAL STOCK MARKET ETF"). Title case
    /// reads easier, keeping a few abbreviations in capitals.
    static func nice(_ s: String) -> String {
        s.capitalized.split(separator: " ").map { w in
            ["Etf", "Us", "S&p", "Reit", "Adr", "Ii", "Iii"].contains(String(w)) ? w.uppercased() : String(w)
        }.joined(separator: " ")
    }

    var detail: String {
        if holding.cash { return holding.name.isEmpty ? "Cash" : Self.nice(holding.name) }
        let shares = sharesText(holding.shares)
        let name = holding.symbol.isEmpty ? "" : Self.nice(holding.name) + " · "
        return name + "\(shares) shares"
    }
}

// MARK: - Editing

/// Add or edit an account and its holdings by hand.
struct AccountEditSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var account: InvestAccount
    @State private var start: [Holding] = []     // holdings when the sheet opened, to tell if they changed
    @State private var holding: Holding?
    @State private var confirmDelete = false

    var isNew: Bool { !store.state.accounts.contains { $0.id == account.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (Roth IRA, 401(k)…)", text: $account.name)
                    TextField("Account number (optional)", text: $account.number)
                } footer: {
                    Text("The account number matches this account to the right one when you import from Fidelity.")
                }
                Section {
                    ForEach(account.holdings) { h in
                        Button { holding = h } label: {
                            ValueRow {
                                Text(h.symbol.isEmpty ? (h.cash ? "Cash" : h.name) : h.symbol)
                            } value: {
                                Text(money(h.value)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { account.holdings.remove(atOffsets: $0) }
                    Button { holding = Holding() } label: { Label("Add a holding", systemImage: "plus") }
                } header: {
                    Text("Holdings")
                } footer: {
                    Text("Total \(money(account.holdingsValue)). Changing holdings counts as a new snapshot, so paycheck contributions start counting again from now.")
                }
                if !isNew {
                    Section { Button("Delete account", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(isNew ? "New account" : account.name)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(account.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Delete \(account.name)?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { store.deleteAccount(account.id); dismiss() }
            }
            .sheet(item: $holding) { h in
                HoldingEditSheet(holding: h) { saved in
                    if let i = account.holdings.firstIndex(where: { $0.id == saved.id }) { account.holdings[i] = saved }
                    else { account.holdings.append(saved) }
                }
                .macSheet()
            }
            .onAppear {
                start = account.holdings
                if isNew { account.name = "" }
            }
        }
    }

    /// Saves the account. New holdings make a new snapshot (see the footer).
    func save() {
        var a = account
        a.name = a.name.trimmingCharacters(in: .whitespaces)
        a.number = a.number.trimmingCharacters(in: .whitespaces)
        if isNew || a.holdings != start { a.asOf = DU.iso(Date()); a.asOfAt = DU.stamp() }
        store.saveAccount(a)
        dismiss()
    }
}

/// Add or edit one holding.
struct HoldingEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var holding: Holding
    let onSave: (Holding) -> Void
    @State private var shares = ""
    @State private var price = ""
    @State private var value = ""
    @State private var cost = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Symbol (FXAIX, AAPL…)", text: $holding.symbol)
                    TextField("Name", text: $holding.name)
                    Toggle("Cash or money market", isOn: $holding.cash)
                }
                Section {
                    if !holding.cash {
                        field("Shares", $shares)
                        field("Price per share", $price)
                    }
                    field("Value", $value)
                    if !holding.cash { field("Cost (what you paid)", $cost) }
                } footer: {
                    Text(holding.cash ? "How much cash is in the account."
                         : "Leave Value empty to use shares × price. Cost is optional; it shows your gain or loss.")
                }
            }
            .navigationTitle(holding.symbol.isEmpty ? "Holding" : holding.symbol.uppercased())
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save() } }
            }
            .onAppear {
                shares = holding.shares > 0 ? sharesText(holding.shares) : ""
                price = holding.price > 0 ? String(format: "%.2f", holding.price) : ""
                value = holding.value != 0 ? String(format: "%.2f", holding.value) : ""
                cost = holding.cost.map { String(format: "%.2f", $0) } ?? ""
            }
        }
    }

    func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack { Text(label); Spacer(); TextField("0.00", text: text).decimalPad().multilineTextAlignment(.trailing).frame(maxWidth: 140) }
    }

    func save() {
        var h = holding
        h.symbol = h.symbol.trimmingCharacters(in: .whitespaces).uppercased()
        if h.cash {
            h.shares = 0; h.price = 0; h.cost = nil
            h.value = r2(BankCSV.parseMoney(value) ?? 0)
        } else {
            h.shares = BankCSV.parseMoney(shares) ?? 0
            h.price = BankCSV.parseMoney(price) ?? 0
            h.value = r2(BankCSV.parseMoney(value) ?? h.shares * h.price)
            h.cost = BankCSV.parseMoney(cost).map(r2)
        }
        onSave(h)
        dismiss()
    }
}

// MARK: - Importing

/// Pick a Fidelity positions file, check which accounts it updates, and import.
struct FidelityImportSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var found: [FidelityCSV.Account] = []
    @State private var targets: [String: String] = [:]   // account key → existing id, "" for new, "skip"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if found.isEmpty {
                    Section {
                        Button { choosing = true } label: { Label("Choose positions file", systemImage: "doc") }
                    } footer: {
                        Text("On fidelity.com, go to Accounts & Trade → Portfolio → Positions, then choose Download (the arrow at the top right of the list). Pick that CSV file here. Nothing is sent anywhere; the file is only read on this device.")
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(Theme.over) }
                    }
                } else {
                    ForEach(found) { a in
                        Section {
                            ValueRow {
                                Text(a.name.isEmpty ? a.number : a.name).font(.ui(.headline))
                            } value: {
                                Text(money(a.total)).monospacedDigit()
                            }
                            Text("\(a.holdings.count) \(a.holdings.count == 1 ? "holding" : "holdings")\(a.number.isEmpty ? "" : " · \(a.number)")")
                                .font(.ui(.caption)).foregroundStyle(.secondary)
                            Picker("Import into", selection: binding(a)) {
                                Text("New account").tag("")
                                ForEach(store.state.accounts) { Text($0.name).tag($0.id) }
                                Text("Skip").tag("skip")
                            }
                        }
                    }
                    Section {
                        Text("Updating an account replaces its holdings with the ones in this file.")
                            .font(.ui(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Import from Fidelity")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !found.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            store.importPositions(found, targets: targets.filter { $0.value != "skip" })
                            dismiss()
                        }
                        .disabled(targets.values.allSatisfy { $0 == "skip" })
                    }
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { res in
                if case .success(let url) = res { load(url) }
            }
        }
    }

    private func binding(_ a: FidelityCSV.Account) -> Binding<String> {
        Binding(get: { targets[a.key] ?? "" }, set: { targets[a.key] = $0 })
    }

    /// Reads the file and matches each account to one already here by its number.
    func load(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            error = "Couldn’t open that file."; return
        }
        do {
            found = try FidelityCSV.parse(text)
            error = nil
            targets = [:]
            for a in found {
                targets[a.key] = store.state.accounts.first { !$0.number.isEmpty && $0.number == a.number }?.id ?? ""
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
