import SwiftUI

/// What a list or card shows when there's nothing in it: an icon, a short line, and
/// optionally the button that fixes it. Friendlier than a line of gray text.
struct EmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil
    var color: Color = Theme.accent
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Space.s) {
            IconBadge(icon: icon, color: color, size: 52)
            Text(title).font(.display(.headline, weight: .semibold)).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.ui(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.m)
    }
}
