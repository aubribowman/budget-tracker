import SwiftUI
import UniformTypeIdentifiers

/// Home before there's a budget: a short welcome and the two steps to set one up.
/// Home switches to the full budget as soon as the first bill or spending item is added.
struct EmptyStart: View {
    @EnvironmentObject var store: Store
    @State private var importing = false
    @State private var importFailed = false

    var body: some View {
        VStack(spacing: Space.l) {
            VStack(spacing: Space.s) {
                IconBadge(icon: "dollarsign.circle", color: Theme.accent, size: 60)
                Text("Plan every paycheck").font(.display(.title2, weight: .bold))
                Text("Give each paycheck a job before it lands. You'll see which bills it covers, what's left to spend, and when you'll be debt-free.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                NavigationLink { ScheduleView() } label: {
                    StartStep(number: 1, title: "Set your paydays",
                              detail: "How often you're paid and what you take home.")
                }
                Divider().padding(.leading, 52)
                NavigationLink { RecurringListView() } label: {
                    StartStep(number: 2, title: "Add your bills and spending",
                              detail: "Rent, subscriptions, groceries. Each one lands on the right paycheck.")
                }
            }
            .buttonStyle(.plain)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))

            Button { importing = true } label: {
                Label("Restore from a backup", systemImage: "square.and.arrow.down")
                    .font(.ui(.subheadline).weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .card()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), store.importBackup(data) { return }
            importFailed = true
        }
        .alert("Couldn't read that file", isPresented: $importFailed) { Button("OK") {} } message: {
            Text("Pick a backup made with Create a backup in Setup.")
        }
    }
}

/// One numbered step on the welcome card.
private struct StartStep: View {
    let number: Int
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: Space.m) {
            Text("\(number)")
                .font(.display(.headline, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(.headline)).foregroundStyle(.primary)
                Text(detail).font(.ui(.subheadline)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.ui(.caption).weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(Space.m)
        .contentShape(Rectangle())
    }
}
