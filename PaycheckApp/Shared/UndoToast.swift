import SwiftUI

/// "Rent marked paid · Undo" along the bottom for a few seconds after a status change,
/// so a mis-tap is one tap to fix. Shown by RootView from `store.undoNote`.
struct UndoToast: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ZStack {
            if let note = store.undoNote {
                HStack(spacing: Space.m) {
                    Text(note.text).lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Undo") { withAnimation(.snappy) { store.undo() } }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.borderless)
                }
                .font(.ui(.subheadline))
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.horizontal)
                .frame(maxWidth: 480)
                .padding(.bottom, Self.bottomGap)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(note.id)
                // Goes away on its own after 5 seconds; a newer change replaces it.
                .task(id: note.id) {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    if store.undoNote?.id == note.id { withAnimation(.snappy) { store.undoNote = nil } }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: "Undo") { store.undo() }
            }
        }
        .animation(.snappy, value: store.undoNote)
    }

    /// Clear of the iPhone's floating tab bar.
    #if os(iOS)
    static let bottomGap: CGFloat = 76
    #else
    static let bottomGap: CGFloat = 20
    #endif
}
