import Foundation
import Combine

/// Keeps a copy of the budget in a folder you pick, like "Paycheck Plan" in iCloud Drive.
/// Every device that picks the same folder reads and writes the same file, and iCloud
/// copies it between them. The file is the same format as a backup.
///
/// Changes go both ways by save time: whichever copy was saved most recently wins.
@MainActor
final class SyncFolder: ObservableObject {
    nonisolated static let fileName = "Paycheck Plan.json"
    private static let bookmarkKey = "syncFolderBookmark"
    private static let nameKey = "syncFolderName"

    @Published private(set) var folderName: String?
    @Published private(set) var lastSynced: Date?
    @Published var problem: String?

    private var folder: URL?
    var isOn: Bool { folder != nil }

    /// Reconnects to the folder picked last time, if there is one.
    init() {
        folder = Self.resolveBookmark()
        folderName = folder == nil ? nil : UserDefaults.standard.string(forKey: Self.nameKey)
    }

    // MARK: Setting up

    /// Remembers a folder you picked, so the app can reach it again after relaunching.
    /// Returns the budget already in that folder, if there is one.
    func connect(_ url: URL) throws -> BudgetState? {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: Self.nameKey)
        folder = Self.resolveBookmark() ?? url
        folderName = url.lastPathComponent
        problem = nil
        return try Self.read(folder: folder!).map { try JSONDecoder().decode(BudgetState.self, from: $0) }
    }

    /// Stops syncing. The file in the folder is left alone.
    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        folder = nil
        folderName = nil
        lastSynced = nil
        problem = nil
    }

    // MARK: Reading and writing

    /// The budget in the sync folder, or nil if there isn't one yet.
    func pull() async -> BudgetState? {
        guard let folder else { return nil }
        do {
            let data = try await Task.detached { try SyncFolder.read(folder: folder) }.value
            let s = try data.map { try JSONDecoder().decode(BudgetState.self, from: $0) }
            problem = nil
            lastSynced = Date()
            return s
        } catch SyncError.waitingForICloud {
            problem = SyncError.waitingForICloud.localizedDescription
            return nil
        } catch {
            problem = "Couldn’t read the sync folder: \(error.localizedDescription)"
            return nil
        }
    }

    /// True when the sync file isn't in iCloud, or this device has iCloud's newest copy of
    /// it. When it's false, iCloud is asked to download the newest copy, and nothing should
    /// be written: writing would replace changes from another device this one hasn't seen.
    func isUpToDate() async -> Bool {
        guard let folder else { return true }
        return await Task.detached { SyncFolder.isCurrent(folder: folder) }.value
    }

    /// Writes the budget to the sync folder. Called after every change. Errors show in
    /// `problem` (on the Setup screen) instead of interrupting the user.
    func push(_ state: BudgetState) async {
        guard let folder else { return }
        // Don't replace a newer copy from another device that iCloud hasn't delivered yet.
        // The next sync (within 30 seconds) compares the two once it has arrived.
        guard await isUpToDate() else {
            problem = SyncError.waitingForICloud.localizedDescription
            return
        }
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(state)
            try await Task.detached { try SyncFolder.write(data, folder: folder) }.value
            problem = nil
            lastSynced = Date()
        } catch {
            problem = "Couldn’t save to the sync folder: \(error.localizedDescription)"
        }
    }

    // MARK: File access

    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        #if os(macOS)
        let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
        guard let url else { return nil }
        // A moved folder still resolves, but the saved bookmark should be refreshed.
        if stale {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            #if os(macOS)
            let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
            if let fresh { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
        }
        return url
    }

    /// See `isUpToDate`. Files outside iCloud (or that iCloud doesn't report on) count as current.
    nonisolated private static func isCurrent(folder: URL) -> Bool {
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appendingPathComponent(fileName)
        // iCloud keeps a placeholder named ".Paycheck Plan.json.icloud" until the file downloads.
        let placeholder = folder.appendingPathComponent("." + fileName + ".icloud")
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        let target = FileManager.default.fileExists(atPath: file.path) ? file
            : FileManager.default.fileExists(atPath: placeholder.path) ? placeholder : nil
        guard let target else { return true }   // no file yet: an empty folder
        if target == placeholder {               // only the placeholder: not downloaded yet
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
            return false
        }
        guard let v = try? file.resourceValues(forKeys: keys), v.isUbiquitousItem == true,
              let status = v.ubiquitousItemDownloadingStatus else { return true }
        if status == .current { return true }
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        return false
    }

    /// Reads through a file coordinator, which also downloads the file from iCloud if needed.
    /// Throws `waitingForICloud` while iCloud is still bringing a newer copy, so a stale
    /// copy (or a missing one) isn't mistaken for the latest.
    nonisolated private static func read(folder: URL) throws -> Data? {
        guard isCurrent(folder: folder) else { throw SyncError.waitingForICloud }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appendingPathComponent(fileName)
        var result: Data?
        var inner: Error?
        var outer: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &outer) { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do { result = try Data(contentsOf: url) } catch { inner = error }
        }
        if let e = outer ?? inner { throw e }
        return result
    }

    /// Writes the file through NSFileCoordinator, so iCloud Drive or another sync app
    /// doesn't read a half-written file. `.atomic` writes to a temporary file first.
    nonisolated private static func write(_ data: Data, folder: URL) throws {
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appendingPathComponent(fileName)
        var inner: Error?
        var outer: NSError?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &outer) { url in
            do { try data.write(to: url, options: .atomic) } catch { inner = error }
        }
        if let e = outer ?? inner { throw e }
    }
}

enum SyncError: LocalizedError {
    case waitingForICloud
    var errorDescription: String? {
        "Waiting for iCloud to download the latest budget from your other device. This usually takes under a minute; keep the app open."
    }
}

extension BudgetState {
    /// When this copy was last changed, for deciding which copy is newer.
    var savedDate: Date {
        guard let s = savedAt else { return .distantPast }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s) ?? .distantPast
    }
}
