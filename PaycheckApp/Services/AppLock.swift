import SwiftUI
import LocalAuthentication

/// Face ID (or Touch ID / passcode) lock for the whole app. RootView in PaycheckApp.swift
/// decides when to lock (going to the background) and when to ask (coming back).
enum AppLock {
    static let enabledKey = "lockWithFaceID"      // UserDefaults key; per device, not synced

    /// "Face ID", "Touch ID", "Optic ID", or "Passcode" if no biometrics are set up.
    static var methodName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// True when the device has Face ID, Touch ID or a passcode set up.
    static var available: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Asks for Face ID, falling back to the device passcode. True when unlocked.
    static func authenticate(reason: String = "Unlock your budget") async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        do { return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
    }
}

/// Covers the app until you unlock. Also shown in the app switcher so balances stay private.
struct LockScreen: View {
    let unlock: () -> Void
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: AppLock.methodName == "Touch ID" ? "touchid" : "faceid")
                    .font(.system(size: 56)).foregroundStyle(Theme.accent)
                Text("Paycheck Plan is locked").font(.title3.bold())
                Button(action: unlock) {
                    Text("Unlock with \(AppLock.methodName)").font(.headline).padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
