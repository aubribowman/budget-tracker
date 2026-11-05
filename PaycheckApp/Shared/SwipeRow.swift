import SwiftUI

/// One action revealed by swiping a row.
struct SwipeAction {
    let label: String
    let icon: String
    let color: Color
    let run: () -> Void
}

/// Swipe a row right or left past a point to run an action, like Mail.
/// Built by hand because the system's swipe actions only work in a List, and paycheck
/// rows live inside cards. On Mac it does nothing; rows there have right-click menus.
struct SwipeRow: ViewModifier {
    var leading: SwipeAction?      // swipe right
    var trailing: SwipeAction?     // swipe left
    @State private var dx: CGFloat = 0
    @State private var armed = false
    @GestureState private var dragging = false
    private let trigger: CGFloat = 80

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .background(Theme.card)    // covers the action color while resting
            .offset(x: dx)
            .background(alignment: dx > 0 ? .leading : .trailing) { revealed }
            .clipShape(RoundedRectangle(cornerRadius: Space.s, style: .continuous))
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .updating($dragging) { _, d, _ in d = true }
                    .onChanged { v in
                        // Only a mostly sideways drag moves the row, so scrolling still works.
                        guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                        var x = v.translation.width
                        if x > 0 && leading == nil || x < 0 && trailing == nil { x = 0 }
                        dx = x
                        let now = abs(x) > trigger
                        if now != armed { armed = now }
                    }
                    .onEnded { _ in
                        if armed { (dx > 0 ? leading : trailing)?.run() }
                        withAnimation(.snappy) { dx = 0 }
                        armed = false
                    }
            )
            // If scrolling takes over mid-swipe the drag is cancelled without onEnded,
            // so put the row back once the drag is gone.
            .onChange(of: dragging) { _, d in
                guard !d else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    if dx != 0 { withAnimation(.snappy) { dx = 0 }; armed = false }
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, new in new }
            .accessibilityActions {
                if let leading { Button(leading.label, action: leading.run) }
                if let trailing { Button(trailing.label, action: trailing.run) }
            }
        #else
        content
        #endif
    }

    @ViewBuilder private var revealed: some View {
        if let a = dx > 0 ? leading : dx < 0 ? trailing : nil {
            Label(a.label, systemImage: a.icon)
                .labelStyle(.iconOnly)
                .font(.ui(.headline))
                .foregroundStyle(.white)
                .scaleEffect(armed ? 1.15 : 0.9)
                .animation(.snappy, value: armed)
                .padding(.horizontal, Space.l)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dx > 0 ? .leading : .trailing)
                .background(armed ? a.color : a.color.opacity(0.5))
        }
    }
}

extension View {
    /// Swipe right for `leading`, left for `trailing`.
    func swipeRow(leading: SwipeAction? = nil, trailing: SwipeAction? = nil) -> some View {
        modifier(SwipeRow(leading: leading, trailing: trailing))
    }
}
