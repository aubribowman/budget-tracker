import SwiftUI

/// The app's entry point. Creates the one `Store` and hands it to every screen.
@main
struct PaycheckPlanApp: App {
    @StateObject private var store = Store()
    @AppStorage("appearance") private var appearance = "auto"   // auto | light | dark, set in Setup

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.accent)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
                .macFormStyle()
        }
        #if os(macOS)
        // Open at a phone-like size; the cards are designed for a narrow column.
        .defaultSize(width: 760, height: 900)
        .commands { ZoomCommands() }
        #endif
    }
}

/// The tabs, so screens can switch tabs (Home links to the others).
enum AppTab: Hashable { case home, paychecks, purchases, month, debt }

/// The tab bar, plus the things that apply to the whole app: the Face ID lock, the
/// sync timer, refreshing when the app comes back, and the error alert.
struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    @State private var tab: AppTab = .home
    @AppStorage(AppLock.enabledKey) private var lockOn = false
    @State private var locked = UserDefaults.standard.bool(forKey: AppLock.enabledKey)
    @State private var unlocking = false

    var body: some View {
        tabs
            .macZoom()
            .overlay {
                // Cover the app while locked, and in the app switcher so balances stay private.
                if lockOn && (locked || phase != .active) {
                    LockScreen { unlock() }.transition(.opacity)
                }
            }
            .task { if locked { unlock() } }
            .onChange(of: phase) { _, p in
                if p == .background && lockOn { locked = true }
                if p == .active && locked { unlock() }
            }
    }

    private func unlock() {
        guard lockOn else { locked = false; return }
        guard !unlocking else { return }
        unlocking = true
        Task {
            let ok = await AppLock.authenticate()
            withAnimation { if ok { locked = false } }
            unlocking = false
        }
    }

    private var tabs: some View {
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
                .tabItem { Label("Payoff", systemImage: "flag.checkered") }
                .tag(AppTab.debt)
        }
        .onChange(of: phase) { _, p in
            // Refresh "today"-based numbers (autopay, safe to spend) when the app comes back.
            if p == .active { store.refresh() }
        }
        .task(id: phase) {
            // While the app is open, check the sync folder now and every 30 seconds.
            guard phase == .active else { return }
            while !Task.isCancelled {
                await store.syncNow()
                try? await Task.sleep(for: .seconds(30))
            }
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
