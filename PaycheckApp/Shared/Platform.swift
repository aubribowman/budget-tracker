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

    /// Keep cards a comfortable width and centered in a wide Mac window or on iPad.
    /// iPhones are narrower than this, so it changes nothing there.
    func readableWidth() -> some View {
        frame(maxWidth: 680).frame(maxWidth: .infinity)
    }

    /// Mac: a list on the same gray background as the card screens, kept to a readable width.
    func macListLook() -> some View {
        #if os(macOS)
        scrollContentBackground(.hidden).readableWidth().background(SystemColor.bg)
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
    // The iPhone's grouped colors. The Mac's own window color is nearly white, so
    // white cards would disappear into it.
    static let card = adaptive(light: Color(red: 1, green: 1, blue: 1), dark: Color(red: 0.17, green: 0.17, blue: 0.18))
    static let bg = adaptive(light: Color(red: 0.949, green: 0.949, blue: 0.969), dark: Color(red: 0.11, green: 0.11, blue: 0.118))
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

    /// The next level up (+1) or down (-1) from the current zoom, stopping at the ends.
    static func step(_ current: Double, by delta: Int) -> Double {
        let i = levels.firstIndex { $0 >= current - 0.001 } ?? levels.firstIndex(of: 1.0)!
        return levels[max(0, min(levels.count - 1, i + delta))]
    }

    /// "115%".
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

/// iPad: a tab's big title, drawn in the page so it lines up with the centered cards
/// (the system draws its own at the screen's left edge, away from them). Put it first
/// in the page and use `.pageTitle` instead of `.navigationTitle`. Shows nothing on
/// iPhone or Mac, which keep their usual titles.
struct PageTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var size
    #endif

    var body: some View {
        #if os(iOS)
        if size == .regular {
            Text(title)
                .font(.display(.largeTitle, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Space.xs)
                .accessibilityAddTraits(.isHeader)
        }
        #endif
    }
}

/// The navigation title for a tab with a `PageTitle`. On iPad the bar's copy is hidden,
/// so the title isn't shown twice; it's still used for the app switcher and VoiceOver.
private struct PageTitleBar: ViewModifier {
    let title: String
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var size
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        // The big title can't be hidden, so make it the small one first, then hide that.
        content.navigationTitle(title)
            .navigationBarTitleDisplayMode(size == .regular ? .inline : .large)
            .toolbar(removing: size == .regular ? .title : nil)
        #else
        content.navigationTitle(title)
        #endif
    }
}

extension View {
    /// Use instead of `.navigationTitle` on a tab that shows a `PageTitle`.
    func pageTitle(_ title: String) -> some View { modifier(PageTitleBar(title: title)) }
}
