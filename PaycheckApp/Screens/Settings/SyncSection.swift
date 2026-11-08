import SwiftUI
import UniformTypeIdentifiers

/// Setup section for keeping devices in sync through a shared folder.
struct SyncSection: View {
    @EnvironmentObject var store: Store
    @ObservedObject var sync: SyncFolder
    /// Opens the folder picker. Setup owns the one file picker on its screen, because
    /// SwiftUI won't reliably show a second one from inside a form.
    let choose: () -> Void
    /// A budget already in the picked folder, waiting for you to choose which copy to keep.
    @Binding var found: BudgetState?

    var body: some View {
        Section {
            if sync.isOn {
                // Connected: the folder, its status, and ways to change or stop.
                LabeledContent("Syncing with", value: sync.folderName ?? "Folder")
                if let p = sync.problem {
                    Label(p, systemImage: "exclamationmark.triangle.fill").font(.ui(.footnote)).foregroundStyle(Theme.bad)
                } else if let d = sync.lastSynced {
                    Text("Last checked \(Text(d, style: .relative)) ago").font(.ui(.footnote)).foregroundStyle(.secondary)
                }
                Button { Task { await store.syncNow() } } label: { Label("Sync now", systemImage: "arrow.triangle.2.circlepath") }
                Button { choose() } label: { Label("Change folder", systemImage: "folder") }
                Button(role: .destructive) { sync.disconnect() } label: { Label("Stop syncing", systemImage: "xmark.circle") }
            } else {
                // Not connected yet.
                Button { choose() } label: { Label("Choose a sync folder", systemImage: "arrow.triangle.2.circlepath") }
            }
        } header: { Text("Sync between devices") } footer: {
            Text(sync.isOn
                 ? "Changes are shared through this folder. Pick the same folder on your other devices. If both change before they sync, the most recent save wins."
                 : "Keep your iPhone and Mac in step. Make a folder in iCloud Drive (like “Paycheck Plan”) and choose it here and on your other devices.")
        }
        // The picked folder already has a budget (from another device): keep that one,
        // overwrite it with this device's, or cancel and stay unconnected.
        .confirmationDialog("There’s already a budget in this folder", isPresented: Binding(get: { found != nil }, set: { if !$0 { found = nil } }),
                            titleVisibility: .visible) {
            if let f = found {
                Button("Use the folder’s budget") { store.useSynced(f); found = nil }
                Button("Replace it with this device’s budget") { Task { await store.pushThisDevice() }; found = nil }
                Button("Cancel", role: .cancel) { sync.disconnect(); found = nil }
            }
        } message: {
            if let f = found {
                Text("The folder’s copy was last changed \(f.savedDate.formatted(date: .abbreviated, time: .shortened)). This device’s was last changed \(store.state.savedDate.formatted(date: .abbreviated, time: .shortened)).")
            }
        }
    }
}
