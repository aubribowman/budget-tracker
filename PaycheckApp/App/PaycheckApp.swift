import SwiftUI

/// The app's entry point. Creates the one `Store` and hands it to every screen.
@main
struct PaycheckPlanApp: App {
    @StateObject private var store = Store()
    @AppStorage("appearance") private var appearance = "auto"   // auto | light | dark, set in Setup

    init() {
        AppFonts.register()
        #if os(iOS)
        AppFonts.styleNavigationBars()
        #endif
    }


    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.accent)
                .font(.ui(.body))   // DM Sans for any text that doesn't pick a font
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
                .tabItem { tabLabel("Home", "house") }
                .tag(AppTab.home)
            PaychecksView()
                .tabItem { tabLabel("Paychecks", "dollarsign.circle") }
                // A red count of bills to pay now or past due, like an unread count.
                .badge(billsToPay)
                .tag(AppTab.paychecks)
            PurchasesView()
                .tabItem { tabLabel("Purchases", "cart") }
                .tag(AppTab.purchases)
            MonthView()
                .tabItem { tabLabel("Month", "chart.pie") }
                .tag(AppTab.month)
            PayoffView()
                .tabItem { tabLabel("Payoff", "flag.checkered") }
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

    /// Bills to pay from the current paycheck, plus any past due, for the Paychecks badge.
    private var billsToPay: Int {
        let u = store.engine.upcoming()
        return u.toPay.count + u.overdue.count
    }

    /// A tab's icon and name. The icons stay thin outlines (iPhone fills them in by
    /// default), so the tab bar looks light and the badge stands out.
    private func tabLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).environment(\.symbolVariants, .none)
    }
}
