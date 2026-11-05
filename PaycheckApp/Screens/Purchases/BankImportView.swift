import SwiftUI
import UniformTypeIdentifiers

/// Pick a CSV from your bank, check where each transaction goes, then import.
struct BankImportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable {
        let tx: BankTx
        var target: ImportTarget
        let suggested: ImportTarget
        let fromRule: Bool
        var remember: Bool
        var id: String { tx.id }
    }

    @State private var choosing = false
    @State private var fileText: String?
    @State private var fileName = ""
    @State private var flip = false
    @State private var rows: [Row] = []
    @State private var skippedDupes = 0
    @State private var error: String?
    @State private var result: (added: Int, problems: [String])?

    var spending: [Recurring] { store.state.recurring.filter { $0.type == "expense" } }
    var bills: [Recurring] { store.state.recurring.filter { $0.type != "expense" && !$0.extraLine } }
    var picked: Int { rows.filter { $0.target != .skip }.count }

    var body: some View {
        NavigationStack {
            Group {
                if rows.isEmpty { intro } else { review }
            }
            .navigationTitle("Import from bank")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !rows.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import \(picked)") { runImport() }.disabled(picked == 0)
                    }
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { res in
                guard case .success(let url) = res else { return }
                load(url)
            }
            .alert("Import finished", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil; dismiss() } })) {
                Button("Done") { result = nil; dismiss() }
            } message: {
                if let r = result {
                    Text("Added \(r.added) \(r.added == 1 ? "transaction" : "transactions")." +
                         (r.problems.isEmpty ? "" : "\n\nNot added:\n" + r.problems.joined(separator: "\n")))
                }
            }
        }
    }

    // MARK: Step 1

    var intro: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Image(systemName: "building.columns").font(.ui(.largeTitle)).foregroundStyle(Theme.accent)
                    Text("Bring in your bank transactions").font(.ui(.title3).bold())
                    Text("Download your transactions from your bank’s website as a CSV file and save it to Files. Then choose it here. You’ll check where each one goes before anything is added.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button { choosing = true } label: {
                        Label("Choose CSV file", systemImage: "doc.badge.plus").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity).card()

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.ui(.subheadline)).foregroundStyle(Theme.bad)
                        .frame(maxWidth: .infinity, alignment: .leading).card()
                }

                VStack(alignment: .leading, spacing: 8) {
                    CardHeader("How it works")
                    Text("• Spending goes into a category, like Groceries or Gas.\n• Bill payments mark that bill paid on the right paycheck.\n• Deposits and anything you don’t pick are skipped.\n• It remembers your choices for each store, and won’t add the same transaction twice.")
                        .font(.ui(.subheadline)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).card()
            }
            .padding()
            .readableWidth()
        }
        .background(Theme.bg)
    }

    // MARK: Step 2

    var review: some View {
        let out = rows.indices.filter { rows[$0].tx.isOutflow }
        let inn = rows.indices.filter { !rows[$0].tx.isOutflow }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileName).font(.ui(.subheadline).weight(.semibold)).lineLimit(1)
                    Text("\(rows.count) new \(rows.count == 1 ? "transaction" : "transactions")" +
                         (skippedDupes > 0 ? ", \(skippedDupes) already imported" : ""))
                        .font(.ui(.caption)).foregroundStyle(.secondary)
                }
                Toggle("Spending shows as positive", isOn: $flip)
                    .font(.ui(.subheadline))
                    .onChange(of: flip) { _, _ in reparse() }
            } footer: {
                Text("Turn this on if your spending landed under Money in.")
            }

            if !out.isEmpty {
                Section("Money out") { ForEach(out, id: \.self) { i in row($rows[i]) } }
            }
            if !inn.isEmpty {
                Section("Money in") { ForEach(inn, id: \.self) { i in row($rows[i]) } }
            }
        }
    }

    func row(_ r: Binding<Row>) -> some View {
        let t = r.wrappedValue.tx
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(t.desc.isEmpty ? "Transaction" : t.desc).font(.ui(.subheadline)).lineLimit(2)
                Spacer()
                Text(money(abs(t.amount))).monospacedDigit().font(.ui(.subheadline).weight(.semibold))
                    .foregroundStyle(t.isOutflow ? .primary : Theme.good)
            }
            HStack(spacing: 8) {
                Text(t.pocket.isEmpty ? DU.short(t.date) : "\(DU.short(t.date)) · \(t.pocket)")
                    .font(.ui(.caption)).foregroundStyle(.secondary).lineLimit(1)
                if r.wrappedValue.fromRule && r.wrappedValue.target == r.wrappedValue.suggested {
                    Tag(text: "Your rule")
                }
                Spacer()
                Picker("Put in", selection: Binding(
                    get: { r.wrappedValue.target },
                    set: { v in
                        r.wrappedValue.target = v
                        // Changing a suggestion means it's worth remembering next time.
                        r.wrappedValue.remember = v != r.wrappedValue.suggested || r.wrappedValue.fromRule
                    })) {
                    Text("Skip").tag(ImportTarget.skip)
                    if !spending.isEmpty {
                        Section("Spending") {
                            ForEach(spending) { s in Text(s.name).tag(ImportTarget.spend(s.id)) }
                        }
                    }
                    if !bills.isEmpty {
                        Section("Mark paid") {
                            ForEach(bills) { b in Text(b.name).tag(ImportTarget.bill(b.id)) }
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.ui(.caption))
            }
            if r.wrappedValue.target != r.wrappedValue.suggested || r.wrappedValue.fromRule {
                Toggle("Always do this for \(merchantLabel(t.desc))", isOn: r.remember)
                    .font(.ui(.caption)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    func merchantLabel(_ desc: String) -> String {
        let k = BankCSV.merchantKey(desc)
        return k.isEmpty ? "this store" : k.capitalized
    }

    // MARK: Actions

    func load(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { error = "Couldn’t open that file."; return }
        fileText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        fileName = url.lastPathComponent
        flip = false
        reparse()
    }

    func reparse() {
        guard let text = fileText else { return }
        do {
            let all = try BankCSV.parse(text, flipSigns: flip)
            let fresh = all.filter { !store.alreadyImported($0) }
            skippedDupes = all.count - fresh.count
            rows = fresh.map { t in
                let s = store.suggestTarget(t)
                return Row(tx: t, target: s.target, suggested: s.target, fromRule: s.fromRule, remember: s.fromRule)
            }
            error = rows.isEmpty ? "Everything in this file was already imported." : nil
        } catch let e {
            rows = []
            error = e.localizedDescription
        }
    }

    func runImport() {
        // Skipped rows are only saved when they set a rule, so unpicked rows can be imported later.
        let picks = rows.filter { $0.target != .skip || $0.remember }.map { (tx: $0.tx, target: $0.target, remember: $0.remember) }
        result = store.applyImport(picks)
    }
}
