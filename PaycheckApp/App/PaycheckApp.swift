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

enum AppTab: Hashable { case home, paychecks, purchases, month, debt }

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            HomeView(tab: $tab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            PaychecksView()
                .tabItem { Label("Paychecks", systemImage: "banknote") }
                .tag(AppTab.paychecks)
            PurchasesView()
                .tabItem { Label("Purchases", systemImage: "cart") }
                .tag(AppTab.purchases)
            MonthView()
                .tabItem { Label("Month", systemImage: "chart.pie") }
                .tag(AppTab.month)
            DebtView()
                .tabItem { Label("Debt", systemImage: "creditcard") }
                .tag(AppTab.debt)
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
