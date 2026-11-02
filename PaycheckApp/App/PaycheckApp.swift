import SwiftUI

@main
struct PaycheckPlanApp: App {
    @StateObject private var store = Store()
    @AppStorage("appearance") private var appearance = "auto"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.accent)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView {
            PaychecksView()
                .tabItem { Label("Paychecks", systemImage: "banknote") }
            PurchasesView()
                .tabItem { Label("Purchases", systemImage: "cart") }
            MonthView()
                .tabItem { Label("Month", systemImage: "chart.pie") }
            DebtView()
                .tabItem { Label("Debt", systemImage: "creditcard") }
            SettingsView()
                .tabItem { Label("Setup", systemImage: "gearshape") }
        }
        .onChange(of: phase) { _, p in
            // Refresh "today"-based numbers (autopay, safe to spend) when the app comes back.
            if p == .active { store.update { _ in } }
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.lastError ?? "") }
    }
}

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
