import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// iPhone-only touches, with a Mac version (or nothing) for each, so screens can
/// use them without checking the platform themselves.
extension View {
    /// Number keypad on iPhone. On Mac, a form would show the "0.00" placeholder as a
    /// separate label beside the box, so hide it there and let it act as a placeholder.
    func decimalPad() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        labelsHidden()
        #endif
    }

    /// Mac: keep cards a comfortable width and centered in a wide window.
    func readableWidth() -> some View {
        #if os(macOS)
        frame(maxWidth: 680).frame(maxWidth: .infinity)
        #else
        self
        #endif
    }

    /// Mac: sheets shrink to fit their content, so give them a sensible size and the
    /// iPhone-style grouped form look. Sheets are their own windows, so they get the zoom too.
    func macSheet() -> some View {
        #if os(macOS)
        formStyle(.grouped)
            .macZoom()
            .frame(minWidth: 460, idealWidth: 540, minHeight: 480, idealHeight: 680)
        #else
        self
        #endif
    }

    /// Mac: View → Zoom In / Zoom Out. Does nothing on iPhone, which has its own text size setting.
    func macZoom() -> some View {
        #if os(macOS)
        modifier(MacZoom())
        #else
        self
        #endif
    }

    /// Mac: iPhone-style grouped forms instead of the Mac's two-column layout.
    func macFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }

    /// Small title in the bar on iPhone. Mac windows always show it that way.
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// A "Done" button above the iPhone number keypad, which has no return key.
    func keyboardDoneButton(_ action: @escaping () -> Void = {}) -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { action(); hideKeyboard() }
            }
        }
        #else
        self
        #endif
    }
}

/// Puts the keyboard away on iPhone.
func hideKeyboard() {
    #if os(iOS)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

/// The system colors the app uses, in their iPhone and Mac versions.
enum SystemColor {
    #if canImport(UIKit)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let bg = Color(UIColor.systemGroupedBackground)
    static let track = Color(UIColor.tertiarySystemFill)
    #else
    static let card = Color(NSColor.controlBackgroundColor)
    static let bg = Color(NSColor.windowBackgroundColor)
    static let track = Color(NSColor.quaternaryLabelColor)
    #endif

    /// A color that switches between two shades for light and dark mode.
    static func adaptive(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        Color(NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? NSColor(dark) : NSColor(light)
        })
        #endif
    }
}

// MARK: - Mac zoom

/// Zoom levels for View → Zoom In / Zoom Out on Mac, like a web browser's.
enum Zoom {
    static let key = "macZoom"
    static let levels: [Double] = [0.75, 0.85, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]

    static func step(_ current: Double, by delta: Int) -> Double {
        let i = levels.firstIndex { $0 >= current - 0.001 } ?? levels.firstIndex(of: 1.0)!
        return levels[max(0, min(levels.count - 1, i + delta))]
    }

    static func label(_ z: Double) -> String { "\(Int((z * 100).rounded()))%" }
}

#if os(macOS)
/// Browser-style zoom: lays the screen out as if the window were smaller (or bigger),
/// then scales it to fill the window. Text re-flows the way it does in Safari, and
/// clicks still land in the right place. Text size settings don't apply on Mac, so this
/// is the way to make everything bigger.
private struct MacZoom: ViewModifier {
    @AppStorage(Zoom.key) private var zoom = 1.0

    func body(content: Content) -> some View {
        // Same structure at every zoom (100% included), so zooming never resets the
        // current tab or scroll position.
        GeometryReader { g in
            content
                .frame(width: g.size.width / zoom, height: g.size.height / zoom)
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
    }
}

/// The View menu items and their shortcuts.
struct ZoomCommands: Commands {
    @AppStorage(Zoom.key) private var zoom = 1.0

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In") { zoom = Zoom.step(zoom, by: 1) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(zoom >= Zoom.levels.last! - 0.001)
            Button("Zoom Out") { zoom = Zoom.step(zoom, by: -1) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(zoom <= Zoom.levels.first! + 0.001)
            Button("Actual Size") { zoom = 1 }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(abs(zoom - 1) < 0.001)
            Divider()
        }
    }
}
#endif
