import SwiftUI

/// Setup → Investment prices: turn daily price updates on, paste a Tiingo key, update now.
/// The key stays in this device's keychain (PriceService.Key), never in the budget file.
struct PriceSection: View {
    @EnvironmentObject var store: Store
    @AppStorage(PriceService.enabledKey) private var on = false
    @AppStorage(PriceService.statusKey) private var status = ""
    @State private var key = ""
    @State private var hasKey = false
    @State private var updating = false

    var body: some View {
        Section {
            Toggle("Update prices daily", isOn: $on)
                .disabled(!hasKey && !on)
            if hasKey {
                LabeledContent("Tiingo key", value: "Saved on this device")
                Button("Remove key", role: .destructive) {
                    PriceService.Key.set(""); hasKey = false; on = false; status = ""
                }
            } else {
                SecureField("Paste your Tiingo key", text: $key)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .onSubmit(saveKey)
                Button("Save key", action: saveKey)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                Link("Get a free key at tiingo.com", destination: URL(string: "https://www.tiingo.com/account/api/token")!)
            }
            if hasKey {
                Button {
                    updating = true
                    Task { await store.updatePrices(force: true); updating = false }
                } label: {
                    HStack {
                        Text("Update now")
                        if updating { Spacer(); ProgressView() }
                    }
                }
                .disabled(updating)
            }
            if !status.isEmpty {
                Text(status).font(.ui(.caption)).foregroundStyle(.secondary)
            }
        } header: { Text("Investment prices") } footer: {
            Text("Sets each holding to today's shares × the latest closing price, a few times a day while the app is open. Only fund and stock symbols are sent to Tiingo. Share counts still come from your last import, so import again after you buy or sell. The key is kept on this device only; add it on each device you want updating.")
        }
        .onAppear { hasKey = PriceService.Key.get() != nil }
    }

    private func saveKey() {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        if PriceService.Key.set(k) {
            hasKey = true; key = ""; on = true
            status = ""
            UserDefaults.standard.removeObject(forKey: PriceService.lastTryKey)
            updating = true
            Task { await store.updatePrices(force: true); updating = false }
        } else {
            status = "Couldn't save the key to the keychain."
        }
    }
}
