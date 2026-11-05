import SwiftUI

/// Shown when there's no budget yet: how to bring one over from the web app.
struct EmptyStart: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down").font(.largeTitle).foregroundStyle(Theme.accent)
            Text("Bring your budget over").font(.title3.bold())
            Text("In the web app, open Setup and tap Download a backup. Then in this app tap the gear on Home, choose Import a backup, and pick that file.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).card()
    }
}
